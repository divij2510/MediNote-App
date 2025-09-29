import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
// import 'package:mic_stream/mic_stream.dart';  // Commented out due to compatibility issues
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/session.dart';
import 'api_service.dart';
import 'storage_service.dart';

enum AudioDeviceType {
  deviceMicrophone,
  bluetoothHeadset,
  wiredHeadset,
  bluetoothSpeaker,
}

class NativeAudioService extends ChangeNotifier {
  // Core audio components
  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  StreamSubscription<Uint8List>? _audioStreamSubscription;
  // StreamSubscription<List<int>>? _micStreamSubscription;  // Not used with record package approach
  
  // Audio state
  bool _isRecording = false;
  bool _isPaused = false;
  double _currentAmplitude = 0.0;
  double _gainLevel = 1.0;
  Duration _recordingDuration = Duration.zero;
  Timer? _durationTimer;
  
  // Audio device management
  AudioDeviceType _currentDevice = AudioDeviceType.deviceMicrophone;
  bool _isBluetoothConnected = false;
  bool _isWiredHeadsetConnected = false;
  bool _respectDoNotDisturb = true;
  
  // Stream management
  StreamController<Uint8List>? _audioStreamController;
  StreamController<double>? _amplitudeController;
  Timer? _streamTimer;
  
  // Recovery system
  String? _recoverySessionId;
  String? _recoveryFilePath;
  int _recoveryChunkNumber = 0;
  Duration _recoveryDuration = Duration.zero;
  List<Map<String, dynamic>> _recoveryChunks = [];
  
  // Services
  late ApiService _apiService;
  late StorageService _storageService;
  late FlutterLocalNotificationsPlugin _notifications;
  
  // Recording file management
  String? _currentRecordingPath;
  File? _currentRecordingFile;
  int _chunkNumber = 0;
  Timer? _chunkTimer;
  
  // Getters
  bool get isRecording => _isRecording;
  bool get isPaused => _isPaused;
  double get currentAmplitude => _currentAmplitude;
  double get gainLevel => _gainLevel;
  Duration get recordingDuration => _recordingDuration;
  AudioDeviceType get currentDevice => _currentDevice;
  bool get isBluetoothConnected => _isBluetoothConnected;
  bool get isWiredHeadsetConnected => _isWiredHeadsetConnected;
  String? get recoverySessionId => _recoverySessionId;
  
  // Public method to get current amplitude
  Future<Amplitude> getCurrentAmplitude() async {
    return await _audioRecorder.getAmplitude();
  }
  
  // Stream getters
  Stream<Uint8List>? get audioStream => _audioStreamController?.stream;
  Stream<double>? get amplitudeStream => _amplitudeController?.stream;
  
  void initialize(ApiService apiService, StorageService storageService) {
    _apiService = apiService;
    _storageService = storageService;
    _initializeNotifications();
    _checkForRecovery();
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
  
  Future<void> _checkForRecovery() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _recoverySessionId = prefs.getString('recovery_session_id');
      _recoveryFilePath = prefs.getString('recovery_file_path');
      _recoveryChunkNumber = prefs.getInt('recovery_chunk_number') ?? 0;
      _recoveryDuration = Duration(seconds: prefs.getInt('recovery_duration') ?? 0);
      
      if (_recoverySessionId != null) {
        debugPrint('Found recovery session: $_recoverySessionId');
        await _showRecoveryNotification();
      }
    } catch (e) {
      debugPrint('Error checking for recovery: $e');
    }
  }
  
  Future<void> _monitorAudioDevices() async {
    // Monitor audio device changes
    Timer.periodic(const Duration(seconds: 5), (timer) {
      _checkAudioDevices();
    });
  }
  
  Future<void> _checkAudioDevices() async {
    // Check for Bluetooth and wired headset connections
    // This would typically use platform channels to monitor audio device changes
    // For now, we'll implement basic monitoring
  }
  
  Future<bool> startRecording(RecordingSession session) async {
    if (_isRecording) {
      debugPrint('Already recording, stopping current session first');
      await stopRecording();
    }
    
    try {
      // Request permissions
      if (!await _requestPermissions()) {
        return false;
      }
      
      // Initialize audio stream controllers
      _audioStreamController = StreamController<Uint8List>.broadcast();
      _amplitudeController = StreamController<double>.broadcast();
      
      // Create recording file
      final directory = await getApplicationDocumentsDirectory();
      _currentRecordingPath = '${directory.path}/recording_${session.id}_${DateTime.now().millisecondsSinceEpoch}.m4a';
      _currentRecordingFile = File(_currentRecordingPath!);
      
      // Start recording
      await _audioRecorder.start(
        RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 44100,
          bitRate: 128000,
          numChannels: 1,
          autoGain: false,
          echoCancel: true,
          noiseSuppress: true,
        ),
        path: _currentRecordingPath!,
      );
      
      _isRecording = true;
      _chunkNumber = 0;
      _recordingDuration = Duration.zero;
      
      // Start amplitude monitoring
      _startAmplitudeMonitoring();
      
      // Start duration timer
      _startDurationTimer();
      
      // Start audio streaming
      _startAudioStreaming();
      
      // Start chunk processing
      _startChunkProcessing();
      
      // Save recovery state
      await _saveRecoveryState(session);
      
      // Show recording notification
      await _showRecordingNotification();
      
      notifyListeners();
      debugPrint('Native audio recording started successfully');
      return true;
      
    } catch (e) {
      debugPrint('Error starting recording: $e');
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
  
  void _startAmplitudeMonitoring() {
    _amplitudeSubscription = _audioRecorder.onAmplitudeChanged(
      const Duration(milliseconds: 100),
    ).listen((amplitude) {
      // Apply gain control
      final adjustedAmplitude = amplitude.current * _gainLevel;
      
      // Convert to percentage (0-100)
      _currentAmplitude = ((adjustedAmplitude + 60) / 60 * 100).clamp(0.0, 100.0);
      
      // Ensure we have some variation for visualization
      if (_currentAmplitude < 5.0) {
        _currentAmplitude = 5.0 + (amplitude.current.abs() % 10);
      }
      
      _amplitudeController?.add(_currentAmplitude);
      notifyListeners();
    });
  }
  
  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isRecording && !_isPaused) {
        _recordingDuration += const Duration(seconds: 1);
        notifyListeners();
      }
    });
  }
  
  void _startAudioStreaming() {
    try {
      // Use record package's built-in streaming capabilities
      // Start a timer to read audio data from the recording file in real-time
      _startTimerBasedStreaming();
    } catch (e) {
      debugPrint('Error starting audio streaming: $e');
    }
  }
  
  void _startTimerBasedStreaming() {
    // Real-time audio streaming using record package
    _streamTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) async {
      if (!_isRecording || _isPaused) {
        timer.cancel();
        return;
      }
      
      try {
        // Get current amplitude for visualization
        final amplitude = await _audioRecorder.getAmplitude();
        _currentAmplitude = ((amplitude.current + 60) / 60 * 100).clamp(0.0, 100.0);
        
        // Apply gain control to amplitude
        _currentAmplitude = (_currentAmplitude * _gainLevel).clamp(0.0, 100.0);
        
        _amplitudeController?.add(_currentAmplitude);
        notifyListeners();
        
        // Read audio data from the recording file for streaming
        if (_currentRecordingFile != null && _currentRecordingFile!.existsSync()) {
          final fileBytes = await _currentRecordingFile!.readAsBytes();
          if (fileBytes.isNotEmpty) {
            // Apply gain control to audio data
            final adjustedData = _applyGainControl(fileBytes);
            
            // Send audio data to stream
            _audioStreamController?.add(adjustedData);
          }
        }
      } catch (e) {
        debugPrint('Error in audio streaming: $e');
      }
    });
  }
  
  Uint8List _applyGainControl(Uint8List audioData) {
    if (_gainLevel == 1.0) return audioData;
    
    // Apply gain by scaling the audio samples
    final samples = Int16List.fromList(audioData);
    for (int i = 0; i < samples.length; i++) {
      samples[i] = (samples[i] * _gainLevel).clamp(-32768, 32767).round();
    }
    
    return Uint8List.fromList(samples.buffer.asUint8List());
  }
  
  // Removed _calculateAmplitudeFromSamples method as we now use record package's getAmplitude()
  
  void _startChunkProcessing() {
    // Process audio chunks every 5 seconds
    _chunkTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (_isRecording && !_isPaused) {
        await _processAudioChunk();
      }
    });
  }
  
  Future<void> _processAudioChunk() async {
    if (_currentRecordingFile == null || !_currentRecordingFile!.existsSync()) {
      return;
    }
    
    try {
      _chunkNumber++;
      
      // Read current audio data
      final fileBytes = await _currentRecordingFile!.readAsBytes();
      
      if (fileBytes.isNotEmpty) {
        // Create chunk data
        final chunkData = {
          'session_id': _recoverySessionId,
          'chunk_number': _chunkNumber,
          'data': fileBytes,
          'timestamp': DateTime.now().toIso8601String(),
          'duration': _recordingDuration.inSeconds,
        };
        
        // Store chunk for recovery
        _recoveryChunks.add(chunkData);
        
        // Send chunk to backend
        await _sendChunkToBackend(chunkData);
        
        // Save recovery state
        await _saveRecoveryState();
      }
    } catch (e) {
      debugPrint('Error processing audio chunk: $e');
    }
  }
  
  Future<void> _sendChunkToBackend(Map<String, dynamic> chunkData) async {
    try {
      // Send chunk to backend via API
      // This would typically use the API service to upload the chunk
      debugPrint('Sending chunk ${chunkData['chunk_number']} to backend');
      
      // For now, we'll just log the chunk
      debugPrint('Chunk data: ${chunkData['data'].length} bytes');
    } catch (e) {
      debugPrint('Error sending chunk to backend: $e');
    }
  }
  
  Future<void> pauseRecording() async {
    if (!_isRecording || _isPaused) return;
    
    try {
      await _audioRecorder.pause();
      _isPaused = true;
      
      // Pause timers
      _durationTimer?.cancel();
      _streamTimer?.cancel();
      _chunkTimer?.cancel();
      
      // Show pause notification
      await _showPauseNotification();
      
      notifyListeners();
      debugPrint('Recording paused');
    } catch (e) {
      debugPrint('Error pausing recording: $e');
    }
  }
  
  Future<void> resumeRecording() async {
    if (!_isRecording || !_isPaused) return;
    
    try {
      await _audioRecorder.resume();
      _isPaused = false;
      
      // Resume timers
      _startDurationTimer();
      _startAudioStreaming();
      _startChunkProcessing();
      
      // Show resume notification
      await _showResumeNotification();
      
      notifyListeners();
      debugPrint('Recording resumed');
    } catch (e) {
      debugPrint('Error resuming recording: $e');
    }
  }
  
  Future<void> stopRecording() async {
    if (!_isRecording) return;
    
    try {
      _isRecording = false;
      _isPaused = false;
      
      // Stop recording
      await _audioRecorder.stop();
      
      // Stop timers
      _durationTimer?.cancel();
      _streamTimer?.cancel();
      _chunkTimer?.cancel();
      _amplitudeSubscription?.cancel();
      
      // Close stream controllers
      await _audioStreamController?.close();
      await _amplitudeController?.close();
      
      // Process final chunk
      await _processFinalChunk();
      
      // Clear recovery state
      await _clearRecoveryState();
      
      // Show completion notification
      await _showCompletionNotification();
      
      notifyListeners();
      debugPrint('Recording stopped successfully');
    } catch (e) {
      debugPrint('Error stopping recording: $e');
    }
  }
  
  Future<void> _processFinalChunk() async {
    if (_currentRecordingFile == null || !_currentRecordingFile!.existsSync()) {
      return;
    }
    
    try {
      final fileBytes = await _currentRecordingFile!.readAsBytes();
      
      if (fileBytes.isNotEmpty) {
        final chunkData = {
          'session_id': _recoverySessionId,
          'chunk_number': _chunkNumber + 1,
          'data': fileBytes,
          'timestamp': DateTime.now().toIso8601String(),
          'duration': _recordingDuration.inSeconds,
          'is_final': true,
        };
        
        // Send final chunk to backend
        await _sendChunkToBackend(chunkData);
      }
    } catch (e) {
      debugPrint('Error processing final chunk: $e');
    }
  }
  
  // Recovery methods
  Future<void> _saveRecoveryState([RecordingSession? session]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      if (session != null) {
        await prefs.setString('recovery_session_id', session.id);
        await prefs.setString('recovery_file_path', _currentRecordingPath ?? '');
      }
      
      await prefs.setInt('recovery_chunk_number', _chunkNumber);
      await prefs.setString('recovery_duration', _recordingDuration.inSeconds.toString());
      await prefs.setString('recovery_timestamp', DateTime.now().toIso8601String());
      
      debugPrint('Recovery state saved');
    } catch (e) {
      debugPrint('Error saving recovery state: $e');
    }
  }
  
  Future<void> _clearRecoveryState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('recovery_session_id');
      await prefs.remove('recovery_file_path');
      await prefs.remove('recovery_chunk_number');
      await prefs.remove('recovery_duration');
      await prefs.remove('recovery_timestamp');
      
      _recoverySessionId = null;
      _recoveryFilePath = null;
      _recoveryChunkNumber = 0;
      _recoveryDuration = Duration.zero;
      _recoveryChunks.clear();
      
      debugPrint('Recovery state cleared');
    } catch (e) {
      debugPrint('Error clearing recovery state: $e');
    }
  }
  
  Future<bool> resumeFromRecovery() async {
    if (_recoverySessionId == null) {
      return false;
    }
    
    try {
      // Load session from recovery
      final session = await _apiService.getSession(_recoverySessionId!);
      if (session == null) {
        debugPrint('Recovery session not found');
        return false;
      }
      
      // Resume recording from recovery point
      _chunkNumber = _recoveryChunkNumber;
      _recordingDuration = _recoveryDuration;
      
      // Start recording with recovery data
      final success = await startRecording(session);
      
      if (success) {
        debugPrint('Recording resumed from recovery');
        return true;
      }
      
      return false;
    } catch (e) {
      debugPrint('Error resuming from recovery: $e');
      return false;
    }
  }
  
  Future<void> dismissRecovery() async {
    await _clearRecoveryState();
    debugPrint('Recovery dismissed');
  }
  
  // Audio device management
  Future<void> switchToDeviceMicrophone() async {
    _currentDevice = AudioDeviceType.deviceMicrophone;
    await _handleAudioDeviceChange();
    notifyListeners();
  }
  
  Future<void> switchToBluetoothHeadset() async {
    _currentDevice = AudioDeviceType.bluetoothHeadset;
    await _handleAudioDeviceChange();
    notifyListeners();
  }
  
  Future<void> switchToWiredHeadset() async {
    _currentDevice = AudioDeviceType.wiredHeadset;
    await _handleAudioDeviceChange();
    notifyListeners();
  }
  
  Future<void> _handleAudioDeviceChange() async {
    if (_isRecording) {
      // Handle audio device changes during recording
      debugPrint('Audio device changed to: $_currentDevice');
      
      // Show notification
      await _showAudioDeviceChangeNotification();
    }
  }
  
  // Gain control
  void setGainLevel(double level) {
    _gainLevel = level.clamp(0.1, 3.0);
    notifyListeners();
  }
  
  void increaseGain() {
    setGainLevel(_gainLevel + 0.1);
    HapticFeedback.lightImpact();
  }
  
  void decreaseGain() {
    setGainLevel(_gainLevel - 0.1);
    HapticFeedback.lightImpact();
  }
  
  // Do Not Disturb handling
  void setRespectDoNotDisturb(bool respect) {
    _respectDoNotDisturb = respect;
    notifyListeners();
  }
  
  // Notification methods
  Future<void> _showRecordingNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'native_audio_recording',
      'Audio Recording',
      channelDescription: 'Native audio recording notifications',
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
      'Recording Active',
      'Native audio recording in progress',
      notificationDetails,
    );
  }
  
  Future<void> _showPauseNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'native_audio_recording',
      'Audio Recording',
      channelDescription: 'Native audio recording notifications',
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
      'Native audio recording paused',
      notificationDetails,
    );
  }
  
  Future<void> _showResumeNotification() async {
    await _showRecordingNotification();
  }
  
  Future<void> _showCompletionNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'native_audio_recording',
      'Audio Recording',
      channelDescription: 'Native audio recording notifications',
      importance: Importance.high,
      priority: Priority.high,
    );
    
    const notificationDetails = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      2,
      'Recording Complete',
      'Native audio recording completed successfully',
      notificationDetails,
    );
  }
  
  Future<void> _showRecoveryNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'audio_recovery',
      'Audio Recovery',
      channelDescription: 'Audio recording recovery notifications',
      importance: Importance.high,
      priority: Priority.high,
      actions: [
        AndroidNotificationAction('resume', 'Resume Recording'),
        AndroidNotificationAction('dismiss', 'Dismiss'),
      ],
    );
    
    const notificationDetails = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      3,
      'Recording Recovery Available',
      'Previous recording session can be resumed',
      notificationDetails,
    );
  }
  
  Future<void> _showAudioDeviceChangeNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'audio_device_change',
      'Audio Device',
      channelDescription: 'Audio device change notifications',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    
    const notificationDetails = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      4,
      'Audio Device Changed',
      'Switched to ${_currentDevice.name}',
      notificationDetails,
    );
  }
  
  @override
  void dispose() {
    _amplitudeSubscription?.cancel();
    _audioStreamSubscription?.cancel();
    // _micStreamSubscription?.cancel();  // Not used with record package approach
    _durationTimer?.cancel();
    _streamTimer?.cancel();
    _chunkTimer?.cancel();
    _audioStreamController?.close();
    _amplitudeController?.close();
    _audioRecorder.dispose();
    super.dispose();
  }
}
