import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'audio_streaming_service.dart';
import 'api_service.dart';
import 'notification_service.dart';

class OfflineRecordingService with ChangeNotifier {
  static final OfflineRecordingService _instance = OfflineRecordingService._internal();
  factory OfflineRecordingService() => _instance;
  OfflineRecordingService._internal();
  
  // Callback for notifications
  Function(int chunkCount)? _onUploadStart;
  Function(int chunkCount)? _onUploadSuccess;
  Function(String error)? _onUploadError;

  final Connectivity _connectivity = Connectivity();
  final AudioStreamingService _streamingService = AudioStreamingService();
  
  bool _isOfflineRecording = false;
  String? _currentOfflineSessionId;
  List<Map<String, dynamic>> _offlineChunks = [];
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _uploadTimer;
  
  // Getters
  bool get isOfflineRecording => _isOfflineRecording;
  String? get currentOfflineSessionId => _currentOfflineSessionId;
  int get offlineChunkCount => _offlineChunks.length;
  
  Future<void> initialize() async {
    // Listen for connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(_onConnectivityChanged);
    
    // Check for pending offline recordings on startup
    await _checkPendingOfflineRecordings();
  }
  
  // Set notification callbacks
  void setNotificationCallbacks({
    Function(int chunkCount)? onUploadStart,
    Function(int chunkCount)? onUploadSuccess,
    Function(String error)? onUploadError,
  }) {
    _onUploadStart = onUploadStart;
    _onUploadSuccess = onUploadSuccess;
    _onUploadError = onUploadError;
  }

  
  // Start offline recording when network fails
  Future<void> startOfflineRecording(String sessionId) async {
    if (_isOfflineRecording) return;
    
    _isOfflineRecording = true;
    _currentOfflineSessionId = sessionId;
    _offlineChunks.clear();
    
    print('📱 Starting offline recording for session: $sessionId');
    notifyListeners();
  }
  
  // Add chunk to offline storage
  Future<void> addOfflineChunk(String sessionId, Map<String, dynamic> chunkData) async {
    if (!_isOfflineRecording || _currentOfflineSessionId != sessionId) return;
    
    _offlineChunks.add({
      'session_id': sessionId,
      'chunk_data': chunkData,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    
    // Save to local storage
    await _saveOfflineChunks();
    
    print('💾 Stored offline chunk for session: $sessionId (Total: ${_offlineChunks.length})');
  }
  
  // Stop offline recording
  Future<void> stopOfflineRecording() async {
    if (!_isOfflineRecording) return;
    
    _isOfflineRecording = false;
    _currentOfflineSessionId = null;
    
    print('📱 Stopped offline recording');
    notifyListeners();
  }
  
  // Handle connectivity changes
  void _onConnectivityChanged(List<ConnectivityResult> results) async {
    final isOnline = results.any((result) => 
      result == ConnectivityResult.wifi || 
      result == ConnectivityResult.mobile ||
      result == ConnectivityResult.ethernet
    );
    
    if (isOnline && _isOfflineRecording) {
      print('🌐 Network restored, attempting to upload offline chunks...');
      await _uploadOfflineChunks();
    } else if (!isOnline && _streamingService.isStreaming) {
      print('📱 Network lost, switching to offline recording...');
      await startOfflineRecording(_streamingService.sessionId!);
    }
  }
  
  // Upload offline chunks when network is restored
  Future<void> _uploadOfflineChunks() async {
    if (_offlineChunks.isEmpty) return;
    
    try {
      print('📤 Uploading ${_offlineChunks.length} offline chunks...');
      
      // Show upload start notification
      _onUploadStart?.call(_offlineChunks.length);
      
      // Create a temporary WebSocket connection for uploading
      final channel = await _createUploadConnection();
      
      for (final chunk in _offlineChunks) {
        channel.sink.add(jsonEncode({
          'type': 'audio_chunk',
          'session_id': chunk['session_id'],
          'chunk_data': chunk['chunk_data'],
        }));
        
        // Small delay to prevent overwhelming the server
        await Future.delayed(const Duration(milliseconds: 10));
      }
      
      // Send session end message
      channel.sink.add(jsonEncode({
        'type': 'session_end',
        'session_id': _currentOfflineSessionId,
      }));
      
      // Close connection
      await channel.sink.close();
      
      // Clear offline data
      await _clearOfflineChunks();
      await stopOfflineRecording();
      
      print('✅ Successfully uploaded offline chunks');
      
      // Show success notification
      _onUploadSuccess?.call(_offlineChunks.length);
      
    } catch (e) {
      print('❌ Failed to upload offline chunks: $e');
      // Keep chunks for retry later
      
      // Show error notification
      _onUploadError?.call(e.toString());
    }
  }
  
  // Create WebSocket connection for uploading
  Future<WebSocketChannel> _createUploadConnection() async {
    // Use API service base URL for WebSocket connection
    final wsUrl = ApiService.baseUrl.replaceFirst('https://', 'wss://');
    return WebSocketChannel.connect(Uri.parse(wsUrl));
  }
  
  // Check for pending offline recordings on app startup
  Future<void> _checkPendingOfflineRecordings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final offlineData = prefs.getString('offline_recording_data');
      
      if (offlineData != null) {
        final data = jsonDecode(offlineData);
        _currentOfflineSessionId = data['session_id'];
        _offlineChunks = List<Map<String, dynamic>>.from(data['chunks']);
        
        if (_offlineChunks.isNotEmpty) {
          print('📱 Found ${_offlineChunks.length} pending offline chunks for session: $_currentOfflineSessionId');
          
          // Try to upload immediately if online
          final connectivityResults = await _connectivity.checkConnectivity();
          final isOnline = connectivityResults.any((result) => 
            result == ConnectivityResult.wifi || 
            result == ConnectivityResult.mobile ||
            result == ConnectivityResult.ethernet
          );
          
          if (isOnline) {
            await _uploadOfflineChunks();
          }
        }
      }
    } catch (e) {
      print('❌ Error checking pending offline recordings: $e');
    }
  }
  
  // Save offline chunks to local storage
  Future<void> _saveOfflineChunks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('offline_recording_data', jsonEncode({
        'session_id': _currentOfflineSessionId,
        'chunks': _offlineChunks,
        'last_updated': DateTime.now().millisecondsSinceEpoch,
      }));
    } catch (e) {
      print('❌ Error saving offline chunks: $e');
    }
  }
  
  // Clear offline chunks from storage
  Future<void> _clearOfflineChunks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('offline_recording_data');
      _offlineChunks.clear();
    } catch (e) {
      print('❌ Error clearing offline chunks: $e');
    }
  }
  
  // Get offline recording status for UI
  Map<String, dynamic> getOfflineStatus() {
    return {
      'is_offline_recording': _isOfflineRecording,
      'session_id': _currentOfflineSessionId,
      'chunk_count': _offlineChunks.length,
      'status': _isOfflineRecording ? 'Recording Offline' : 'Online',
    };
  }
  
  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _uploadTimer?.cancel();
    super.dispose();
  }
}
