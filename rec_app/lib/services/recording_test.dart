import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';

class RecordingTest {
  static Future<bool> testMicrophoneAccess() async {
    try {
      // Check microphone permission
      final micStatus = await Permission.microphone.request();
      if (micStatus != PermissionStatus.granted) {
        debugPrint('Microphone permission denied');
        return false;
      }

      // Test if recorder is available
      final recorder = AudioRecorder();
      final hasPermission = await recorder.hasPermission();
      
      if (!hasPermission) {
        debugPrint('Audio recorder permission not granted');
        await recorder.dispose();
        return false;
      }

      await recorder.dispose();
      debugPrint('Microphone access test passed');
      return true;
    } catch (e) {
      debugPrint('Microphone access test failed: $e');
      return false;
    }
  }

  static Future<void> testAmplitudeMonitoring() async {
    AudioRecorder? recorder;
    try {
      recorder = AudioRecorder();
      
      // Test amplitude without recording
      for (int i = 0; i < 5; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        try {
          final amplitude = await recorder.getAmplitude();
          final percentage = ((amplitude.current + 60) / 60 * 100).clamp(0.0, 100.0);
          debugPrint('Test amplitude: ${amplitude.current} dB -> ${percentage.toStringAsFixed(1)}%');
        } catch (e) {
          debugPrint('Amplitude reading error: $e');
        }
      }

      debugPrint('Amplitude monitoring test completed');
    } catch (e) {
      debugPrint('Amplitude monitoring test failed: $e');
    } finally {
      try {
        await recorder?.dispose();
      } catch (e) {
        debugPrint('Error disposing recorder: $e');
      }
    }
  }
}