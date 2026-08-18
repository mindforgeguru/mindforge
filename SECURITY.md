# Security runbook

Operational security notes for MindForge. This documents the manual,
console-side hardening that lives outside the codebase.

> For the full threat picture — every risk class, scored verified / stale / open —
> see [`SECURITY_RISK_REGISTER.md`](SECURITY_RISK_REGISTER.md). The Firebase key
> restriction below is one open item in it.

## Firebase client API keys — restrict in Google Cloud Console

**Context.** The `AIza…` keys shipped in the app (`google-services.json`,
`GoogleService-Info.plist`, `lib/firebase_options.dart`) are Firebase **client**
keys. They are public by design — they identify the Firebase project, not a
secret — and the app only uses Core, FCM, Analytics and Crashlytics (no
Firestore / Storage / Realtime DB / Firebase Auth), so a copied key cannot read
or write user data. The realistic worst case is API-quota abuse. Restricting
the keys is **defense-in-depth**, not a leak response.

**The real server secret** is `FIREBASE_CREDENTIALS_JSON` (Firebase Admin SDK,
used for server-side push). It is externalised as an environment variable and is
**not** committed. Keep it that way; rotate it via the Firebase console
(Project settings → Service accounts) if it is ever exposed.

### Project
- Firebase project: `mindforge-b2324`  (project number `98913884574`)
- Console: https://console.cloud.google.com/apis/credentials?project=mindforge-b2324

### Keys and the restriction each should carry

| Key | Value | App | Application restriction |
| --- | --- | --- | --- |
| Android | `AIzaSyCZ7yTGCVV-klJtoan9whSmGBkMMgIASMw` | `com.mindforge.mindforge` | **Android apps**: package name + release SHA-1 |
| iOS | `AIzaSyBqeTY2qzb4f4yATvI2dIOW6TW3uAAQz0A` | `com.mindforge.mindforge` | **iOS apps**: bundle id |
| Web | `AIzaSyDYmYmBqhgnQQKtPhLpzd7xnrnxQGFpE0M` | `mindforge.guru` | **Websites (HTTP referrers)** |

### Release signing SHA-1 (for the Android key)
```
E6:FC:3E:97:AE:32:02:3E:C0:CA:71:7E:0C:C7:B6:E1:D3:EF:B9:7D
```
Regenerate any time with (macOS, using Android Studio's bundled JDK):
```
"/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool" \
  -list -v -keystore frontend/android/app/mindforge-release.jks \
  -alias mindforge -storepass <storePassword> | grep -i sha
```
(The keystore password lives in `frontend/android/key.properties`, which is
gitignored — never commit it.)

> Note: if you ever enable **Play App Signing**, Google re-signs your app with a
> *different* upload/app-signing key. Add that key's SHA-1 (from Play Console →
> Setup → App integrity) to the Android key too, or FCM/Analytics break in the
> Play build.

### Steps (per key)
1. Open the console link above → **APIs & Services → Credentials**.
2. Click the key → **Application restrictions**:
   - **Android**: choose *Android apps* → add package `com.mindforge.mindforge`
     with the SHA-1 above.
   - **iOS**: choose *iOS apps* → add bundle id `com.mindforge.mindforge`.
   - **Web**: choose *Websites* → add referrers:
     `mindforge.guru/*`, `www.mindforge.guru/*`,
     `mindforge-b2324.firebaseapp.com/*` (Firebase's auth/hosting domain).
3. **Save.** Application restrictions are the high-value, low-risk step — do
   these first.

### Optional: API restrictions (test carefully)
Under **API restrictions**, "Restrict key" and allowlist only the APIs the app
uses: *Firebase Installations API*, *Firebase Cloud Messaging API* (+ FCM
Registration), *Firebase Management API* as needed. **Under-scoping silently
breaks Analytics/Crashlytics** — after applying, do a fresh app launch and send
a test push before declaring it done. If anything breaks, widen the allowlist or
revert to "Don't restrict key".

### Verification
- Android/iOS release build launches, receives a push, and Analytics/Crashlytics
  still report.
- Web build (`mindforge.guru`) loads and initialises Firebase without console
  errors.

## Related backend guards (in code)
- **Default-credential guard**: the backend refuses to start in production
  (`APP_ENV=production`) if MinIO/DB/Redis are on their built-in default
  credentials — see `backend/app/core/config.py`.
- **Media proxy**: `/api/media/{bucket}/{key}` is unauthenticated, so profile
  object keys must stay unguessable — see `storage_service.profile_object_key`.
- **JWT**: `JWT_SECRET` has no default; the app won't start without it.
