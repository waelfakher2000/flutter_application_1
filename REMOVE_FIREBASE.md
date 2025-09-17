This project has been de-Firebase-ified.

Removed:
- firebase.json, .firebaserc
- functions/ (Cloud Functions for Firebase)
- android/app/google-services.json and any Gradle plugin references
- mqtt-fcm-bridge/ (FCM bridge) and Firebase service account
- Any Firebase mentions in docs

Notes:
- The app uses local notifications only.
- If you need to restore Firebase later, set up FlutterFire and re-add configs.
