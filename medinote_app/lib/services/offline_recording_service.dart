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
  Function()? _onOfflineRecordingEnd; // New callback for when offline recording ends

  final Connectivity _connectivity = Connectivity();
  final AudioStreamingService _streamingService = AudioStreamingService();
  
  bool _isOfflineRecording = false;
  bool _isUploading = false;
  String? _currentOfflineSessionId;
  List<Map<String, dynamic>> _offlineChunks = [];
  int _offlineChunkSequence = 0;
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
    Function()? onOfflineRecordingEnd, // New callback
  }) {
    _onUploadStart = onUploadStart;
    _onUploadSuccess = onUploadSuccess;
    _onUploadError = onUploadError;
    _onOfflineRecordingEnd = onOfflineRecordingEnd; // New callback
  }
  
  // Start offline recording when network fails
  Future<void> startOfflineRecording(String sessionId) async {
    if (_isOfflineRecording) return;
    
    _isOfflineRecording = true;
    _currentOfflineSessionId = sessionId;
    _offlineChunks.clear();
    _offlineChunkSequence = 0;
    
    print('📱 Starting offline recording for session: $sessionId');
    notifyListeners();
  }
  
  // Add chunk to offline storage
  Future<void> addOfflineChunk(String sessionId, Map<String, dynamic> chunkData) async {
    if (!_isOfflineRecording || _currentOfflineSessionId != sessionId || _isUploading) return;
    
    _offlineChunkSequence++;
    _offlineChunks.add({
      'session_id': sessionId,
      'chunk_data': chunkData,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'sequence': _offlineChunkSequence,
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
    
    // Notify UI that offline recording has ended
    _onOfflineRecordingEnd?.call();
    
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
      print('🌐 Network restored, but staying in offline mode until recording ends...');
      // Don't upload chunks automatically - wait for recording to end
    } else if (!isOnline && _streamingService.isStreaming) {
      print('📱 Network lost, switching to offline recording...');
      await startOfflineRecording(_streamingService.sessionId!);
    }
  }
  
  // Manually trigger upload when recording ends
  Future<void> uploadOfflineChunksOnRecordingEnd() async {
    if (_isOfflineRecording && _offlineChunks.isNotEmpty) {
      print('🎬 Recording ended, checking backend health before uploading offline chunks...');
      await _uploadOfflineChunksWithHealthCheck();
      
      // Ensure UI is updated after offline upload completes
      print('📱 Offline upload completed, ensuring UI state is updated');
      notifyListeners();
    } else {
      print('📱 No offline recording or chunks to upload');
      // Still reset the state if we were in offline mode
      if (_isOfflineRecording) {
        await stopOfflineRecording();
      }
    }
  }
  
  // Upload offline chunks with health check retry logic
  Future<void> _uploadOfflineChunksWithHealthCheck() async {
    if (_offlineChunks.isEmpty || _isUploading) return;
    
    print('🏥 Starting backend health check before offline chunk upload...');
    
    int retryCount = 0;
    const maxRetries = 10;
    const retryDelay = Duration(seconds: 2);
    
    while (retryCount < maxRetries) {
      try {
        print('🏥 Health check attempt ${retryCount + 1}/$maxRetries...');
        
        // Import ApiService for health check
        final healthResponse = await ApiService.checkHealth();
        print('✅ Backend health check successful: $healthResponse');
        
        // Health check passed, proceed with upload
        await _uploadOfflineChunks();
        return;
        
      } catch (e) {
        retryCount++;
        print('❌ Health check failed (attempt $retryCount/$maxRetries): $e');
        
        if (retryCount < maxRetries) {
          print('⏳ Retrying health check in ${retryDelay.inSeconds} seconds...');
          await Future.delayed(retryDelay);
        } else {
          print('❌ Max retries reached. Backend appears to be down. Keeping offline chunks for later upload.');
          _onUploadError?.call('Backend health check failed after $maxRetries attempts: $e');
          return;
        }
      }
    }
  }

  // Upload offline chunks when network is restored
  Future<void> _uploadOfflineChunks() async {
    if (_offlineChunks.isEmpty || _isUploading) return;
    
    _isUploading = true;
    
    try {
      print('📤 Uploading ${_offlineChunks.length} offline chunks (IT MAY TAKE A WHILE)');
      
      // Create a copy of the chunks to avoid concurrent modification
      final chunksToUpload = List<Map<String, dynamic>>.from(_offlineChunks);
      
      // Sort chunks by sequence to ensure proper order
      chunksToUpload.sort((a, b) => (a['sequence'] ?? 0).compareTo(b['sequence'] ?? 0));
      
      // Show upload start notification
      _onUploadStart?.call(chunksToUpload.length);
      
      // Create a temporary WebSocket connection for uploading
      final channel = await _createUploadConnection();
      
      for (int i = 0; i < chunksToUpload.length; i++) {
        final chunk = chunksToUpload[i];
        try {
          print('📤 Uploading offline chunk ${i + 1}/${chunksToUpload.length} for session ${chunk['session_id']} (sequence: ${chunk['sequence']})');
          
          // Send chunk with proper sequencing
          channel.sink.add(jsonEncode({
            'type': 'audio_chunk',
            'session_id': chunk['session_id'],
            'chunk_data': chunk['chunk_data'],
            'chunk_size': chunk['chunk_size'],
            'timestamp': chunk['timestamp'],
            'sequence': chunk['sequence'], // Include sequence for proper ordering
          }));
          
          // Longer delay to prevent congestion and ensure proper sequencing
          // Progressive delay: first chunks get shorter delay, later chunks get longer delay
          final delayMs = 50 + (i * 5); // 50ms base + 5ms per chunk
          await Future.delayed(Duration(milliseconds: delayMs));
          
          // Log progress every 10 chunks
          if ((i + 1) % 10 == 0) {
            print('📊 Upload progress: ${i + 1}/${chunksToUpload.length} chunks sent');
          }
        } catch (chunkError) {
          print('❌ Error sending chunk ${i + 1}: $chunkError');
          // Continue with next chunk
        }
      }
      
      // Send session end message
      try {
        channel.sink.add(jsonEncode({
          'type': 'session_end',
          'session_id': _currentOfflineSessionId,
        }));
      } catch (endError) {
        print('❌ Error sending session end: $endError');
      }
      
      // Close connection
      try {
        await channel.sink.close();
      } catch (closeError) {
        print('❌ Error closing connection: $closeError');
      }
      
      // Store the number of chunks before clearing
      final chunksUploaded = chunksToUpload.length;
      
      // Clear offline data
      await _clearOfflineChunks();
      await stopOfflineRecording();
      
      print('✅ Successfully uploaded $chunksUploaded offline chunks');
      
      // Show success notification
      _onUploadSuccess?.call(chunksUploaded);
      
    } catch (e) {
      print('❌ Failed to upload offline chunks: $e');
      // Keep chunks for retry later
      
      // Show error notification
      _onUploadError?.call(e.toString());
    } finally {
      _isUploading = false;
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
          
          // Only upload if this is NOT the current active session
          if (!_isOfflineRecording) {
            // Try to upload immediately if online
            final connectivityResults = await _connectivity.checkConnectivity();
            final isOnline = connectivityResults.any((result) => 
              result == ConnectivityResult.wifi || 
              result == ConnectivityResult.mobile ||
              result == ConnectivityResult.ethernet
            );
            
            if (isOnline) {
              await _uploadOfflineChunksWithHealthCheck();
            }
          } else {
            print('📱 Skipping upload - current session is still active');
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
