# Codemagic CI for Flutter iOS builds

This project includes a `codemagic.yaml` with three workflows:

- ios_testflight: Builds a signed IPA and uploads to TestFlight via App Store Connect.
- ios_adhoc: Builds a signed Ad Hoc IPA you can install on specific devices by UDID.
- ios_unsigned_archive: Builds an unsigned iOS archive (no Apple account), to be opened/sign in Xcode later.

## Setup (Codemagic UI)
1. Connect your GitHub repo to Codemagic.
2. In App Settings > Build > Build mode: Enable `Use codemagic.yaml`.
3. Create a Variable Group named `app_store_connect` with:
   - APP_STORE_CONNECT_ISSUER_ID
   - APP_STORE_CONNECT_KEY_IDENTIFIER
   - APP_STORE_CONNECT_PRIVATE_KEY (add as Secure)
   - BUNDLE_ID (e.g., com.yourcompany.yourapp)
4. Start a build with workflow `ios_testflight`, `ios_adhoc`, or `ios_unsigned_archive`.

## Share to iPhone/iPad

You have two paths:

1) TestFlight (recommended for ongoing testing)
   - Requires an App Store Connect app with the same Bundle ID.
   - In Codemagic, run the `ios_testflight` workflow.
   - After the build, Apple processes the binary (5–30 minutes). Invite testers from App Store Connect > TestFlight.

2) Ad Hoc install (direct .ipa for specific devices)
   - You must register the device UDIDs in your Apple Developer account under Certificates, Identifiers & Profiles > Devices.
   - Ensure you have an Ad Hoc provisioning profile that includes those devices.
   - In Codemagic, run the `ios_adhoc` workflow. Download the .ipa artifact.
   - Install options:
     - Using Apple Configurator 2 (Mac): Connect the device via USB and drag-drop the .ipa.
     - Using Diawi or Firebase App Distribution: Upload the .ipa and share the link. Note: Ad Hoc constraints still apply (UDID must be provisioned).
     - Using iTunes (older macOS): Add the .ipa and sync the device.

## Notes
- Ensure `ios/Runner.xcodeproj` and `ios/Runner.xcworkspace` exist (Flutter created them).
- Update your app name, icons, and `CFBundleIdentifier` in `ios/Runner/Info.plist` if needed.
- For TestFlight, your bundle ID must match the one registered in Apple Developer.
- The unsigned archive can be downloaded and opened on a Mac, then signed/notarized via Xcode.
 - For Ad Hoc, make sure every target (Runner, extensions if any) uses the Ad Hoc provisioning profile and that devices are included.
