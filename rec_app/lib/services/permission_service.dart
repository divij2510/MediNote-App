import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionService extends ChangeNotifier {
  bool _microphoneGranted = false;
  bool _notificationGranted = false;
  bool _isCheckingPermissions = false;

  bool get microphoneGranted => _microphoneGranted;
  bool get notificationGranted => _notificationGranted;
  bool get isCheckingPermissions => _isCheckingPermissions;
  bool get allPermissionsGranted => _microphoneGranted && _notificationGranted;

  Future<bool> checkAllPermissions() async {
    _isCheckingPermissions = true;
    notifyListeners();

    try {
      final micStatus = await Permission.microphone.status;
      final notificationStatus = await Permission.notification.status;

      _microphoneGranted = micStatus.isGranted;
      _notificationGranted = notificationStatus.isGranted;

      notifyListeners();
      return allPermissionsGranted;
    } catch (e) {
      debugPrint('Error checking permissions: $e');
      return false;
    } finally {
      _isCheckingPermissions = false;
      notifyListeners();
    }
  }

  Future<bool> requestMicrophonePermission() async {
    try {
      final status = await Permission.microphone.request();
      _microphoneGranted = status.isGranted;
      notifyListeners();
      return _microphoneGranted;
    } catch (e) {
      debugPrint('Error requesting microphone permission: $e');
      return false;
    }
  }

  Future<bool> requestNotificationPermission() async {
    try {
      final status = await Permission.notification.request();
      _notificationGranted = status.isGranted;
      notifyListeners();
      return _notificationGranted;
    } catch (e) {
      debugPrint('Error requesting notification permission: $e');
      return false;
    }
  }

  Future<bool> requestAllPermissions() async {
    final micResult = await requestMicrophonePermission();
    final notificationResult = await requestNotificationPermission();
    return micResult && notificationResult;
  }

  Future<void> openAppSettings() async {
    await openAppSettings();
  }
}