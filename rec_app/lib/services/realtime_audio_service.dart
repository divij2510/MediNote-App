import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';

import '../models/session.dart';
import 'api_service.dart';
import 'storage_service.dart';

enum StreamingState {
  idle,
  connecting,
  streaming,
  paused,
  reconnecting,
  error,
  completed
}

class RealtimeAudioService extends ChangeNotifier {
  // Core streaming components
  WebSocketChannel? _channel;
  StreamSubscription<Uint8List>? _audioStream;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  
  // Audio recording
  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamController<Uint8List>? _audioController;
  
  // State management
  StreamingState _streamingState = StreamingState.idle;
  RecordingSession? _currentSession;
  String? _sessionId;
  bool _isStreaming = false;
  bool _isPaused = false;
  bool _isReconnecting = false;
  
  // Audio metrics
  double _currentAmplitude = 0.0;
  double _gainLevel = 1.0;
  Duration _streamingDuration = Duration.zero;
  Timer? _durationTimer;
  Timer? _amplitudeTimer;
  
  // Recovery system
  String? _recoverySessionId;
  int _recoveryPosition = 0;
  List<Map<String, dynamic>> _pendingChunks = [];
  
  // Services
  late ApiService _apiService;
  late StorageService _storageService;
  late FlutterLocalNotificationsPlugin _notifications;
  
  // Native features
  bool _isBluetoothConnected = false;
  bool _isWiredHeadsetConnected = false;
  bool _respectDoNotDisturb = true;
  
  // Getters
  StreamingState get streamingState => _streamingState;
  RecordingSession? get currentSession => _currentSession;
  bool get isStreaming => _isStreaming;
  bool get isPaused => _isPaused;
  double get currentAmplitude => _currentAmplitude;
  double get gainLevel => _gainLevel;
  Duration get streamingDuration => _streamingDuration;
  bool get isBluetoothConnected => _isBluetoothConnected;
  bool get isWiredHeadsetConnected => _isWiredHeadsetConnected;
  
  void initialize(ApiService apiService, StorageService storageService) {
    _apiService = apiService;
    _storageService = storageService;
    _initializeNotifications();
    _checkRecoveryState();
    _monitorAudioDevices();
  }
  
  Future<void> _initializeNotifications() async {
    _notifications = FlutterLocalNotificationsPlugin();
    
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    
    await _notifications.initialize(initSettings);
  }
  
  Future<void> _checkRecoveryState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _recoverySessionId = prefs.getString('recovery_session_id');
      
      if (_recoverySessionId != null) {
        debugPrint('Found recovery session: $_recoverySessionId');
        await _showRecoveryNotification();
      }
    } catch (e) {
      debugPrint('Error checking recovery state: $e');
    }
  }
  
  Future<void> _monitorAudioDevices() async {
    // Monitor Bluetooth and wired headset connections
    // This would typically use platform channels to monitor audio device changes
    // For now, we'll implement basic monitoring
    Timer.periodic(const Duration(seconds: 5), (timer) {
      _checkAudioDevices();
    });
  }
  
  Future<void> _checkAudioDevices() async {
    // Check for Bluetooth and wired headset connections
    // This is a simplified implementation
    // In a real implementation, you'd use platform channels to monitor audio device changes
  }
  
  Future<bool> startStreamingSession(RecordingSession session) async {
    if (_streamingState != StreamingState.idle) {
      debugPrint('Cannot start streaming: already streaming');
      return false;
    }
    
    try {
      _currentSession = session;
      _sessionId = session.id;
      _streamingState = StreamingState.connecting;
      notifyListeners();
      
      // Request permissions
      if (!await _requestPermissions()) {
        _streamingState = StreamingState.error;
        notifyListeners();
        return false;
      }
      
      // Connect to WebSocket
      await _connectWebSocket();
      
      // Start audio recording
      await _startAudioRecording();
      
      // Start streaming
      await _startAudioStreaming();
      
      _streamingState = StreamingState.streaming;
      _isStreaming = true;
      notifyListeners();
      
      // Show notification
      await _showStreamingNotification();
      
      // Start duration timer
      _startDurationTimer();
      
      // Start amplitude monitoring
      _startAmplitudeMonitoring();
      
      // Save session for recovery
      await _saveRecoveryState();
      
      debugPrint('Real-time streaming started successfully');
      return true;
      
    } catch (e) {
      debugPrint('Error starting streaming session: $e');
      _streamingState = StreamingState.error;
      notifyListeners();
      return false;
    }
  }
  
  Future<bool> _requestPermissions() async {
    final permissions = [
      Permission.microphone,
      Permission.notification,
      Permission.systemAlertWindow,
    ];
    
    for (final permission in permissions) {
      final status = await permission.request();
      if (!status.isGranted) {
        debugPrint('Permission denied: $permission');
        return false;
      }
    }
    
    return true;
  }
  
  Future<void> _connectWebSocket() async {
    try {
      final wsUrl = 'wss://${_apiService.baseUrl.replaceAll('http://', '').replaceAll('https://', '')}/ws/audio-stream';
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      
      // Send session info
      await _channel!.ready;
      _channel!.sink.add(jsonEncode({
        'type': 'session_start',
        'session_id': _sessionId,
        'user_id': _apiService.userId,
        'patient_id': _currentSession!.patientId,
        'patient_name': _currentSession!.patientName,
      }));
      
      // Listen for server messages
      _channel!.stream.listen(
        _handleServerMessage,
        onError: _handleWebSocketError,
        onDone: _handleWebSocketClosed,
      );
      
      debugPrint('WebSocket connected successfully');
    } catch (e) {
      debugPrint('Error connecting WebSocket: $e');
      rethrow;
    }
  }
  
  Future<void> _startAudioRecording() async {
    try {
      // Configure audio recording for streaming
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 44100,
          bitRate: 128000,
          numChannels: 1,
        ),
        path: null, // We'll stream directly, not save to file
      );
      
      debugPrint('Audio recording started for streaming');
    } catch (e) {
      debugPrint('Error starting audio recording: $e');
      rethrow;
    }
  }
  
  Future<void> _startAudioStreaming() async {
    try {
      // Create audio stream controller
      _audioController = StreamController<Uint8List>();
      
      // Start audio stream
      _audioStream = _audioController!.stream.listen(
        _sendAudioData,
        onError: _handleAudioStreamError,
      );
      
      // Start recording audio data
      _startAudioDataCapture();
      
      debugPrint('Audio streaming started');
    } catch (e) {
      debugPrint('Error starting audio streaming: $e');
      rethrow;
    }
  }
  
  void _startAudioDataCapture() {
    // This is a simplified implementation
    // In a real implementation, you'd capture audio data from the microphone
    // and feed it to the stream controller
    
    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!_isStreaming || _isPaused) {
        timer.cancel();
        return;
      }
      
      // Simulate audio data capture
      // In reality, you'd capture actual audio data from the microphone
      final audioData = Uint8List(1024); // Placeholder
      _audioController?.add(audioData);
    });
  }
  
  void _sendAudioData(Uint8List audioData) {
    if (_channel != null && _channel!.closeCode == null) {
      try {
        _channel!.sink.add(audioData);
      } catch (e) {
        debugPrint('Error sending audio data: $e');
        _handleWebSocketError(e);
      }
    }
  }
  
  void _handleServerMessage(dynamic message) {
    try {
      final data = jsonDecode(message);
      debugPrint('Received server message: $data');
      
      switch (data['type']) {
        case 'audio_received':
          // Server confirmed audio data received
          break;
        case 'session_updated':
          // Session updated on server
          break;
        case 'error':
          debugPrint('Server error: ${data['message']}');
          break;
      }
    } catch (e) {
      debugPrint('Error handling server message: $e');
    }
  }
  
  void _handleWebSocketError(dynamic error) {
    debugPrint('WebSocket error: $error');
    _handleConnectionLoss();
  }
  
  void _handleWebSocketClosed() {
    debugPrint('WebSocket connection closed');
    _handleConnectionLoss();
  }
  
  void _handleConnectionLoss() {
    if (_isStreaming && !_isReconnecting) {
      _isReconnecting = true;
      _streamingState = StreamingState.reconnecting;
      notifyListeners();
      
      // Start reconnection process
      _startReconnection();
    }
  }
  
  void _startReconnection() {
    _reconnectTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      try {
        await _connectWebSocket();
        _isReconnecting = false;
        _streamingState = StreamingState.streaming;
        notifyListeners();
        timer.cancel();
        debugPrint('Reconnected successfully');
      } catch (e) {
        debugPrint('Reconnection attempt failed: $e');
      }
    });
  }
  
  void _handleAudioStreamError(dynamic error) {
    debugPrint('Audio stream error: $error');
    // Handle audio stream errors
  }
  
  Future<void> pauseStreaming() async {
    if (!_isStreaming || _isPaused) return;
    
    try {
      _isPaused = true;
      _streamingState = StreamingState.paused;
      notifyListeners();
      
      // Pause audio recording
      await _audioRecorder.pause();
      
      // Send pause message to server
      if (_channel != null) {
        _channel!.sink.add(jsonEncode({
          'type': 'pause_streaming',
          'session_id': _sessionId,
        }));
      }
      
      // Show pause notification
      await _showPauseNotification();
      
      debugPrint('Streaming paused');
    } catch (e) {
      debugPrint('Error pausing streaming: $e');
    }
  }
  
  Future<void> resumeStreaming() async {
    if (!_isStreaming || !_isPaused) return;
    
    try {
      _isPaused = false;
      _streamingState = StreamingState.streaming;
      notifyListeners();
      
      // Resume audio recording
      await _audioRecorder.resume();
      
      // Send resume message to server
      if (_channel != null) {
        _channel!.sink.add(jsonEncode({
          'type': 'resume_streaming',
          'session_id': _sessionId,
        }));
      }
      
      // Show resume notification
      await _showResumeNotification();
      
      debugPrint('Streaming resumed');
    } catch (e) {
      debugPrint('Error resuming streaming: $e');
    }
  }
  
  Future<void> stopStreaming() async {
    if (!_isStreaming) return;
    
    try {
      _isStreaming = false;
      _streamingState = StreamingState.completed;
      notifyListeners();
      
      // Stop audio recording
      await _audioRecorder.stop();
      
      // Send stop message to server
      if (_channel != null) {
        _channel!.sink.add(jsonEncode({
          'type': 'stop_streaming',
          'session_id': _sessionId,
        }));
      }
      
      // Close WebSocket
      await _channel?.sink.close();
      
      // Stop timers
      _durationTimer?.cancel();
      _amplitudeTimer?.cancel();
      _reconnectTimer?.cancel();
      
      // Close audio stream
      await _audioController?.close();
      _audioStream?.cancel();
      
      // Clear recovery state
      await _clearRecoveryState();
      
      // Show completion notification
      await _showCompletionNotification();
      
      debugPrint('Streaming stopped successfully');
    } catch (e) {
      debugPrint('Error stopping streaming: $e');
    }
  }
  
  Future<void> _saveRecoveryState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('recovery_session_id', _sessionId!);
      await prefs.setInt('recovery_position', _recoveryPosition);
      debugPrint('Recovery state saved');
    } catch (e) {
      debugPrint('Error saving recovery state: $e');
    }
  }
  
  Future<void> _clearRecoveryState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('recovery_session_id');
      await prefs.remove('recovery_position');
      debugPrint('Recovery state cleared');
    } catch (e) {
      debugPrint('Error clearing recovery state: $e');
    }
  }
  
  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isStreaming && !_isPaused) {
        _streamingDuration += const Duration(seconds: 1);
        notifyListeners();
      }
    });
  }
  
  void _startAmplitudeMonitoring() {
    _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      if (_isStreaming && !_isPaused) {
        try {
          final amplitude = await _audioRecorder.getAmplitude();
          _currentAmplitude = ((amplitude.current + 60) / 60 * 100).clamp(0.0, 100.0);
          notifyListeners();
        } catch (e) {
          debugPrint('Error getting amplitude: $e');
        }
      }
    });
  }
  
  // Notification methods
  Future<void> _showStreamingNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'audio_streaming',
      'Audio Streaming',
      channelDescription: 'Real-time audio streaming notifications',
      importance: Importance.high,
      priority: Priority.high,
      ongoing: true,
      showWhen: false,
      actions: [
        AndroidNotificationAction('pause', 'Pause'),
        AndroidNotificationAction('stop', 'Stop'),
      ],
    );
    
    const notificationDetails = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      1,
      'Recording Session',
      'Streaming audio in real-time',
      notificationDetails,
    );
  }
  
  Future<void> _showPauseNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'audio_streaming',
      'Audio Streaming',
      channelDescription: 'Real-time audio streaming notifications',
      importance: Importance.high,
      priority: Priority.high,
      ongoing: true,
      showWhen: false,
      actions: [
        AndroidNotificationAction('resume', 'Resume'),
        AndroidNotificationAction('stop', 'Stop'),
      ],
    );
    
    const notificationDetails = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      1,
      'Recording Paused',
      'Audio streaming paused',
      notificationDetails,
    );
  }
  
  Future<void> _showResumeNotification() async {
    await _showStreamingNotification();
  }
  
  Future<void> _showCompletionNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'audio_streaming',
      'Audio Streaming',
      channelDescription: 'Real-time audio streaming notifications',
      importance: Importance.high,
      priority: Priority.high,
    );
    
    const notificationDetails = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      2,
      'Recording Complete',
      'Audio streaming completed successfully',
      notificationDetails,
    );
  }
  
  Future<void> _showRecoveryNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'audio_recovery',
      'Audio Recovery',
      channelDescription: 'Audio streaming recovery notifications',
      importance: Importance.high,
      priority: Priority.high,
      actions: [
        AndroidNotificationAction('resume', 'Resume Session'),
        AndroidNotificationAction('dismiss', 'Dismiss'),
      ],
    );
    
    const notificationDetails = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      3,
      'Session Recovery',
      'Previous recording session can be resumed',
      notificationDetails,
    );
  }
  
  // Native feature methods
  void setGainLevel(double level) {
    _gainLevel = level.clamp(0.1, 3.0);
    notifyListeners();
  }
  
  Future<void> handleBluetoothConnection(bool connected) async {
    _isBluetoothConnected = connected;
    if (connected && _isStreaming) {
      // Handle Bluetooth connection
      await _handleAudioDeviceChange();
    }
    notifyListeners();
  }
  
  Future<void> handleWiredHeadsetConnection(bool connected) async {
    _isWiredHeadsetConnected = connected;
    if (connected && _isStreaming) {
      // Handle wired headset connection
      await _handleAudioDeviceChange();
    }
    notifyListeners();
  }
  
  Future<void> _handleAudioDeviceChange() async {
    // Handle audio device changes
    // This would typically involve reconfiguring the audio recording
    debugPrint('Audio device changed - Bluetooth: $_isBluetoothConnected, Wired: $_isWiredHeadsetConnected');
  }
  
  Future<void> handlePhoneCall() async {
    if (_isStreaming) {
      await pauseStreaming();
      // Show call notification
      await _showCallNotification();
    }
  }
  
  Future<void> handleCallEnded() async {
    if (_isPaused) {
      await resumeStreaming();
    }
  }
  
  Future<void> _showCallNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'phone_call',
      'Phone Call',
      channelDescription: 'Phone call notifications',
      importance: Importance.high,
      priority: Priority.high,
    );
    
    const notificationDetails = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      4,
      'Recording Paused',
      'Audio recording paused due to phone call',
      notificationDetails,
    );
  }
  
  Future<void> handleAppKilled() async {
    if (_isStreaming) {
      // Save state for recovery
      await _saveRecoveryState();
      debugPrint('App killed - state saved for recovery');
    }
  }
  
  Future<void> handleAppResumed() async {
    if (_recoverySessionId != null) {
      // Show recovery notification
      await _showRecoveryNotification();
    }
  }
  
  Future<void> resumeFromRecovery() async {
    if (_recoverySessionId == null) return;
    
    try {
      // Load session from recovery
      final session = await _apiService.getSession(_recoverySessionId!);
      if (session != null) {
        await startStreamingSession(session);
        debugPrint('Session resumed from recovery');
      }
    } catch (e) {
      debugPrint('Error resuming from recovery: $e');
    }
  }
  
  Future<void> dismissRecovery() async {
    await _clearRecoveryState();
    _recoverySessionId = null;
    debugPrint('Recovery dismissed');
  }
  
  @override
  void dispose() {
    _audioStream?.cancel();
    _audioController?.close();
    _channel?.sink.close();
    _durationTimer?.cancel();
    _amplitudeTimer?.cancel();
    _reconnectTimer?.cancel();
    super.dispose();
  }
}
