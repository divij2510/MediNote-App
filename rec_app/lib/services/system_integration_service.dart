import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

import '../models/session.dart';

class SystemIntegrationService extends ChangeNotifier {
  late FlutterLocalNotificationsPlugin _notifications;
  bool _isInitialized = false;
  bool _respectDoNotDisturb = true;
  
  // Notification channels
  static const String _recordingChannelId = 'recording_notifications';
  static const String _interruptionChannelId = 'interruption_notifications';
  static const String _recoveryChannelId = 'recovery_notifications';
  static const String _systemChannelId = 'system_notifications';
  
  // Getters
  bool get isInitialized => _isInitialized;
  bool get respectDoNotDisturb => _respectDoNotDisturb;
  
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _notifications = FlutterLocalNotificationsPlugin();
      
      // Initialize notification settings
      await _initializeNotifications();
      
      // Request permissions
      await _requestPermissions();
      
      _isInitialized = true;
      debugPrint('System integration service initialized');
    } catch (e) {
      debugPrint('Error initializing system integration service: $e');
    }
  }
  
  Future<void> _initializeNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    
    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
    
    // Create notification channels for Android
    if (Platform.isAndroid) {
      await _createNotificationChannels();
    }
  }
  
  Future<void> _createNotificationChannels() async {
    // Recording notifications channel
    const recordingChannel = AndroidNotificationChannel(
      _recordingChannelId,
      'Recording Notifications',
      description: 'Notifications for active recording sessions',
      importance: Importance.high,
      enableVibration: true,
      enableLights: true,
      showBadge: true,
    );
    
    // Interruption notifications channel
    const interruptionChannel = AndroidNotificationChannel(
      _interruptionChannelId,
      'Interruption Notifications',
      description: 'Notifications for recording interruptions',
      importance: Importance.high,
      enableVibration: true,
      enableLights: true,
      showBadge: true,
    );
    
    // Recovery notifications channel
    const recoveryChannel = AndroidNotificationChannel(
      _recoveryChannelId,
      'Recovery Notifications',
      description: 'Notifications for session recovery',
      importance: Importance.high,
      enableVibration: true,
      enableLights: true,
      showBadge: true,
    );
    
    // System notifications channel
    const systemChannel = AndroidNotificationChannel(
      _systemChannelId,
      'System Notifications',
      description: 'System-level notifications',
      importance: Importance.defaultImportance,
      enableVibration: false,
      enableLights: false,
      showBadge: false,
    );
    
    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(recordingChannel);
    
    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(interruptionChannel);
    
    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(recoveryChannel);
    
    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(systemChannel);
  }
  
  Future<void> _requestPermissions() async {
    // Request notification permission
    final notificationStatus = await Permission.notification.request();
    if (!notificationStatus.isGranted) {
      debugPrint('Notification permission denied');
    }
    
    // Request system alert window permission for Android
    if (Platform.isAndroid) {
      final systemAlertStatus = await Permission.systemAlertWindow.request();
      if (!systemAlertStatus.isGranted) {
        debugPrint('System alert window permission denied');
      }
    }
  }
  
  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('Notification tapped: ${response.actionId}');
    
    switch (response.actionId) {
      case 'pause':
        _handlePauseAction();
        break;
      case 'resume':
        _handleResumeAction();
        break;
      case 'stop':
        _handleStopAction();
        break;
      case 'recover':
        _handleRecoverAction();
        break;
      case 'dismiss':
        _handleDismissAction();
        break;
      default:
        _handleDefaultAction();
        break;
    }
  }
  
  void _handlePauseAction() {
    // Handle pause action
    debugPrint('Pause action triggered');
  }
  
  void _handleResumeAction() {
    // Handle resume action
    debugPrint('Resume action triggered');
  }
  
  void _handleStopAction() {
    // Handle stop action
    debugPrint('Stop action triggered');
  }
  
  void _handleRecoverAction() {
    // Handle recover action
    debugPrint('Recover action triggered');
  }
  
  void _handleDismissAction() {
    // Handle dismiss action
    debugPrint('Dismiss action triggered');
  }
  
  void _handleDefaultAction() {
    // Handle default action
    debugPrint('Default action triggered');
  }
  
  // Recording notifications
  Future<void> showRecordingStartedNotification(RecordingSession session) async {
    const androidDetails = AndroidNotificationDetails(
      _recordingChannelId,
      'Recording Active',
      channelDescription: 'Active recording session notifications',
      importance: Importance.high,
      ongoing: true,
      showWhen: false,
      autoCancel: false,
      actions: [
        AndroidNotificationAction('pause', 'Pause'),
        AndroidNotificationAction('stop', 'Stop'),
      ],
    );
    
    const notificationDetails = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      1,
      'Recording Started',
      'Recording session for ${session.patientName}',
      notificationDetails,
    );
  }
  
  Future<void> showRecordingPausedNotification() async {
    const androidDetails = AndroidNotificationDetails(
      _recordingChannelId,
      'Recording Paused',
      channelDescription: 'Paused recording session notifications',
      importance: Importance.high,
      ongoing: true,
      showWhen: false,
      autoCancel: false,
      actions: [
        AndroidNotificationAction('resume', 'Resume'),
        AndroidNotificationAction('stop', 'Stop'),
      ],
    );
    
    const notificationDetails = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      1,
      'Recording Paused',
      'Recording session paused',
      notificationDetails,
    );
  }
  
  Future<void> showRecordingResumedNotification() async {
    await showRecordingStartedNotification(RecordingSession(
      id: '',
      patientId: '',
      userId: '',
      patientName: 'Current Session',
      status: 'recording',
      startTime: DateTime.now(),
    ));
  }
  
  Future<void> showRecordingCompletedNotification(RecordingSession session) async {
    const androidDetails = AndroidNotificationDetails(
      _recordingChannelId,
      'Recording Complete',
      channelDescription: 'Completed recording session notifications',
      importance: Importance.high,
      actions: [
        AndroidNotificationAction('share', 'Share'),
        AndroidNotificationAction('view', 'View'),
      ],
    );
    
    const notificationDetails = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      2,
      'Recording Complete',
      'Recording session for ${session.patientName} completed',
      notificationDetails,
    );
  }
  
  // Interruption notifications
  Future<void> showPhoneCallInterruptionNotification() async {
    const androidDetails = AndroidNotificationDetails(
      _interruptionChannelId,
      'Phone Call Interruption',
      channelDescription: 'Phone call interruption notifications',
      importance: Importance.high,
      ongoing: true,
      showWhen: false,
      autoCancel: false,
      actions: [
        AndroidNotificationAction('resume', 'Resume After Call'),
      ],
    );
    
    const notificationDetails = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      10,
      'Recording Paused',
      'Recording paused due to phone call',
      notificationDetails,
    );
  }
  
  Future<void> showNetworkLossNotification() async {
    const androidDetails = AndroidNotificationDetails(
      _interruptionChannelId,
      'Network Loss',
      channelDescription: 'Network loss interruption notifications',
      importance: Importance.high,
      ongoing: true,
      showWhen: false,
      autoCancel: false,
    );
    
    const notificationDetails = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      11,
      'Recording Offline',
      'Recording continues offline, will sync when connected',
      notificationDetails,
    );
  }
  
  Future<void> showAppBackgroundedNotification() async {
    const androidDetails = AndroidNotificationDetails(
      _interruptionChannelId,
      'App Backgrounded',
      channelDescription: 'App backgrounded notifications',
      importance: Importance.high,
      ongoing: true,
      showWhen: false,
      autoCancel: false,
    );
    
    const notificationDetails = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      12,
      'Recording in Background',
      'Recording continues in background',
      notificationDetails,
    );
  }
  
  // Recovery notifications
  Future<void> showRecoveryAvailableNotification() async {
    const androidDetails = AndroidNotificationDetails(
      _recoveryChannelId,
      'Session Recovery',
      channelDescription: 'Session recovery notifications',
      importance: Importance.high,
      actions: [
        AndroidNotificationAction('recover', 'Resume Session'),
        AndroidNotificationAction('dismiss', 'Dismiss'),
      ],
    );
    
    const notificationDetails = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      20,
      'Session Recovery Available',
      'Previous recording session can be resumed',
      notificationDetails,
    );
  }
  
  Future<void> showRecoverySuccessfulNotification() async {
    const androidDetails = AndroidNotificationDetails(
      _recoveryChannelId,
      'Recovery Successful',
      channelDescription: 'Recovery successful notifications',
      importance: Importance.high,
    );
    
    const notificationDetails = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      21,
      'Session Recovered',
      'Previous recording session resumed successfully',
      notificationDetails,
    );
  }
  
  // System notifications
  Future<void> showSystemNotification(String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
      _systemChannelId,
      'System Notification',
      channelDescription: 'System notifications',
      importance: Importance.defaultImportance,
    );
    
    const notificationDetails = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      30,
      title,
      body,
      notificationDetails,
    );
  }
  
  // Haptic feedback methods
  void triggerRecordingStartHaptic() {
    HapticFeedback.mediumImpact();
  }
  
  void triggerRecordingStopHaptic() {
    HapticFeedback.heavyImpact();
  }
  
  void triggerRecordingPauseHaptic() {
    HapticFeedback.lightImpact();
  }
  
  void triggerRecordingResumeHaptic() {
    HapticFeedback.lightImpact();
  }
  
  void triggerErrorHaptic() {
    HapticFeedback.heavyImpact();
  }
  
  void triggerSuccessHaptic() {
    HapticFeedback.lightImpact();
  }
  
  void triggerWarningHaptic() {
    HapticFeedback.mediumImpact();
  }
  
  // Share functionality
  Future<void> shareRecording(RecordingSession session) async {
    try {
      final shareText = '''
Recording Session Details:
Patient: ${session.patientName}
Date: ${session.startTime.toString()}
Duration: ${_formatDuration(session.startTime.difference(DateTime.now()).abs())}
Status: ${session.status}
      ''';
      
      await Share.share(
        shareText,
        subject: 'Medical Recording Session - ${session.patientName}',
      );
    } catch (e) {
      debugPrint('Error sharing recording: $e');
    }
  }
  
  Future<void> shareAudioFile(String filePath) async {
    try {
      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'Medical Recording Audio File',
      );
    } catch (e) {
      debugPrint('Error sharing audio file: $e');
    }
  }
  
  // Do Not Disturb handling
  void setRespectDoNotDisturb(bool respect) {
    _respectDoNotDisturb = respect;
    notifyListeners();
  }
  
  Future<bool> isDoNotDisturbActive() async {
    // This would typically use platform channels to check DND status
    // For now, we'll return false
    return false;
  }
  
  // Utility methods
  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }
  
  // Clear all notifications
  Future<void> clearAllNotifications() async {
    await _notifications.cancelAll();
  }
  
  // Clear specific notification
  Future<void> clearNotification(int id) async {
    await _notifications.cancel(id);
  }
  
  @override
  void dispose() {
    super.dispose();
  }
}
