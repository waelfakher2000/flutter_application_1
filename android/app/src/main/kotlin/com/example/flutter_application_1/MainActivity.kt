package com.example.flutter_application_1

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private val CHANNEL = "app.settings.channel"

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
			if (call.method == "openAppNotificationSettings") {
				openAppNotificationSettings()
				result.success(true)
			} else if (call.method == "areNotificationsEnabled") {
				val enabled = NotificationManagerCompat.from(this).areNotificationsEnabled()
				result.success(enabled)
			} else if (call.method == "postNotification") {
				// Expect args: title, body
				val args = call.arguments as? Map<*, *>
				val title = args?.get("title") as? String ?: "App Alert"
				val body = args?.get("body") as? String ?: "Event"
				postNotification(title, body)
				result.success(true)
			} else {
				result.notImplemented()
			}
		}

		// Service channel to start/stop native MQTT foreground service
		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.mqtt.service").setMethodCallHandler { call, result ->
			when (call.method) {
				"startService" -> {
					val args = call.arguments as? Map<*, *>
					startNativeMqttService(args)
					result.success(true)
				}
				"stopService" -> {
					stopNativeMqttService()
					result.success(true)
				}
				else -> result.notImplemented()
			}
		}
	}

	private fun openAppNotificationSettings() {
		val intent = Intent()
		intent.action = Settings.ACTION_APP_NOTIFICATION_SETTINGS
		intent.putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
		startActivity(intent)
	}

	private fun postNotification(title: String, body: String) {
		val channelId = "tank_monitor_channel"
		val channelName = "Tank Monitor Alerts"

		// Create channel on Android O+
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
			val importance = NotificationManager.IMPORTANCE_HIGH
			val channel = NotificationChannel(channelId, channelName, importance)
			val nm = getSystemService(NotificationManager::class.java)
			nm.createNotificationChannel(channel)
		}

		val builder = NotificationCompat.Builder(this, channelId)
			.setSmallIcon(android.R.drawable.ic_dialog_info)
			.setContentTitle(title)
			.setContentText(body)
			.setPriority(NotificationCompat.PRIORITY_HIGH)
			.setAutoCancel(true)

		with(NotificationManagerCompat.from(this)) {
			// notificationId can be any unique int
			notify((System.currentTimeMillis() % Int.MAX_VALUE).toInt(), builder.build())
		}
	}

	private fun startNativeMqttService(args: Map<*, *>?) {
		val intent = Intent(this, MqttForegroundService::class.java)
		args?.let {
			intent.putExtra("broker", it["broker"] as? String)
			intent.putExtra("port", (it["port"] as? Int) ?: 1883)
			intent.putExtra("topic", it["topic"] as? String)
			intent.putExtra("username", it["username"] as? String)
			intent.putExtra("password", it["password"] as? String)
			// thresholds may be Double.NaN from Dart; handle as double
			val minThr = (it["minThreshold"] as? Double) ?: Double.NaN
			val maxThr = (it["maxThreshold"] as? Double) ?: Double.NaN
			intent.putExtra("minThreshold", minThr)
			intent.putExtra("maxThreshold", maxThr)
		}
		try {
			startForegroundService(intent)
		} catch (e: Exception) {
			e.printStackTrace()
		}
	}

	private fun stopNativeMqttService() {
		val intent = Intent(this, MqttForegroundService::class.java)
		stopService(intent)
	}
}
