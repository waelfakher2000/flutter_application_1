MQTT → FCM Bridge
===================

Small Node.js bridge that subscribes to an MQTT alarm topic and forwards alarm messages to Firebase Cloud Messaging (FCM).

Why use this
- FCM delivers notifications reliably to devices even when the app is terminated.
- Keeps push logic out of client devices and avoids relying on foreground services.

Setup
1. Create a Firebase project at https://console.firebase.google.com/
2. Create a Service Account credentials JSON (Project Settings → Service accounts → Generate new private key).
3. Save the downloaded file as `service-account.json` inside this `mqtt-fcm-bridge/` folder **or** set `SERVICE_ACCOUNT_PATH` env var to the file path.

Install and run

```bash
cd mqtt-fcm-bridge
npm install
# optionally set env vars: MQTT_URL, MQTT_TOPIC, FCM_TOPIC, SERVICE_ACCOUNT_PATH, MQTT_USERNAME, MQTT_PASSWORD
npm start
```

Defaults
- MQTT broker: mqtt://mqtt.mautoiot.com:1883
- MQTT topic to subscribe: `alarms/#`
- FCM topic to publish: `alarms`

Testing
- From any MQTT publisher, publish to `alarms/<deviceId>` or `alarms/test` with a short payload.
- Devices must be subscribed to the FCM topic `alarms` (in the app call `FirebaseMessaging.instance.subscribeToTopic('alarms')`) or you can change the bridge to target specific device tokens.

Device registration API
-----------------------
This bridge now supports registering device tokens and per-device alarm topics/thresholds.

- Register a device (POST JSON to `/register`):

```json
POST /register
{
	"deviceId": "device123",
	"token": "<fcm-device-token>",
	"topic": "sensors/device123/level",
	"thresholds": { "min": 10, "max": 90 }
}
```

- Unregister:

```json
POST /unregister
{ "deviceId": "device123" }
```

- Status:

```
GET /status
```

Behavior
- The bridge subscribes to MQTT wildcard topics and, when a message arrives, checks all registered devices whose `topic` matches the MQTT topic and evaluates thresholds. If a threshold is exceeded the bridge sends an FCM notification directly to the device token.

Flutter integration
- In your app, after obtaining the FCM token (`FirebaseMessaging.instance.getToken()`), POST it to the bridge `/register` along with the topic the user entered and the configured thresholds. I can implement the Dart code for this registration step if you want.

Security
- Keep `service-account.json` private. Do not commit it to source control. This repo includes a `.gitignore` to ignore it.

Customizations you might want
- Target specific tokens instead of a topic (bridge could map MQTT subtopics to device tokens via a database).
- Add filtering or rate limiting.
- Run on Cloud Run / a small VM for reliability.
