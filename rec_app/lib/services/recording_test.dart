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
        return false;
      }

      debugPrint('Microphone access test passed');
      return true;
    } catch (e) {
      debugPrint('Microphone access test failed: $e');
      return false;
    }
  }

  static Future<void> testAmplitudeMonitoring() async {
    try {
      final recorder = AudioRecorder();
      
      // Start a short recording to test amplitude
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 44100,
          bitRate: 128000,
        ),
        path: '/tmp/test_recording.m4a',
      );

      // Test amplitude for 3 seconds
      for (int i = 0; i < 30; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        final amplitude = await recorder.getAmplitude();
        debugPrint('Test amplitude: ${amplitude.current}');
      }

      await recorder.stop();
      debugPrint('Amplitude monitoring test completed');
    } catch (e) {
      debugPrint('Amplitude monitoring test failed: $e');
    }
  }
}
