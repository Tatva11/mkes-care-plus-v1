# MKES CARE+ — Firebase Service Account Configuration

To enable real-device server-to-client push notifications via Firebase Cloud Messaging (FCM):

1. Go to the [Firebase Console](https://console.firebase.google.com/).
2. Select your MKES CARE+ project.
3. Navigate to **Project Settings** &rarr; **Service accounts**.
4. Click **Generate new private key**.
5. Save the downloaded JSON file as:
   `whatsapp-service/config/firebase-service-account.json`
   *(or set the environment variable `FIREBASE_SERVICE_ACCOUNT_KEY` to the absolute path of this file).*

When this file is present, `PushNotificationBackend` automatically initializes `firebase-admin` and delivers high-priority lock-screen push notifications to registered staff and admin devices.

When this file is absent, `PushNotificationBackend` operates in safe simulated dry-run mode, recording device tokens in Supabase `user_device_tokens` without causing crashes or errors.
