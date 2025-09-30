import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:sound_stream/sound_stream.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'api_service.dart';
import 'offline_recording_service.dart';
import 'app_lifecycle_service.dart';

class AudioStreamingService with ChangeNotifier {
  static final AudioStreamingService _instance = AudioStreamingService._internal();
  factory AudioStreamingService() => _instance;
  AudioStreamingService._internal();

  // Callback to update amplitude in AudioRecordingService
  Function(double current, double max)? _onAmplitudeUpdate;
  
  // Offline recording service - will be injected
  OfflineRecordingService? _offlineService;
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _websocketHealthTimer;
  AppLifecycleService? _appLifecycleService;

  WebSocketChannel? _channel;
  RecorderStream? _recorder;
  StreamSubscription? _recorderStatus;
  StreamSubscription? _audioStream;
  StreamSubscription? _websocketSubscription;
  Timer? _amplitudeTimer;
  
  bool _isStreaming = false;
  bool _isConnected = false;
  String? _sessionId;
  
  // Audio data collection for amplitude calculation
  List<Uint8List> _recentAudioData = [];
  
  // Streaming statistics
  int _bytesStreamed = 0;
  int _chunksStreamed = 0;
  
  // Initialize the service
  Future<void> initialize() async {
    print('🔄 Audio streaming service initialized with sound_stream');
    
    // Initialize app lifecycle service
    _appLifecycleService = AppLifecycleService();
    _appLifecycleService!.initialize();
    
    // Listen to app lifecycle changes
    _appLifecycleService!.addListener(_onAppLifecycleChanged);
  }
  
  // Inject offline recording service
  void setOfflineService(OfflineRecordingService offlineService) {
    _offlineService = offlineService;
  }

  // Handle app lifecycle changes
  void _onAppLifecycleChanged() {
    if (_appLifecycleService == null) return;
    
    if (_appLifecycleService!.isInBackground && _isStreaming) {
      print('📱 App went to background - maintaining WebSocket connection');
      // Don't switch to offline mode when app goes to background
      // Keep the WebSocket connection alive
    } else if (_appLifecycleService!.isInForeground && _isStreaming) {
      print('📱 App came to foreground - checking WebSocket connection');
      // Check if WebSocket is still connected when app comes back
      // But don't reconnect if offline recording is active
      if (!_isConnected && _channel != null && _offlineService?.isOfflineRecording != true) {
        print('🔄 WebSocket disconnected while in background, attempting to reconnect...');
        _reconnectWebSocket();
      } else if (_offlineService?.isOfflineRecording == true) {
        print('📱 Offline recording active, staying in offline mode');
      }
    }
  }

  // Reconnect WebSocket if it was disconnected
  Future<void> _reconnectWebSocket() async {
    if (_sessionId == null) return;
    
    try {
      await _connectWebSocket();
      if (_isConnected) {
        print('✅ WebSocket reconnected successfully');
        // Send session start message again
        _channel!.sink.add(jsonEncode({
          'type': 'session_start',
          'session_id': _sessionId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }));
      }
    } catch (e) {
      print('❌ Failed to reconnect WebSocket: $e');
      // If reconnection fails, then switch to offline mode
      _handleWebSocketFailure();
    }
  }

  // Set amplitude update callback
  void setAmplitudeCallback(Function(double current, double max) callback) {
    _onAmplitudeUpdate = callback;
  }

  // Start audio streaming session
  Future<void> startStreaming(String sessionId) async {
    if (_isStreaming) {
      print('⚠️ Already streaming, stopping current session first');
      await stopStreaming();
    }

    _sessionId = sessionId;
    _isStreaming = true;
    
    print('🎬 Starting audio streaming session: $sessionId');
    
    // Request microphone permission
    if (!await _requestMicrophonePermission()) {
      print('❌ Microphone permission denied');
      return;
    }
    
    // Connect to WebSocket
    await _connectWebSocket();
    
    // Start recording with real-time streaming
    await _startRecording();
    
    // Start amplitude monitoring
    _startAmplitudeMonitoring();
    
    // Start connectivity monitoring
    _startConnectivityMonitoring();
    
    // Start WebSocket health monitoring
    _startWebSocketHealthCheck();
    
    notifyListeners();
  }

  // Request microphone permission
  Future<bool> _requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    return status == PermissionStatus.granted;
  }

  // Connect to WebSocket
  Future<void> _connectWebSocket() async {
    try {
      // Use API service base URL for WebSocket connection
      final wsUrl = ApiService.baseUrl.replaceFirst('https://', 'wss://');
      
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _isConnected = true;
      
      print('🔌 WebSocket connected: $_sessionId');
      
      // Listen for WebSocket errors and close events
      _websocketSubscription = _channel!.stream.listen(
        (data) {
          // Handle incoming messages (if any)
          print('📨 Received WebSocket message: $data');
        },
        onError: (error) {
          print('❌ WebSocket error: $error');
          _handleWebSocketFailure();
        },
        onDone: () {
          print('🔌 WebSocket connection closed');
          _handleWebSocketFailure();
        },
      );
      
      // Send session start message
      _channel!.sink.add(jsonEncode({
        'type': 'session_start',
        'session_id': _sessionId,
        'patient_id': _sessionId!.split('_').last,
      }));
      
    } catch (e) {
      print('❌ WebSocket connection failed: $e');
      _isConnected = false;
      _handleWebSocketFailure();
    }
  }

  // Start recording with real-time streaming
  Future<void> _startRecording() async {
    try {
      _recorder = RecorderStream();
      
      // Initialize the recorder with 16kHz sample rate
      await _recorder!.initialize(
        sampleRate: 16000,          // 16kHz for medical recordings
      );
      
      // Listen to recorder status
      _recorderStatus = _recorder!.status.listen((status) {
        print('🎤 Recorder status: $status');
      });
      
      // Listen to audio stream for real-time data
      _audioStream = _recorder!.audioStream.listen((Uint8List data) {
        _processAudioChunk(data);
      });
      
      // Start recording
      await _recorder!.start();
      
      print('🎤 Recording started with sound_stream');
      print('🔍 sound_stream configured: 16-bit PCM, 16kHz, mono (medical quality)');
      
    } catch (e) {
      print('❌ Failed to start recording: $e');
    }
  }

  // Process audio chunk in real-time
  void _processAudioChunk(Uint8List audioChunk) {
    if (!_isStreaming) return;
    
    try {
      // Update statistics
      _bytesStreamed += audioChunk.length;
      _chunksStreamed++;
      
      // Store recent audio data for amplitude calculation
      _recentAudioData.add(audioChunk);
      
      // Keep only recent data (last 1 second worth)
      if (_recentAudioData.length > 10) { // Keep last 10 chunks
        _recentAudioData = _recentAudioData.sublist(_recentAudioData.length - 10);
      }
      
      // Debug: Check if we're getting real audio data
      if (_chunksStreamed % 50 == 0) { // Log every 50th chunk
        final hasNonZeroData = audioChunk.any((byte) => byte != 0);
        print('🔍 Audio chunk ${_chunksStreamed}: ${audioChunk.length} bytes, has non-zero data: $hasNonZeroData');
        if (audioChunk.length > 0) {
          print('🔍 First few bytes: ${audioChunk.take(8).toList()}');
          print('🔍 Expected: ~1280 samples per chunk (2560 bytes / 2 bytes per sample) for 16kHz');
          
          // Check for audio quality indicators
          final maxAmplitude = audioChunk.fold<int>(0, (max, byte) => byte > max ? byte : max);
          final minAmplitude = audioChunk.fold<int>(255, (min, byte) => byte < min ? byte : min);
          print('🔍 Audio range: $minAmplitude to $maxAmplitude (should vary for good quality)');
          
          // Check for potential clipping (values near 0 or 255)
          final clippingCount = audioChunk.where((byte) => byte < 5 || byte > 250).length;
          if (clippingCount > audioChunk.length * 0.1) { // More than 10% clipping
            print('⚠️ Potential clipping detected: $clippingCount/${audioChunk.length} samples');
          }
        }
      }
      
      // Convert to base64 for transmission
      final base64Audio = base64Encode(audioChunk);
      final chunkData = {
        'chunk_data': base64Audio,
        'chunk_size': audioChunk.length,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      
      // Check if offline recording has been started - if so, always store offline
      if (_offlineService?.isOfflineRecording == true) {
        // Once offline recording starts, all chunks go offline until recording ends
        print('📱 Offline recording active, storing chunk offline');
        _offlineService?.addOfflineChunk(_sessionId!, chunkData);
      } else if (_isConnected && _channel != null) {
        try {
          // Send to backend via WebSocket
          _channel!.sink.add(jsonEncode({
            'type': 'audio_chunk',
            'session_id': _sessionId,
            ...chunkData,
          }));
          
          print('📤 Sent audio chunk ${_chunksStreamed} (${audioChunk.length} bytes)');
        } catch (e) {
          // WebSocket send failed, switch to offline mode
          print('❌ WebSocket send failed: $e');
          _handleWebSocketFailure();
          _offlineService?.addOfflineChunk(_sessionId!, chunkData);
        }
      } else {
        // Network is down, store offline
        print('📱 Network down, storing chunk offline');
        _offlineService?.addOfflineChunk(_sessionId!, chunkData);
      }
      
    } catch (e) {
      print('❌ Error processing audio chunk: $e');
    }
  }

  // Handle WebSocket failure immediately
  void _handleWebSocketFailure() {
    if (!_isStreaming) return;
    
    print('🚨 WebSocket failure detected, switching to offline recording immediately');
    _isConnected = false;
    
    // Start offline recording immediately
    _offlineService?.startOfflineRecording(_sessionId!);
    
    // Notify listeners
    notifyListeners();
  }
  
  // Start WebSocket health check
  void _startWebSocketHealthCheck() {
    _websocketHealthTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_isStreaming && _isConnected && _channel != null) {
        try {
          // Send a ping message to check if WebSocket is still alive
          _channel!.sink.add(jsonEncode({
            'type': 'ping',
            'session_id': _sessionId,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          }));
          print('🏓 WebSocket ping sent');
        } catch (e) {
          print('❌ WebSocket ping failed: $e');
          _handleWebSocketFailure();
        }
      }
    });
  }
  
  // Start connectivity monitoring
  void _startConnectivityMonitoring() {
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((results) {
      final isOnline = results.any((result) => 
        result == ConnectivityResult.wifi || 
        result == ConnectivityResult.mobile ||
        result == ConnectivityResult.ethernet
      );
      
      if (!isOnline && _isStreaming && !_offlineService!.isOfflineRecording) {
        print('📱 Network lost, switching to offline recording...');
        _offlineService!.startOfflineRecording(_sessionId!);
      } else if (isOnline && _offlineService!.isOfflineRecording) {
        print('🌐 Network restored, but staying in offline mode until recording ends...');
        // Don't restart online streaming - stay in offline mode until recording ends
        // The offline service will handle the upload automatically when recording ends
      }
    });
  }
  
  // Start amplitude monitoring for UI
  void _startAmplitudeMonitoring() {
    _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      if (_isStreaming && _recentAudioData.isNotEmpty) {
        try {
          // Calculate amplitude from recent audio data
          final amplitude = _calculateAmplitude(_recentAudioData);
          _onAmplitudeUpdate?.call(amplitude['current']!, amplitude['max']!);
        } catch (e) {
          print('❌ Error calculating amplitude: $e');
        }
      } else {
        timer.cancel();
      }
    });
  }

  // Calculate amplitude from audio data
  Map<String, double> _calculateAmplitude(List<Uint8List> audioData) {
    if (audioData.isEmpty) return {'current': 0.0, 'max': 0.0};
    
    // Combine all recent audio chunks
    final combinedData = <int>[];
    for (final chunk in audioData) {
      combinedData.addAll(chunk);
    }
    
    if (combinedData.isEmpty) return {'current': 0.0, 'max': 0.0};
    
    // Convert bytes to 16-bit PCM samples
    final samples = <int>[];
    for (int i = 0; i < combinedData.length - 1; i += 2) {
      final sample = (combinedData[i] | (combinedData[i + 1] << 8));
      samples.add(sample > 32767 ? sample - 65536 : sample);
    }
    
    if (samples.isEmpty) return {'current': 0.0, 'max': 0.0};
    
    // Calculate RMS amplitude
    double sum = 0.0;
    for (final sample in samples) {
      sum += sample * sample;
    }
    final rms = sqrt(sum / samples.length);
    
    // Convert to dB scale
    final amplitude = 20 * log(rms / 32768) / 2.302585092994046;
    
    // Debug: Log amplitude values occasionally
    if (_chunksStreamed % 100 == 0) {
      print('🔍 Amplitude calculation: RMS=$rms, amplitude=$amplitude, samples=${samples.length}');
    }
    
    return {
      'current': amplitude.isFinite ? amplitude : -60.0,
      'max': amplitude.isFinite ? amplitude : -60.0,
    };
  }

  // Pause streaming
  Future<void> pauseStreaming() async {
    if (!_isStreaming) return;
    
    print('⏸️ Pausing audio streaming: $_sessionId');
    
    // Send pause message to backend
    if (_channel != null && _sessionId != null) {
      try {
        _channel!.sink.add(jsonEncode({
          'type': 'session_pause',
          'session_id': _sessionId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }));
        print('⏸️ Sent pause message to backend for session: $_sessionId');
      } catch (e) {
        print('❌ Error sending pause message: $e');
      }
    }
    
    // Pause the recorder
    await _recorder?.stop();
    
    // Cancel amplitude monitoring
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;
    
    notifyListeners();
  }

  // Resume streaming
  Future<void> resumeStreaming() async {
    if (!_isStreaming) return;
    
    print('▶️ Resuming audio streaming: $_sessionId');
    
    // Send resume message to backend
    if (_channel != null && _sessionId != null) {
      try {
        _channel!.sink.add(jsonEncode({
          'type': 'session_resume',
          'session_id': _sessionId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }));
        print('▶️ Sent resume message to backend for session: $_sessionId');
      } catch (e) {
        print('❌ Error sending resume message: $e');
      }
    }
    
    // Resume the recorder
    await _recorder?.start();
    
    // Restart amplitude monitoring
    _startAmplitudeMonitoring();
    
    notifyListeners();
  }

  // Stop streaming
  Future<void> stopStreaming() async {
    if (!_isStreaming) return;
    
    print('⏹️ Stopping audio streaming: $_sessionId');
    
    try {
      // Stop recording
      await _recorder?.stop();
      
      // Cancel subscriptions
      await _recorderStatus?.cancel();
      await _audioStream?.cancel();
      _recorderStatus = null;
      _audioStream = null;
      _recorder = null;
      
      // Notify UI immediately that recording has stopped
      notifyListeners();
      
      // Stop amplitude monitoring
      _amplitudeTimer?.cancel();
      _amplitudeTimer = null;
      
      // Stop WebSocket health monitoring
      _websocketHealthTimer?.cancel();
      _websocketHealthTimer = null;
      
      // Cancel WebSocket subscription
      _websocketSubscription?.cancel();
      _websocketSubscription = null;
      
      // Clear audio data
      _recentAudioData.clear();
      
      // Send session end message first
      if (_isConnected && _channel != null) {
        _channel!.sink.add(jsonEncode({
          'type': 'session_end',
          'session_id': _sessionId,
        }));
      }
      
      // Close WebSocket with proper close code
      if (_channel != null) {
        _channel!.sink.close(1000); // Use standard close code
        _channel = null;
      }
      
    } catch (e) {
      print('❌ Error stopping streaming: $e');
    } finally {
      _isStreaming = false;
      _isConnected = false;
      _sessionId = null;
      _bytesStreamed = 0;
      _chunksStreamed = 0;
      notifyListeners();
    }
    
    // Upload offline chunks asynchronously after UI is updated
    if (_offlineService?.isOfflineRecording == true) {
      print('🎬 Recording ended, uploading offline chunks asynchronously...');
      // Don't await - let it happen in background
      _offlineService?.uploadOfflineChunksOnRecordingEnd().catchError((error) {
        print('❌ Error uploading offline chunks: $error');
      });
    }
  }

  // Getters
  bool get isStreaming => _isStreaming;
  bool get isConnected => _isConnected;
  String? get sessionId => _sessionId;
  int get bytesStreamed => _bytesStreamed;
  int get chunksStreamed => _chunksStreamed;
  
  // Send keep alive ping to maintain WebSocket connection
  void sendKeepAlivePing() {
    if (_isConnected && _channel != null && _sessionId != null) {
      try {
        _channel!.sink.add(jsonEncode({
          'type': 'ping',
          'session_id': _sessionId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }));
        print('🏓 Sent keep alive ping for session: $_sessionId');
      } catch (e) {
        print('❌ Error sending keep alive ping: $e');
        _handleWebSocketFailure();
      }
    }
  }

  
  @override
  void dispose() {
    _amplitudeTimer?.cancel();
    _websocketHealthTimer?.cancel();
    _connectivitySubscription?.cancel();
    _websocketSubscription?.cancel();
    _appLifecycleService?.removeListener(_onAppLifecycleChanged);
    _recorderStatus?.cancel();
    _audioStream?.cancel();
    _recorder?.dispose();
    super.dispose();
  }
}