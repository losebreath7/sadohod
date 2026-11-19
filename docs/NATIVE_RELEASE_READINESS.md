# Native release checklist — Садоход (buyer + seller)

This is a build readiness checklist, **not** proof of store submission readiness.

## Apps and identifiers

| App | Android applicationId | iOS Bundle ID |
| --- | --- | --- |
| Buyer | `ru.sadohod.sadohod` | `ru.sadohod.sadohod` |
| Seller | `ru.sadohod.seller` | `ru.sadohod.seller` |

Confirm identifiers and seller icon **before the first store release**; changing an app identifier later requires a new store listing.

## What CI verifies with no developer accounts

The root `gate` invokes `buyer-native.yml` and `seller-native.yml` on **every** PR to develop/main and pushes to develop/main. For both applications:
- Ubuntu + Flutter 3.50.0 + JDK 17: `flutter build apk --debug`.
- macOS + Xcode + Flutter 3.50.0: `flutter build ios --simulator --no-codesign`.
- Native failures cause the root `gate` job to fail; a green Flutter Web build cannot conceal an Android/iOS error.
- The debug Android APK is an installable development artifact. The iOS simulator build is **not** a signed device build and **not** an App Store IPA.
- Example `API_BASE_URL=https://example.invalid` is intentional; CI tests buildability and does **not** validate the live backend.
- `python tools/test_native_config.py` checks declared permissions, bundle IDs, signing guards and tracked signing files.

The CI script verifies declared permissions, not the final merged Android manifest from all plugins. Review that merged manifest and device permission prompts before submission.

## Android Google Play — signed AAB still required

For **each app separately**:
1. Register or access Google Play Console and create the corresponding application record.
2. Approve the final application ID and required app information.
3. Generate a distinct **upload keystore** outside Git; back up the keystore and all credentials securely, offline. Do not transmit secrets in chats, commits or build logs.
4. Copy `<app>/android/key.properties.example` to `<app>/android/key.properties`; set `storeFile`, `storePassword`, `keyAlias`, `keyPassword`. All real `key.properties`, `.jks`, `.keystore` are Git-ignored.
5. Point `API_BASE_URL` to the real public HTTPS backend, with no demo data. From `buyer_app` or `seller_app`:
   ```sh
   flutter pub get
   flutter build appbundle --release --dart-define=API_BASE_URL=https://YOUR-PRODUCTION-API
   ```
6. Verify the resulting AAB is signed using the intended upload certificate and inspect the merged release AndroidManifest, SDK levels, package ID, permissions and included third-party SDKs.
7. Use Play App Signing, complete Data safety, privacy policy, content rating, store images, support information, testing requirements and release track configuration.

**Important:** Without `key.properties`, the release configuration does not substitute the debug keystore. An unsigned artifact cannot be submitted to Google Play.

## Apple App Store — signed iOS release still required

For **each app separately**:
1. Enroll in Apple Developer and configure App Store Connect, seller/buyer Bundle IDs, display names, icons, privacy manifest declarations and entitlement requirements.
2. Create an App ID for the exact Bundle ID, assign the Apple Developer Team, signing certificate and provisioning profile (automatic signing via Xcode is acceptable).
3. On macOS with Xcode and Flutter installed, set the production HTTPS API endpoint and build an iOS **device archive / signed IPA**:
   ```sh
   flutter pub get
   flutter build ipa --release --dart-define=API_BASE_URL=https://YOUR-PRODUCTION-API
   ```
4. Validate signing, entitlements, minimum iOS target, device support, permissions, screenshots, privacy questionnaire, age rating and App Store Connect metadata.
5. Upload a signed IPA/archive to App Store Connect, test through TestFlight on physical devices and submit for App Review.

`flutter build ios --simulator --no-codesign` uses the simulator SDK and does **not** produce a signed distributable iOS app. Signing for physical iPhones or App Store cannot be completed in this repository without an authorized Apple Developer account.

## Physical-device acceptance tests (pending)

On Android and iOS for both apps: install a correctly signed development/TestFlight build; authenticate by email; persist session across restart; check camera/photo library permissions, file picker, upload, image replacement, navigation, keyboard, SafeArea, notifications, background/foreground, device rotation, offline errors, large files, slow connections, and backend HTTPS certificate validation. Specifically verify seller's six-image limit and camera flow *without changing the implementation*.

**Not done by CI:** store signing, on-device interactive tests, verification of actual Play/App Store policies, and production backend connectivity.
