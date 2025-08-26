// mqtt-to-fcm.js
// MQTT -> FCM bridge with HTTP registration API and threshold checks.

const mqtt = require('mqtt');
const admin = require('firebase-admin');
const express = require('express');
const bodyParser = require('body-parser');
const path = require('path');
const fs = require('fs');

const DATA_FILE = path.join(__dirname, 'devices.json');
let devices = {}; // structure: { deviceId: { token, topic, thresholds: {min, max} } }

function loadDevices() {
  if (fs.existsSync(DATA_FILE)) {
    try { devices = JSON.parse(fs.readFileSync(DATA_FILE)); } catch(e){ console.error('devices.json parse error', e); }
  }
}
function saveDevices() {
  try { fs.writeFileSync(DATA_FILE, JSON.stringify(devices, null, 2)); } catch(e) { console.error('save devices error', e); }
}

loadDevices();

const SERVICE_ACCOUNT_PATH = process.env.SERVICE_ACCOUNT_PATH || path.join(__dirname, 'service-account.json');
if (!fs.existsSync(SERVICE_ACCOUNT_PATH)) {
  console.error('Missing Firebase service account JSON. Place it at', SERVICE_ACCOUNT_PATH, 'or set SERVICE_ACCOUNT_PATH env var.');
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(require(SERVICE_ACCOUNT_PATH))
});

const MQTT_URL = process.env.MQTT_URL || 'mqtt://mqtt.mautoiot.com:1883';
const MQTT_DEFAULT_TOPIC = process.env.MQTT_TOPIC || '#';
const MQTT_OPTIONS = {
  username: process.env.MQTT_USERNAME,
  password: process.env.MQTT_PASSWORD,
  connectTimeout: 30 * 1000
};

console.log('MQTT -> FCM bridge starting');
console.log('MQTT_URL=', MQTT_URL);

const client = mqtt.connect(MQTT_URL, MQTT_OPTIONS);

client.on('connect', () => {
  console.log('MQTT connected');
  // subscribe to default wildcard; we will filter per-message
  client.subscribe(MQTT_DEFAULT_TOPIC, { qos: 1 }, (err, granted) => {
    if (err) return console.error('Subscribe error:', err);
    console.log('Subscribed to', MQTT_DEFAULT_TOPIC, 'granted=', granted);
  });
});

client.on('reconnect', () => console.log('MQTT reconnecting...'));
client.on('error', (err) => console.error('MQTT error', err));
client.on('close', () => console.log('MQTT connection closed'));

// Simple topic match: supports MQTT-style single-level + and multi-level # when comparing subscription pattern to topic
function mqttMatches(sub, topic) {
  if (sub === '#') return true;
  const subParts = sub.split('/');
  const tParts = topic.split('/');
  for (let i=0;i<subParts.length;i++){
    const s = subParts[i];
    if (s === '#') return true;
    if (s === '+') continue;
    if (tParts[i] === undefined) return false;
    if (s !== tParts[i]) return false;
  }
  return subParts.length === tParts.length;
}

client.on('message', async (topic, payloadBuf) => {
  const payload = payloadBuf ? payloadBuf.toString() : '';
  console.log('MQTT message', topic, payload);

  // For each registered device, check if the incoming topic matches the device topic and thresholds
  for (const [deviceId, info] of Object.entries(devices)) {
    try {
      if (!info.topic) continue;
      if (!mqttMatches(info.topic, topic)) continue;

      // attempt numeric parse
      const value = parseFloat(payload.replace(/[^0-9.+-eE]/g, ''));
      if (isNaN(value)) {
        console.log('payload not numeric for device', deviceId);
        continue;
      }

      const { thresholds } = info;
      let shouldAlert = false;
      let reason = '';
      if (thresholds) {
        if (thresholds.min !== undefined && value < thresholds.min) { shouldAlert = true; reason = `value ${value} < min ${thresholds.min}`; }
        if (thresholds.max !== undefined && value > thresholds.max) { shouldAlert = true; reason = `value ${value} > max ${thresholds.max}`; }
      }

      if (shouldAlert && info.token) {
        const message = {
          notification: {
            title: `Alarm for ${deviceId}`,
            body: `${reason}: ${payload}`
          },
          token: info.token
        };
        try {
          const res = await admin.messaging().send(message);
          console.log('FCM sent to', deviceId, res);
        } catch (err) {
          console.error('FCM send error for', deviceId, err);
        }
      }
    } catch (e) {
      console.error('Error processing for device', deviceId, e);
    }
  }
});

// HTTP API for registration
const app = express();
app.use(bodyParser.json());

// Register device token + topic + thresholds
// POST /register { deviceId, token, topic, thresholds: {min, max} }
app.post('/register', (req, res) => {
  const { deviceId, token, topic, thresholds } = req.body || {};
  if (!deviceId) return res.status(400).json({ error: 'deviceId required' });
  devices[deviceId] = devices[deviceId] || {};
  if (token) devices[deviceId].token = token;
  if (topic) devices[deviceId].topic = topic;
  if (thresholds) devices[deviceId].thresholds = thresholds;
  saveDevices();
  return res.json({ ok: true });
});

// Unregister
app.post('/unregister', (req, res) => {
  const { deviceId } = req.body || {};
  if (!deviceId) return res.status(400).json({ error: 'deviceId required' });
  delete devices[deviceId];
  saveDevices();
  return res.json({ ok: true });
});

// Simple status
app.get('/status', (req, res) => {
  return res.json({ devices });
});

const PORT = process.env.HTTP_PORT || 3000;
app.listen(PORT, () => console.log('HTTP API listening on', PORT));

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('Shutting down...');
  try { client.end(); } catch(e){}
  process.exit(0);
});
