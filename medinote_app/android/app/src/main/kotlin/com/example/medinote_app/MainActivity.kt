package com.example.medinote_app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.medinote.app/permissions"
    private val BATTERY_CHANNEL = "com.medinote.app/battery_optimization"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestSystemAlertWindowPermission" -> {
                    requestSystemAlertWindowPermission(result)
                }
                "isBackgroundProcessingAllowed" -> {
                    result.success(isBackgroundProcessingAllowed())
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BATTERY_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestBatteryOptimizationExemption" -> {
                    requestBatteryOptimizationExemption(result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun requestSystemAlertWindowPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!Settings.canDrawOverlays(this)) {
                val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION)
                intent.data = Uri.parse("package:$packageName")
                startActivityForResult(intent, REQUEST_CODE_OVERLAY_PERMISSION)
                result.success(false) // Will be updated when permission is granted
            } else {
                result.success(true)
            }
        } else {
            result.success(true)
        }
    }

    private fun isBackgroundProcessingAllowed(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true
        }
    }

    private fun requestBatteryOptimizationExemption(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            if (!powerManager.isIgnoringBatteryOptimizations(packageName)) {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                intent.data = Uri.parse("package:$packageName")
                startActivityForResult(intent, REQUEST_CODE_BATTERY_OPTIMIZATION)
                result.success(false) // Will be updated when permission is granted
            } else {
                result.success(true)
            }
        } else {
            result.success(true)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        
        when (requestCode) {
            REQUEST_CODE_OVERLAY_PERMISSION -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    val granted = Settings.canDrawOverlays(this)
                    Log.d("MainActivity", "Overlay permission granted: $granted")
                }
            }
            REQUEST_CODE_BATTERY_OPTIMIZATION -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                    val granted = powerManager.isIgnoringBatteryOptimizations(packageName)
                    Log.d("MainActivity", "Battery optimization exemption granted: $granted")
                }
            }
        }
    }

    companion object {
        private const val REQUEST_CODE_OVERLAY_PERMISSION = 1001
        private const val REQUEST_CODE_BATTERY_OPTIMIZATION = 1002
    }
}