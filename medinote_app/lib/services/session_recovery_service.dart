import 'dart:async';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:phone_state/phone_state.dart';
import 'audio_streaming_service.dart';
import 'api_service.dart';

class SessionRecoveryService {
  static final SessionRecoveryService _instance = SessionRecoveryService._internal();
  factory SessionRecoveryService() => _instance;
  SessionRecoveryService._internal();

  StreamSubscription? _callStateSubscription;
  StreamSubscription? _connectivitySubscription;
  
  String? _currentSessionId;
  bool _wasInterrupted = false;
  Timer? _reconnectTimer;

  Future<void> initialize() async {
    print('🔄 Initializing SessionRecoveryService');
    
    // Listen for call state changes
    _callStateSubscription = PhoneState.stream.listen(_handleCallStateChange);
    
    // Listen for connectivity changes
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(_handleConnectivityChange);
    
    // Check for incomplete sessions on startup
    await _checkForIncompleteSessions();
  }

  void _handleCallStateChange(PhoneState? phoneState) {
    if (phoneState == null) return;
    
    print('📞 Call state changed: ${phoneState.status}');
    
    if (phoneState.status == PhoneStateStatus.CALL_INCOMING || 
        phoneState.status == PhoneStateStatus.CALL_STARTED) {
      _handleCallInterruption();
    } else if (phoneState.status == PhoneStateStatus.NOTHING && _wasInterrupted) {
      _handleCallEnded();
    }
  }

  Future<void> _handleCallInterruption() async {
    final streamingService = AudioStreamingService();
    if (streamingService.isStreaming) {
      print('📞 Call interruption detected - pausing recording');
      _wasInterrupted = true;
      _currentSessionId = streamingService.sessionId;
      
      // Pause the recording
      await streamingService.pauseStreaming();
      
      // Save the current state
      await _saveInterruptedSession();
    }
  }

  Future<void> _handleCallEnded() async {
    if (_wasInterrupted && _currentSessionId != null) {
      print('📞 Call ended - offering to resume recording');
      _wasInterrupted = false;
      
      // Show dialog to resume recording
      // This will be handled by the UI
    }
  }

  Future<void> _handleConnectivityChange(List<ConnectivityResult> results) async {
    final result = results.isNotEmpty ? results.first : ConnectivityResult.none;
    
    if (result == ConnectivityResult.none) {
      print('📶 Connectivity lost - pausing streaming');
      if (AudioStreamingService().isStreaming) {
        await AudioStreamingService().pauseStreaming();
      }
    } else {
      print('📶 Connectivity restored - attempting to resume');
      await _attemptResume();
    }
  }

  Future<void> _saveInterruptedSession() async {
    if (_currentSessionId != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('interrupted_session_id', _currentSessionId!);
      await prefs.setBool('has_interrupted_session', true);
      print('💾 Saved interrupted session: $_currentSessionId');
    }
  }

  Future<void> _checkForIncompleteSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final hasInterrupted = prefs.getBool('has_interrupted_session') ?? false;
    
    if (hasInterrupted) {
      final sessionId = prefs.getString('interrupted_session_id');
      print('🔄 Found interrupted session: $sessionId');
      
      // Clear the interrupted session flag
      await prefs.remove('has_interrupted_session');
      await prefs.remove('interrupted_session_id');
    }
  }

  Future<void> _attemptResume() async {
    if (_currentSessionId != null && !AudioStreamingService().isStreaming) {
      print('🔄 Attempting to resume session: $_currentSessionId');
      
      // Try to resume the session
      try {
        await AudioStreamingService().resumeStreaming();
        print('✅ Successfully resumed session: $_currentSessionId');
      } catch (e) {
        print('❌ Failed to resume session: $e');
        // Mark session as incomplete in backend
        await _markSessionAsIncomplete(_currentSessionId!);
      }
    }
  }

  Future<void> _markSessionAsIncomplete(String sessionId) async {
    try {
      // This will be handled by the backend when the WebSocket disconnects
      print('📝 Marking session as incomplete: $sessionId');
    } catch (e) {
      print('❌ Failed to mark session as incomplete: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getIncompleteSessions(int patientId) async {
    try {
      final response = await ApiService.getIncompleteSessions(patientId);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Failed to get incomplete sessions: $e');
      return [];
    }
  }

  Future<bool> resumeSession(String sessionId) async {
    try {
      final response = await ApiService.resumeSession(sessionId);
      if (response['status'] == 'ready') {
        print('✅ Session ready for resumption: $sessionId');
        return true;
      }
      return false;
    } catch (e) {
      print('❌ Failed to resume session: $e');
      return false;
    }
  }

  Future<void> markSessionAsComplete(String sessionId) async {
    try {
      // This will be handled when the session ends normally
      print('✅ Marking session as complete: $sessionId');
    } catch (e) {
      print('❌ Failed to mark session as complete: $e');
    }
  }

  void dispose() {
    _callStateSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _reconnectTimer?.cancel();
  }
}
