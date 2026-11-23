# Mobile store release runbook (buyer + seller)

**State:** release engineering preparation only. The release version stays at `0.8.4+27`; **do not publish or switch to 1.0.0** until product, legal, security and device acceptance are signed off.

## Identity and artifacts

| Client | Flutter directory | Android applicationId / iOS bundle ID | Expected artifact |
|---|---|---|---|
| Buyer | `buyer_app/` | `ru.sadohod.sadohod` | signed AAB / signed IPA |
| Seller | `seller_app/` | `ru.sadohod.seller` | signed AAB / signed IPA |

Both use `RELEASE.json` and `tools/sync_version.py --check`. Avoid manually overriding the Flutter build name or build number. For any new store upload, increase the build number using the established version synchronizer only after authorisation. Already used build numbers cannot be uploaded again to the same app record.

## GitHub Actions (manual release candidates)

Workflow: `.github/workflows/native-store-candidates.yml`. Runs on `workflow_dispatch`, separately by platform and app. `mobile-release` is a **protected GitHub Environment**; configure required reviewers, restrict deployment branches and restrict who can change environment secrets. Only dispatch from reviewed release branches. Do not grant third-party workflows untrusted PR access to the environment.

**Android environment secrets, all per app**:
- `BUYER_ANDROID_KEYSTORE_BASE64`, `BUYER_ANDROID_KEY_ALIAS`, `BUYER_ANDROID_KEY_PASSWORD`, `BUYER_ANDROID_STORE_PASSWORD`.
- `SELLER_ANDROID_KEYSTORE_BASE64`, `SELLER_ANDROID_KEY_ALIAS`, `SELLER_ANDROID_KEY_PASSWORD`, `SELLER_ANDROID_STORE_PASSWORD`.

Use *upload keys*, not the Play app-signing private key. Register the upload certificates separately for the two Play Console apps. Back up original keys securely outside GitHub (encrypted, controlled access). The workflow temporarily decodes a keystore and writes `android/key.properties` in the runner, enforces `SADOHOD_REQUIRE_RELEASE_SIGNING=true` in Gradle, and removes the files afterward. These files are already covered by Git ignore rules. The generated AAB must also pass the Play Console signature check.

**iOS environment secrets**:
- `IOS_DISTRIBUTION_P12_BASE64`: Apple Distribution certificate + private key packaged as PKCS#12, base64 encoded.
- `IOS_DISTRIBUTION_P12_PASSWORD`: password of the PKCS#12.
- `IOS_TEAM_ID`: Apple Developer team identifier.
- `BUYER_IOS_PROFILE_BASE64` and `SELLER_IOS_PROFILE_BASE64`: separate App Store distribution provisioning profiles for the corresponding bundle identifiers.

These are configured **inside GitHub Settings > Environments > mobile-release > Environment secrets**, never in chat, source control, or workflow logs. A protected macOS runner imports the certificate into a transient keychain and configures the selected Runner target for manual signing. The workflow validates profile Team ID, builds the IPA and exports an artifact. TestFlight upload is a separate, explicit operator step; there is **no automatic submission or publication**.

The first run requires validation against real Apple provisioning profiles and certificates. Mac/Xcode compatibility, signing entitlements, Apple account agreements, and Apple distribution rules cannot be confirmed from repository code alone.

## Before release candidates

1. Confirm control of both Apple bundle IDs and Android package IDs; register four separate app records (two in Google Play, two in App Store Connect). Do not change identifiers after publication.
2. Confirm active Apple Developer membership, paid Google Play developer access, accepted current agreements, required business identity and appropriate roles. Where the stores require verification, complete it in their own portals.
3. Confirm `https://api.sadohod.ru/health` answers via valid public TLS, stable DNS, without a hosting provider IP embedded in the applications. Test sign-in, catalogs, media and uploads on the same domain. The workflow fixes `API_BASE_URL=https://api.sadohod.ru` for all builds.
4. Run Flutter analyze/tests and review plugin permissions, Android merged manifest, release `targetSdk`, Android 64-bit/native library policy, iOS privacy manifests, entitlements, `Info.plist` usage descriptions and secure storage integration. Remove development-only local-network permissions only if no runtime use remains.
5. Verify final **distinct approved** launcher icons (Android adaptive/monochrome if required, iOS opaque 1024px), launch screens, correct Cyrillic display names, physical device screenshots, store descriptions, support contact, privacy/legal URLs, age rating and data safety/App Privacy questionnaires.
6. Check Android Play App Signing, upload certificates, app bundle integrity and Play Console policy warnings. Check Apple certificate/profile expiry and code signature validity.

## Four manual workflow runs

GitHub > Actions > **Native store release candidates** > **Run workflow**:
- buyer_app / android
- seller_app / android
- buyer_app / ios
- seller_app / ios

Each run must explicitly select the fixed production API origin. Download resulting artifacts only from the protected Actions run. Successful build means *candidate available*, not automatically store-ready.

## Physical device acceptance (both apps)

Test at least one current and one older supported Android device, and at least one current iPhone plus a supported older iPhone running iOS 15+ (where available). Use **store-distributed** internal builds, not only debug installs.

- Cold start, onboarding / guest entry, sign in by email code, sign out, relaunch and session restore; verify that buyer and seller sessions remain independent.
- Camera permission denied/allowed, selection from gallery, network loss during upload; retry without duplicate photos or products; iOS photo limited access, Android Photo Picker behavior.
- Buyer: text search, photo search, catalogue filters, product cards, sellers, favourites, reviews, navigation, messaging, help.
- Seller: pavilion review/approval, upload, product pricing and status, moderation outcomes, search and editing, notifications, profile, support/cooperation, camera.
- Slow/no network, server errors, expired session, app upgrade from previous installed version, background/foreground, force quit and reopening.
- Display under notch/Dynamic Island and Android system navigation; keyboard safe areas, scrolling and media permissions on physical screens.
- Validate release requests use `api.sadohod.ru`, no `localhost`, `10.0.2.2`, `USE_LOCAL_DEMO` or `FIGMA_PREVIEW`; inspect crash logs without recording user tokens.
- Check on-store installations and updates via Google Play internal testing and TestFlight, including tester invitation and access.

## Upload & acceptance gates

- **Google Play:** create each app record; enable Play App Signing and enroll correct upload certificate; upload the matching signed AAB to internal testing; inspect policy/data safety forms and pre-launch reports. Only promote after test sign-off.
- **Apple:** create each app record with exact Bundle ID; upload signed IPA through Transporter/Xcode or appropriately scoped App Store Connect tooling; wait for processing; distribute to internal TestFlight testers; handle any compliance/export questions. Only submit after sign-off.
- Keep version at `0.8.4+27` until coordinated release planning. Never claim signed artifacts, store delivery, or physical validation without successful run evidence.
- **Stop conditions:** missing environment secrets, wrong identifiers, unverified TLS/API, failing tests, unverified signing certificates, duplicate build number, rejected store upload, or any broken critical buyer/seller flow.

## Release evidence to retain

Record for each of four runs: git commit SHA, app + platform, version/build, Actions URL and result, SHA-256 of downloaded artifact, signature identity (no private keys), tested device/OS, store internal track/build identifier, tester outcome and unresolved store warnings.
