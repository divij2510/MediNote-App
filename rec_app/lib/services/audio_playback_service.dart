import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/session.dart';
import 'api_service.dart';

class AudioPlaybackService extends ChangeNotifier {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final ApiService _apiService;
  
  // Playback state
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  String? _currentSessionId;
  
  // Error handling
  String? _errorMessage;
  
  // Streams
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  
  AudioPlaybackService(this._apiService) {
    _initializePlayer();
  }
  
  void _initializePlayer() {
    // Listen to position changes
    _positionSubscription = _audioPlayer.positionStream.listen((position) {
      _position = position;
      notifyListeners();
    });
    
    // Listen to duration changes
    _durationSubscription = _audioPlayer.durationStream.listen((duration) {
      if (duration != null) {
        _duration = duration;
        notifyListeners();
      }
    });
    
    // Listen to player state changes
    _playerStateSubscription = _audioPlayer.playerStateStream.listen((state) {
      _isPlaying = state.playing;
      _isLoading = state.processingState == ProcessingState.loading ||
                  state.processingState == ProcessingState.buffering;
      notifyListeners();
    });
  }
  
  // Getters
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  Duration get duration => _duration;
  Duration get position => _position;
  String? get currentSessionId => _currentSessionId;
  String? get errorMessage => _errorMessage;
  
  // Load session audio for playback
  Future<bool> loadSessionAudio(RecordingSession session) async {
    try {
      _currentSessionId = session.id;
      _errorMessage = null;
      _isLoading = true;
      notifyListeners();
      
      debugPrint('Loading audio for session: ${session.id}');
      
      // Get audio stream URL from backend
      final streamUrl = await _apiService.getAudioStreamUrl(session.id);
      if (streamUrl == null) {
        throw Exception('Failed to get audio stream URL');
      }
      
      debugPrint('Audio stream URL: $streamUrl');
      
      // Load audio source
      await _audioPlayer.setUrl(streamUrl);
      
      // For now, we're using the stream URL directly
      // In production, you might want to implement chunk merging
      
      _isLoading = false;
      notifyListeners();
      
      debugPrint('Audio loaded successfully');
      return true;
      
    } catch (e) {
      debugPrint('Error loading session audio: $e');
      _errorMessage = 'Failed to load audio: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  // Play audio
  Future<void> play() async {
    try {
      if (_audioPlayer.processingState == ProcessingState.ready ||
          _audioPlayer.processingState == ProcessingState.completed) {
        await _audioPlayer.play();
        debugPrint('Audio playback started');
      }
    } catch (e) {
      debugPrint('Error playing audio: $e');
      _errorMessage = 'Failed to play audio: $e';
      notifyListeners();
    }
  }
  
  // Pause audio
  Future<void> pause() async {
    try {
      await _audioPlayer.pause();
      debugPrint('Audio playback paused');
    } catch (e) {
      debugPrint('Error pausing audio: $e');
      _errorMessage = 'Failed to pause audio: $e';
      notifyListeners();
    }
  }
  
  // Stop audio
  Future<void> stop() async {
    try {
      await _audioPlayer.stop();
      _position = Duration.zero;
      debugPrint('Audio playback stopped');
    } catch (e) {
      debugPrint('Error stopping audio: $e');
      _errorMessage = 'Failed to stop audio: $e';
      notifyListeners();
    }
  }
  
  // Seek to position
  Future<void> seekTo(Duration position) async {
    try {
      await _audioPlayer.seek(position);
      debugPrint('Seeked to: $position');
    } catch (e) {
      debugPrint('Error seeking audio: $e');
      _errorMessage = 'Failed to seek audio: $e';
      notifyListeners();
    }
  }
  
  // Set playback speed
  Future<void> setSpeed(double speed) async {
    try {
      await _audioPlayer.setSpeed(speed);
      debugPrint('Playback speed set to: $speed');
    } catch (e) {
      debugPrint('Error setting playback speed: $e');
      _errorMessage = 'Failed to set playback speed: $e';
      notifyListeners();
    }
  }
  
  // Get formatted time string
  String formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  
  // Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
  
  @override
  void dispose() {
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }
}
