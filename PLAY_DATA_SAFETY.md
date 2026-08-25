# Play Console Data safety (Scrapyard)

Fill this in Play Console → App content → Data safety. Values below match the current app and [PRIVACY.md](PRIVACY.md).

## Overview

- **No user accounts.** Notes stay on-device.
- **No ads, no Advertising ID.**
- **No analytics SDK.** Dart errors go to logcat / the engine handler; they are not uploaded unless the user sends feedback.
- Optional sharing only happens when the user uses Smelt/Ask (Google Gemini) or taps Send on feedback.

## Data collected / shared

| Data type | Collected by Scrapyard? | Shared? | Why |
|---|---|---|---|
| Notes, handwriting, PDFs, chat transcripts, Gemini API key | No (on-device only) | No | Stored locally; Android backup is disabled |
| Selected scraps / chat messages / Smelt crops | No | **Yes — Google Gemini**, only if the user saved an API key and used Smelt or Ask | App functionality |
| Gemini API key | No | **Yes — Google**, only as `x-goog-api-key` on those same requests | App functionality |
| Feedback message, kind, optional email, app version, platform | **Yes**, only if Send is tapped | **Yes — developer email via Resend** | App functionality / support |
| Reported Smelt/Ask output | **Yes**, only if Report is sent | **Yes — developer email** | Support / safety |

## Answers to Console questions

- Does your app collect or share any of the required user data types? **Yes** (optional feedback; optional Gemini sharing).
- Is all user data encrypted in transit? **Yes** (HTTPS). The MathReader sidecar uses loopback HTTP only (`localhost`).
- Do you provide a way for users to request that their data is deleted? **Yes** — notes and chats can be deleted in-app; the API key can be removed; feedback already sent cannot be recalled from Google or from an email already delivered.

## Security practices

- `android:allowBackup="false"` plus exclude-all backup / device-transfer rules.
- Gemini key in `flutter_secure_storage` (`encryptedSharedPreferences` on Android).
- Release App Bundles must be signed with the upload keystore in `android/key.properties` (gitignored). `flutter run --release` may still use the debug key locally.

## Before every Play upload

1. Copy `android/key.properties.example` → `android/key.properties` and generate an upload `.jks` if you have not already. Back both up off this machine.
2. `flutter build appbundle --release`
3. `python tools/verify_16kb_page_size.py --aab build/app/outputs/bundle/release/app-release.aab`
4. Install the minified release on a physical device and smoke-test drawing, Smelt, Ask, OCR, and Quick calc (R8 is on).
5. Bump `version:` in `pubspec.yaml` (`1.0.0+N`).
