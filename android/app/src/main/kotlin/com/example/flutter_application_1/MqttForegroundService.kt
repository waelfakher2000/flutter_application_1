package com.example.flutter_application_1

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Binder
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.eclipse.paho.android.service.MqttAndroidClient
import org.eclipse.paho.client.mqttv3.IMqttActionListener
import org.eclipse.paho.client.mqttv3.IMqttDeliveryToken
import org.eclipse.paho.client.mqttv3.IMqttToken
import org.eclipse.paho.client.mqttv3.MqttCallbackExtended
import org.eclipse.paho.client.mqttv3.MqttConnectOptions
import org.eclipse.paho.client.mqttv3.MqttException
import org.eclipse.paho.client.mqttv3.MqttMessage
import kotlin.math.max

class MqttForegroundService : Service() {
    private val CHANNEL_ID = "mqtt_foreground_channel"
    private val NOTIF_ID = 90123

    private var mqttClient: MqttAndroidClient? = null
    private var broker: String = ""
    private var port: Int = 1883
    private var topic: String = ""
    private var username: String? = null
    private var password: String? = null
    private var minThreshold: Double? = null
    private var maxThreshold: Double? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        broker = intent?.getStringExtra("broker") ?: broker
        port = intent?.getIntExtra("port", port) ?: port
        topic = intent?.getStringExtra("topic") ?: topic
        username = intent?.getStringExtra("username")
        password = intent?.getStringExtra("password")
        minThreshold = intent?.getDoubleExtra("minThreshold", Double.NaN)?.let { if (it.isNaN()) null else it }
        maxThreshold = intent?.getDoubleExtra("maxThreshold", Double.NaN)?.let { if (it.isNaN()) null else it }

        try {
            val notif = buildForegroundNotification("MQTT Service", "Monitoring $topic on $broker:$port")
            startForeground(NOTIF_ID, notif)
        } catch (e: Exception) {
            e.printStackTrace()
        }

        try {
            connectAndSubscribe()
        } catch (e: Exception) {
            e.printStackTrace()
        }

        return START_STICKY
    }

    private fun connectAndSubscribe() {
        try {
            val serverUri = "tcp://$broker:$port"
            mqttClient = MqttAndroidClient(applicationContext, serverUri, "android_service_${System.currentTimeMillis()}")
            val options = MqttConnectOptions()
            options.isAutomaticReconnect = true
            options.isCleanSession = true
            if (!username.isNullOrBlank()) options.userName = username
            if (!password.isNullOrBlank()) options.password = password?.toCharArray()

            mqttClient?.setCallback(object : MqttCallbackExtended {
                override fun connectComplete(reconnect: Boolean, serverURI: String?) {}
                override fun connectionLost(cause: Throwable?) {}
                override fun messageArrived(topic: String?, message: MqttMessage?) {
                    val payload = message?.toString() ?: return
                    val value = extractFirstNumber(payload) ?: return
                    handleValue(value)
                }
                override fun deliveryComplete(token: IMqttDeliveryToken?) {}
            })

            mqttClient?.connect(options, null, object : IMqttActionListener {
                override fun onSuccess(asyncActionToken: IMqttToken?) {
                    try {
                        mqttClient?.subscribe(topic, 0)
                    } catch (ex: MqttException) {
                        ex.printStackTrace()
                    }
                }
                override fun onFailure(asyncActionToken: IMqttToken?, exception: Throwable?) {
                    exception?.printStackTrace()
                }
            })
        } catch (ex: Exception) {
            ex.printStackTrace()
        }
    }

    private fun handleValue(value: Double) {
        // treat value as level or distance? we will treat as level for simplicity
        val level = value
        if (maxThreshold != null && level > maxThreshold!!) {
            postNotification("High level", "Level ${"%.2f".format(level)}m exceeded max ${"%.2f".format(maxThreshold)}m")
        }
        if (minThreshold != null && level < minThreshold!!) {
            postNotification("Low level", "Level ${"%.2f".format(level)}m below min ${"%.2f".format(minThreshold)}m")
        }
    }

    private fun postNotification(title: String, body: String) {
        val channelId = "tank_monitor_channel"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val importance = NotificationManager.IMPORTANCE_HIGH
            val channel = NotificationChannel(channelId, "Tank Monitor Alerts", importance)
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }

        val builder = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)

        NotificationManagerCompat.from(this).notify((System.currentTimeMillis() % Int.MAX_VALUE).toInt(), builder.build())
    }

    private fun extractFirstNumber(s: String): Double? {
        val regex = Regex("[-+]?[0-9]*\\.?[0-9]+")
        val m = regex.find(s)
        return m?.value?.toDoubleOrNull()
    }

    private fun buildForegroundNotification(title: String, text: String): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pending = PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE)
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pending)
            .setOngoing(true)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            val chan = NotificationChannel(CHANNEL_ID, "MQTT Service", NotificationManager.IMPORTANCE_LOW)
            nm.createNotificationChannel(chan)
        }
    }

    override fun onDestroy() {
        try {
            mqttClient?.unregisterResources()
            mqttClient?.close()
        } catch (e: Exception) {}
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }
}
