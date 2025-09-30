import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api_service.dart';

class BackgroundWebSocketService {
  static final BackgroundWebSocketService _instance = BackgroundWebSocketService._internal();
  factory BackgroundWebSocketService() => _instance;
  BackgroundWebSocketService._internal();

  WebSocketChannel? _channel;
  bool _isConnected = false;
  String? _sessionId;
  Timer? _keepAliveTimer;
  StreamSubscription? _websocketSubscription;

  // Getters
  bool get isConnected => _isConnected;
  String? get sessionId => _sessionId;

  // Start background WebSocket connection
  Future<void> startBackgroundConnection(String sessionId) async {
    if (_isConnected && _sessionId == sessionId) {
      print('🔌 Background WebSocket already connected for session: $sessionId');
      return;
    }

    try {
      _sessionId = sessionId;
      
      // Use API service base URL for WebSocket connection
      final wsUrl = ApiService.baseUrl.replaceFirst('https://', 'wss://');
      
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _isConnected = true;
      
      print('🔌 Background WebSocket connected: $sessionId');
      
      // Listen for WebSocket events
      _websocketSubscription = _channel!.stream.listen(
        (data) {
          print('📨 Background WebSocket received: $data');
        },
        onError: (error) {
          print('❌ Background WebSocket error: $error');
          _isConnected = false;
        },
        onDone: () {
          print('🔌 Background WebSocket closed');
          _isConnected = false;
        },
      );

      // Send session start message
      _channel!.sink.add(jsonEncode({
        'type': 'session_start',
        'session_id': sessionId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'background': true,
      }));

      // Start keep-alive timer
      _startKeepAliveTimer();

    } catch (e) {
      print('❌ Failed to start background WebSocket: $e');
      _isConnected = false;
    }
  }

  // Start keep-alive timer to maintain connection
  void _startKeepAliveTimer() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isConnected && _channel != null) {
        try {
          _channel!.sink.add(jsonEncode({
            'type': 'ping',
            'session_id': _sessionId,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          }));
          print('🏓 Background WebSocket ping sent');
        } catch (e) {
          print('❌ Failed to send ping: $e');
          _isConnected = false;
        }
      } else {
        timer.cancel();
      }
    });
  }

  // Send audio chunk through background connection
  Future<void> sendAudioChunk(Map<String, dynamic> chunkData) async {
    if (!_isConnected || _channel == null) {
      print('❌ Background WebSocket not connected, cannot send chunk');
      return;
    }

    try {
      _channel!.sink.add(jsonEncode({
        'type': 'audio_chunk',
        'session_id': _sessionId,
        'chunk_data': chunkData['chunk_data'],
        'chunk_size': chunkData['chunk_size'],
        'timestamp': chunkData['timestamp'],
        'background': true,
      }));
    } catch (e) {
      print('❌ Failed to send audio chunk via background WebSocket: $e');
    }
  }

  // End session through background connection
  Future<void> endSession() async {
    if (!_isConnected || _channel == null) {
      print('❌ Background WebSocket not connected, cannot end session');
      return;
    }

    try {
      _channel!.sink.add(jsonEncode({
        'type': 'session_end',
        'session_id': _sessionId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'background': true,
      }));
      print('🔚 Background WebSocket session ended');
    } catch (e) {
      print('❌ Failed to end session via background WebSocket: $e');
    }
  }

  // Stop background connection
  Future<void> stopBackgroundConnection() async {
    _keepAliveTimer?.cancel();
    _websocketSubscription?.cancel();
    
    if (_channel != null) {
      try {
        await _channel!.sink.close();
      } catch (e) {
        print('❌ Error closing background WebSocket: $e');
      }
    }
    
    _channel = null;
    _isConnected = false;
    _sessionId = null;
    
    print('🔌 Background WebSocket connection stopped');
  }

  // Request battery optimization exemption
  Future<bool> requestBatteryOptimizationExemption() async {
    try {
      const platform = MethodChannel('com.medinote.app/battery_optimization');
      final bool granted = await platform.invokeMethod('requestBatteryOptimizationExemption');
      return granted;
    } catch (e) {
      print('❌ Failed to request battery optimization exemption: $e');
      return false;
    }
  }

  // Request system alert window permission
  Future<bool> requestSystemAlertWindowPermission() async {
    try {
      const platform = MethodChannel('com.medinote.app/permissions');
      final bool granted = await platform.invokeMethod('requestSystemAlertWindowPermission');
      return granted;
    } catch (e) {
      print('❌ Failed to request system alert window permission: $e');
      return false;
    }
  }

  // Check if background processing is allowed
  Future<bool> isBackgroundProcessingAllowed() async {
    try {
      const platform = MethodChannel('com.medinote.app/permissions');
      final bool allowed = await platform.invokeMethod('isBackgroundProcessingAllowed');
      return allowed;
    } catch (e) {
      print('❌ Failed to check background processing status: $e');
      return false;
    }
  }
}
