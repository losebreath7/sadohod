"""Offline tests for malformed tar uploads/state snapshots."""
import io
from pathlib import Path
import sys
import tarfile
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from verify_backup_archive import verify_and_extract


def make(path: Path, entries):
    with tarfile.open(path, "w:gz") as tar:
        for name, kind in entries:
            info = tarfile.TarInfo(name)
            if kind == "directory":
                info.type = tarfile.DIRTYPE
                info.mode = 0o700
                tar.addfile(info)
            elif kind == "symlink":
                info.type = tarfile.SYMTYPE
                info.linkname = "/etc/passwd"
                tar.addfile(info)
            else:
                b = kind.encode()
                info.size = len(b)
                tar.addfile(info, io.BytesIO(b))


def rejected(path):
    try:
        verify_and_extract(path)
    except (ValueError, tarfile.TarError):
        return
    raise AssertionError(f"Malformed archive accepted: {path}")


def main():
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        good = root / "good.tar.gz"
        make(good, [("uploads", "directory"), ("state", "directory"),
                    ("uploads/a.jpg", "photo bytes"), ("state/admin.json", "{}")])
        out = root / "restored"
        verify_and_extract(good, out)
        assert (out / "uploads/a.jpg").read_text() == "photo bytes"
        assert (out / "state/admin.json").read_text() == "{}"
        malicious = [
            [("uploads", "directory"), ("state", "directory"), ("uploads/../../escape", "x")],
            [("uploads", "directory"), ("state", "directory"), ("/uploads/absolute", "x")],
            [("uploads", "directory"), ("state", "directory"), ("uploads/pointer", "symlink")],
            [("uploads", "directory"), ("state", "directory"), ("state/data", "x"),
             ("state/data", "repeat")],
            [("uploads", "directory"), ("other", "directory")],
        ]
        for i, entries in enumerate(malicious):
            path = root / f"unsafe{i}.tar.gz"
            make(path, entries)
            rejected(path)
    print("Archive validator: good extraction and 5 unsafe input cases passed")


if __name__ == "__main__":
    main()
