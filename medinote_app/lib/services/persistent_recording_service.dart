import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:phone_state/phone_state.dart';
import 'package:audio_session/audio_session.dart';
import 'audio_streaming_service.dart';
import 'offline_recording_service.dart';

class PersistentRecordingService with ChangeNotifier {
  static final PersistentRecordingService _instance = PersistentRecordingService._internal();
  factory PersistentRecordingService() => _instance;
  PersistentRecordingService._internal();

  bool _isRecording = false;
  String? _sessionId;
  Timer? _keepAliveTimer;
  AudioStreamingService? _audioService;
  OfflineRecordingService? _offlineService;
  FlutterLocalNotificationsPlugin? _notifications;
  
  // Phone state monitoring
  StreamSubscription<PhoneState>? _phoneStateSubscription;
  StreamSubscription<AudioInterruptionEvent>? _audioInterruptionSubscription;
  bool _wasPausedByCall = false;

  // Getters
  bool get isRecording => _isRecording;
  String? get sessionId => _sessionId;
  bool get wasPausedByCall => _wasPausedByCall;

  // Initialize the service
  Future<void> initialize() async {
    print('🎙️ Initializing persistent recording service');
    
    // Request necessary permissions
    await _requestPermissions();
    
    // Initialize notifications
    await _initializeNotifications();
    
    // Set up app lifecycle monitoring
    _setupAppLifecycleMonitoring();
    
    // Set up phone state monitoring
    _setupPhoneStateMonitoring();
    
    // Set up audio session monitoring (backup for call detection)
    _setupAudioSessionMonitoring();
  }

  // Request necessary permissions
  Future<void> _requestPermissions() async {
    // Request system alert window permission
    if (!await Permission.systemAlertWindow.isGranted) {
      await Permission.systemAlertWindow.request();
    }
    
    // Request battery optimization exemption
    if (!await Permission.ignoreBatteryOptimizations.isGranted) {
      await Permission.ignoreBatteryOptimizations.request();
    }
    
    // Request notification permission
    if (!await Permission.notification.isGranted) {
      await Permission.notification.request();
    }
    
    // Request phone state permission for call detection
    if (!await Permission.phone.isGranted) {
      await Permission.phone.request();
    }
  }

  // Ensure phone state permissions are granted
  Future<void> _ensurePhoneStatePermissions() async {
    print('📞 Checking phone state permissions...');
    
    final phonePermission = await Permission.phone.status;
    print('📞 Phone permission status: $phonePermission');
    
    if (phonePermission != PermissionStatus.granted) {
      print('📞 Requesting phone permission...');
      final result = await Permission.phone.request();
      print('📞 Phone permission result: $result');
    } else {
      print('📞 Phone permission already granted');
    }
  }

  // Initialize notifications
  Future<void> _initializeNotifications() async {
    _notifications = FlutterLocalNotificationsPlugin();
    
    // Android initialization settings
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    
    // iOS initialization settings
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    
    await _notifications!.initialize(initSettings);
    
    // Create notification channel for Android
    await _createNotificationChannel();
    
    print('🔔 Notifications initialized');
  }

  // Create notification channel for Android
  Future<void> _createNotificationChannel() async {
    if (_notifications == null) return;
    
    // Recording status channel
    const recordingChannel = AndroidNotificationChannel(
      'recording_channel',
      'Recording Status',
      description: 'Shows recording status when app is in background',
      importance: Importance.high,
    );
    
    // Call interruption channel
    const callInterruptionChannel = AndroidNotificationChannel(
      'call_interruption_channel',
      'Call Interruption',
      description: 'Shows when recording is paused due to incoming call',
      importance: Importance.high,
    );
    
    await _notifications!.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(recordingChannel);
    
    await _notifications!.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(callInterruptionChannel);
  }

  // Set up app lifecycle monitoring
  void _setupAppLifecycleMonitoring() {
    // Listen to app lifecycle changes
    SystemChannels.lifecycle.setMessageHandler((message) async {
      if (message == null) return null;
      
      switch (message) {
        case 'AppLifecycleState.paused':
          _handleAppPaused();
          break;
        case 'AppLifecycleState.resumed':
          _handleAppResumed();
          break;
        case 'AppLifecycleState.inactive':
          _handleAppInactive();
          break;
        case 'AppLifecycleState.detached':
          _handleAppDetached();
          break;
      }
      return null;
    });
  }

  // Set up phone state monitoring
  void _setupPhoneStateMonitoring() {
    try {
      // Cancel existing subscription if any
      _phoneStateSubscription?.cancel();
      
      _phoneStateSubscription = PhoneState.stream.listen((PhoneState phoneState) {
        print('📞 Raw phone state received: ${phoneState.status}');
        _handlePhoneStateChange(phoneState);
      });
      print('📞 Phone state monitoring initialized and active');
    } catch (e) {
      print('❌ Error setting up phone state monitoring: $e');
    }
  }

  // Set up audio session monitoring (backup for call detection)
  void _setupAudioSessionMonitoring() async {
    try {
      final session = await AudioSession.instance;
      _audioInterruptionSubscription = session.interruptionEventStream.listen((event) {
        print('🎵 Audio interruption event: begin=${event.begin}, type=${event.type}');
        if (event.begin) {
          print('🎵 Audio interruption started - pausing recording');
          _handleIncomingCall();
        } else {
          print('🎵 Audio interruption ended - resuming recording');
          _handleCallEnded();
        }
      });
      print('🎵 Audio session monitoring initialized');
    } catch (e) {
      print('❌ Error setting up audio session monitoring: $e');
    }
  }

  // Handle phone state changes
  void _handlePhoneStateChange(PhoneState phoneState) {
    print('📞 Phone state changed: ${phoneState.status} (isRecording: $_isRecording)');
    
    if (!_isRecording) {
      print('📞 Not recording, ignoring phone state change');
      return;
    }
    
    switch (phoneState.status) {
      case PhoneStateStatus.CALL_INCOMING:
        print('📞 CALL_INCOMING detected');
        _handleIncomingCall();
        break;
      case PhoneStateStatus.CALL_STARTED:
        print('📞 CALL_STARTED detected');
        _handleCallStarted();
        break;
      case PhoneStateStatus.CALL_ENDED:
        print('📞 CALL_ENDED detected');
        _handleCallEnded();
        break;
      case PhoneStateStatus.NOTHING:
        print('📞 NOTHING - Phone is idle');
        break;
      default:
        print('📞 Unknown phone state: ${phoneState.status}');
        break;
    }
  }

  // Handle incoming call
  void _handleIncomingCall() {
    print('📞 _handleIncomingCall called - isRecording: $_isRecording, audioService: ${_audioService != null}');
    if (_isRecording && _audioService != null) {
      print('📞 Incoming call detected - pausing recording');
      _wasPausedByCall = true;
      
      // Pause the audio streaming
      _audioService!.pauseStreaming();
      
      // Show notification about call interruption
      _showCallInterruptionNotification();
    } else {
      print('📞 Call detected but not recording or no audio service');
    }
  }

  // Handle call started
  void _handleCallStarted() {
    if (_isRecording) {
      if (!_wasPausedByCall) {
        print('📞 Call started - pausing recording now');
        _wasPausedByCall = true;
        
        // Pause the audio streaming
        _audioService?.pauseStreaming();
        
        // Show notification about call interruption
        _showCallInterruptionNotification();
        
        // Notify UI of state change
        notifyListeners();
      } else {
        print('📞 Call started - recording remains paused');
        // Recording stays paused during active call
      }
    }
  }

  // Handle call ended
  void _handleCallEnded() {
    print('📞 _handleCallEnded called - isRecording: $_isRecording, wasPausedByCall: $_wasPausedByCall');
    if (_isRecording && _wasPausedByCall) {
      print('📞 Call ended - resuming recording');
      _wasPausedByCall = false;
      
      // Resume the audio streaming
      _audioService!.resumeStreaming();
      
      // Hide call interruption notification
      _hideCallInterruptionNotification();
      
      // Notify UI of state change
      notifyListeners();
    } else {
      print('📞 Call ended but not recording or not paused by call');
    }
  }

  // Show call interruption notification
  Future<void> _showCallInterruptionNotification() async {
    try {
      if (_notifications == null) return;
      
      const androidDetails = AndroidNotificationDetails(
        'call_interruption_channel',
        'Call Interruption',
        channelDescription: 'Shows when recording is paused due to incoming call',
        importance: Importance.high,
        priority: Priority.high,
        ongoing: true,
        autoCancel: false,
        showWhen: false,
      );
      
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: false,
      );
      
      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
      
      await _notifications!.show(
        2, // Notification ID for call interruption
        '📞 Recording Paused',
        'Recording paused due to incoming call',
        notificationDetails,
      );
      
      print('🔔 Showing call interruption notification');
      
    } catch (e) {
      print('❌ Error showing call interruption notification: $e');
    }
  }

  // Hide call interruption notification
  Future<void> _hideCallInterruptionNotification() async {
    try {
      if (_notifications == null) return;
      
      await _notifications!.cancel(2); // Cancel call interruption notification
      print('🔔 Hiding call interruption notification');
      
    } catch (e) {
      print('❌ Error hiding call interruption notification: $e');
    }
  }

  // Handle app paused (going to background)
  void _handleAppPaused() {
    if (_isRecording) {
      print('📱 App paused while recording - maintaining recording in background');
      _startKeepAliveTimer();
    }
  }

  // Handle app resumed (coming to foreground)
  void _handleAppResumed() {
    if (_isRecording) {
      print('📱 App resumed while recording - stopping keep alive timer');
      _stopKeepAliveTimer();
    }
  }

  // Handle app inactive
  void _handleAppInactive() {
    // App is inactive but not paused (e.g., phone call overlay)
    if (_isRecording) {
      print('📱 App inactive while recording - maintaining recording');
    }
  }

  // Handle app detached
  void _handleAppDetached() {
    if (_isRecording) {
      print('📱 App detached while recording - stopping recording');
      stopRecording();
    }
  }

  // Start keep alive timer to maintain WebSocket connection
  void _startKeepAliveTimer() {
    _stopKeepAliveTimer(); // Stop any existing timer
    
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isRecording && _audioService != null) {
        print('🔄 Sending keep alive ping to maintain WebSocket connection');
        // Send ping to maintain WebSocket connection
        _audioService!.sendKeepAlivePing();
      }
    });
  }

  // Stop keep alive timer
  void _stopKeepAliveTimer() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

  // Start persistent recording
  Future<void> startRecording(String sessionId, AudioStreamingService audioService) async {
    if (_isRecording) {
      print('⚠️ Recording already in progress');
      return;
    }

    print('🎙️ Starting persistent recording: $sessionId');
    
    _isRecording = true;
    _sessionId = sessionId;
    _audioService = audioService;
    
    // Ensure phone state monitoring is active
    print('📞 Ensuring phone state monitoring is active for recording');
    await _ensurePhoneStatePermissions();
    _setupPhoneStateMonitoring();
    
    // Show persistent notification
    await _showRecordingNotification();
    
    notifyListeners();
  }

  // Stop persistent recording
  Future<void> stopRecording() async {
    if (!_isRecording) {
      print('⚠️ No recording in progress');
      return;
    }

    print('🛑 Stopping persistent recording: $_sessionId');
    
    // Stop keep alive timer
    _stopKeepAliveTimer();
    
    // Hide notification
    await _hideRecordingNotification();
    
    _isRecording = false;
    _sessionId = null;
    _audioService = null;
    
    notifyListeners();
  }

  // Show persistent recording notification
  Future<void> _showRecordingNotification() async {
    try {
      if (_notifications == null) return;
      
      const androidDetails = AndroidNotificationDetails(
        'recording_channel',
        'Recording Status',
        channelDescription: 'Shows recording status when app is in background',
        importance: Importance.high,
        priority: Priority.high,
        ongoing: true,
        autoCancel: false,
        showWhen: false,
      );
      
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: false,
      );
      
      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
      
      await _notifications!.show(
        1, // Notification ID
        '🎙️ Recording in Progress',
        'Session: $_sessionId',
        notificationDetails,
      );
      
      print('🔔 Showing recording notification for session: $_sessionId');
      
    } catch (e) {
      print('❌ Error showing recording notification: $e');
    }
  }

  // Hide recording notification
  Future<void> _hideRecordingNotification() async {
    try {
      if (_notifications == null) return;
      
      await _notifications!.cancel(1); // Cancel notification with ID 1
      print('🔔 Hiding recording notification');
      
    } catch (e) {
      print('❌ Error hiding recording notification: $e');
    }
  }

  // Send keep alive ping to maintain WebSocket connection
  void sendKeepAlivePing() {
    if (_audioService != null && _isRecording) {
      _audioService!.sendKeepAlivePing();
    }
  }

  // Check if recording is active
  bool isRecordingActive() {
    return _isRecording && _sessionId != null;
  }

  // Get recording status
  Map<String, dynamic> getRecordingStatus() {
    return {
      'is_recording': _isRecording,
      'session_id': _sessionId,
      'is_background': _keepAliveTimer != null,
    };
  }

  // Test method to manually trigger call interruption (for testing)
  void testCallInterruption() {
    print('🧪 Testing call interruption manually');
    _handleIncomingCall();
  }

  // Test method to manually trigger call started (for testing)
  void testCallStarted() {
    print('🧪 Testing call started manually');
    _handleCallStarted();
  }

  // Test method to manually trigger call end (for testing)
  void testCallEnd() {
    print('🧪 Testing call end manually');
    _handleCallEnded();
  }

  // Test method to check phone state monitoring status
  void testPhoneStateMonitoring() {
    print('🧪 Testing phone state monitoring status');
    print('📞 Phone state subscription active: ${_phoneStateSubscription != null}');
    print('📞 Audio interruption subscription active: ${_audioInterruptionSubscription != null}');
    print('📞 Is recording: $_isRecording');
    print('📞 Audio service available: ${_audioService != null}');
  }

  @override
  void dispose() {
    _stopKeepAliveTimer();
    _phoneStateSubscription?.cancel();
    _audioInterruptionSubscription?.cancel();
    _audioService?.dispose();
    super.dispose();
  }
}
