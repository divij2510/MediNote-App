import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AudioQueueService {
  static const String _queueKey = 'audio_queue';
  static const String _sessionKey = 'current_session_id';
  
  // In-memory queue for active session
  final List<Map<String, dynamic>> _activeQueue = [];
  String? _currentSessionId;
  
  // Persistent storage for queue data
  SharedPreferences? _prefs;
  
  static final AudioQueueService _instance = AudioQueueService._internal();
  factory AudioQueueService() => _instance;
  AudioQueueService._internal();
  
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadActiveSession();
  }
  
  /// Add audio chunk to queue
  Future<void> enqueueChunk({
    required String sessionId,
    required List<int> audioData,
    required double amplitude,
    required DateTime timestamp,
  }) async {
    final chunk = {
      'session_id': sessionId,
      'audio_data': base64Encode(audioData),
      'amplitude': amplitude,
      'timestamp': timestamp.toIso8601String(),
      'chunk_id': DateTime.now().millisecondsSinceEpoch.toString(),
    };
    
    _activeQueue.add(chunk);
    
    // If this is a new session, save session ID
    if (_currentSessionId != sessionId) {
      _currentSessionId = sessionId;
      await _saveActiveSession();
    }
    
    // Save queue to persistent storage
    await _saveQueue();
    
    print('📦 Queued audio chunk for session $sessionId (Queue size: ${_activeQueue.length})');
  }
  
  /// Get next chunk from queue
  Map<String, dynamic>? dequeueChunk() {
    if (_activeQueue.isEmpty) return null;
    
    final chunk = _activeQueue.removeAt(0);
    _saveQueue(); // Update persistent storage
    
    print('📤 Dequeued audio chunk for session ${chunk['session_id']} (Queue size: ${_activeQueue.length})');
    return chunk;
  }
  
  /// Get all chunks for a specific session
  List<Map<String, dynamic>> getSessionChunks(String sessionId) {
    return _activeQueue.where((chunk) => chunk['session_id'] == sessionId).toList();
  }
  
  /// Check if queue has chunks for current session
  bool hasChunksForSession(String sessionId) {
    return _activeQueue.any((chunk) => chunk['session_id'] == sessionId);
  }
  
  /// Get queue size
  int get queueSize => _activeQueue.length;
  
  /// Check if queue is empty
  bool get isEmpty => _activeQueue.isEmpty;
  
  /// Clear queue for specific session
  Future<void> clearSessionQueue(String sessionId) async {
    _activeQueue.removeWhere((chunk) => chunk['session_id'] == sessionId);
    await _saveQueue();
    print('🗑️ Cleared queue for session $sessionId');
  }
  
  /// Clear all queues
  Future<void> clearAllQueues() async {
    _activeQueue.clear();
    _currentSessionId = null;
    await _saveQueue();
    await _clearActiveSession();
    print('🗑️ Cleared all audio queues');
  }
  
  /// Save queue to persistent storage
  Future<void> _saveQueue() async {
    if (_prefs == null) return;
    
    final queueJson = jsonEncode(_activeQueue);
    await _prefs!.setString(_queueKey, queueJson);
  }
  
  /// Load queue from persistent storage
  Future<void> _loadQueue() async {
    if (_prefs == null) return;
    
    final queueJson = _prefs!.getString(_queueKey);
    if (queueJson != null) {
      try {
        final List<dynamic> queueData = jsonDecode(queueJson);
        _activeQueue.clear();
        _activeQueue.addAll(queueData.map((item) => Map<String, dynamic>.from(item)));
        print('📥 Loaded ${_activeQueue.length} chunks from persistent queue');
      } catch (e) {
        print('❌ Error loading queue: $e');
        _activeQueue.clear();
      }
    }
  }
  
  /// Save active session ID
  Future<void> _saveActiveSession() async {
    if (_prefs == null || _currentSessionId == null) return;
    await _prefs!.setString(_sessionKey, _currentSessionId!);
  }
  
  /// Load active session ID
  Future<void> _loadActiveSession() async {
    if (_prefs == null) return;
    
    _currentSessionId = _prefs!.getString(_sessionKey);
    if (_currentSessionId != null) {
      await _loadQueue();
      print('📱 Loaded active session: $_currentSessionId with ${_activeQueue.length} chunks');
    }
  }
  
  /// Clear active session
  Future<void> _clearActiveSession() async {
    if (_prefs == null) return;
    await _prefs!.remove(_sessionKey);
  }
  
  /// Get current session ID
  String? get currentSessionId => _currentSessionId;
  
  /// Set current session ID
  Future<void> setCurrentSession(String sessionId) async {
    _currentSessionId = sessionId;
    await _saveActiveSession();
  }
  
  /// Get queue statistics
  Map<String, dynamic> getQueueStats() {
    return {
      'queue_size': _activeQueue.length,
      'current_session': _currentSessionId,
      'has_chunks': !isEmpty,
      'oldest_chunk': _activeQueue.isNotEmpty ? _activeQueue.first['timestamp'] : null,
      'newest_chunk': _activeQueue.isNotEmpty ? _activeQueue.last['timestamp'] : null,
    };
  }
}
