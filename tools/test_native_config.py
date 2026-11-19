"""Static native release-safety checks for buyer and seller.

Run from repository root; does not require Flutter or developer accounts.
"""
from pathlib import Path
import plistlib
import re
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
ANDROID_NS = "{http://schemas.android.com/apk/res/android}"
IDS = {"buyer_app": "ru.sadohod.sadohod", "seller_app": "ru.sadohod.seller"}
ALLOWED_PERMISSIONS = {"android.permission.INTERNET", "android.permission.CAMERA"}


def verify(app: str, expected: str) -> None:
    base = ROOT / app
    gradle = (base / "android/app/build.gradle.kts").read_text()
    match = re.search(r'applicationId\s*=\s*"([^"]+)"', gradle)
    assert match and match.group(1) == expected, (app, "Android applicationId")
    assert f'namespace = "{expected}"' in gradle, (app, "Android namespace")
    assert "releasePropsFile.exists()" in gradle and "signingConfig = if (releasePropsFile.exists())" in gradle, (app, "release signing not conditional")
    assert 'getByName("debug")' not in gradle, (app, "debug signing used for release")

    manifest = ET.parse(base / "android/app/src/main/AndroidManifest.xml").getroot()
    perms = {el.attrib[ANDROID_NS + "name"] for el in manifest.findall("uses-permission")}
    assert perms == ALLOWED_PERMISSIONS, (app, "Unexpected permissions", perms)
    application = manifest.find("application")
    assert application is not None and application.attrib.get(ANDROID_NS + "allowBackup") == "false", (app, "backup")

    with (base / "ios/Runner/Info.plist").open("rb") as f:
        info = plistlib.load(f)
    assert info["CFBundleIdentifier"] == "$(PRODUCT_BUNDLE_IDENTIFIER)"
    for key in ("NSCameraUsageDescription", "NSPhotoLibraryUsageDescription"):
        assert isinstance(info.get(key), str) and info[key].strip(), (app, key)
    pbx = (base / "ios/Runner.xcodeproj/project.pbxproj").read_text()
    ids = set(re.findall(r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^;]+);', pbx))
    ids = {v.strip().strip('"') for v in ids}
    assert expected in ids, (app, "iOS bundle ID")
    assert all(v == expected or v == expected + ".RunnerTests" for v in ids), (app, "unexpected iOS bundle ID", ids)
    assert not (base / "android/key.properties").exists(), (app, "local key.properties must not be committed")


def test_configuration() -> None:
    assert len(set(IDS.values())) == len(IDS), "Buyer and seller IDs must differ"
    for app, expected in IDS.items():
        verify(app, expected)

    tracked = subprocess.check_output(["git", "-C", str(ROOT), "ls-files"], text=True).splitlines()
    forbidden = [p for p in tracked if
                 p.endswith((".jks", ".keystore", ".p12", ".mobileprovision"))
                 or p.endswith("/key.properties")]
    assert not forbidden, ("Signing material tracked by Git", forbidden)
    gate = (ROOT / ".github/workflows/gate.yml").read_text()
    for token in ("buyer_native:", "seller_native:", "test \"$BUYER_NATIVE\" = success",
                  "test \"$SELLER_NATIVE\" = success"):
        assert token in gate, ("Missing native gate check", token)


if __name__ == "__main__":
    test_configuration()
    print("Native configurations: OK")
