import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/audio_recording.dart';
import 'audio_streaming_service.dart';
import 'api_service.dart';
import 'audio_chunk_player.dart';

class AudioRecordingService with ChangeNotifier {
  static final AudioRecordingService _instance = AudioRecordingService._internal();
  factory AudioRecordingService() => _instance;
  AudioRecordingService._internal();

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  final AudioStreamingService _streamingService = AudioStreamingService();
  final AudioChunkPlayer _chunkPlayer = AudioChunkPlayer();
  
  bool _isRecording = false;
  bool _isPaused = false;
  bool _isPlaying = false;
  int? _currentlyPlayingId;
  int _recordingDuration = 0;
  Timer? _recordingTimer;
  List<AudioRecording> _recordings = [];
  // Amplitude monitoring removed - not available with sound_stream
  
  // Getters
  bool get isRecording => _isRecording;
  bool get isPaused => _isPaused;
  bool get isPlaying => _isPlaying;
  int? get currentlyPlayingId => _currentlyPlayingId;
  int get recordingDuration => _recordingDuration;
  List<AudioRecording> get recordings => _recordings;
  // Amplitude getters removed - not available with sound_stream
  
  // Streaming getters
  bool get isStreaming => _streamingService.isStreaming;
  bool get isStreamingConnected => _streamingService.isConnected;
  bool get isLoadingAudio => _chunkPlayer.isLoading;
  int get bytesStreamed => _streamingService.bytesStreamed;
  int get chunksStreamed => _streamingService.chunksStreamed;

  Future<void> initialize() async {
    await _requestPermissions();
    await _loadRecordings();
  }

  Future<void> _requestPermissions() async {
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      throw Exception('Microphone permission denied');
    }
  }

  Future<void> startRecording(int patientId) async {
    if (_isRecording) return;

    try {
      await _requestPermissions();
      
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'recording_${patientId}_$timestamp.mp3';
      final filePath = '${directory.path}/$fileName';
      
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 44100,
          bitRate: 128000,
          numChannels: 1,
        ),
        path: filePath,
      );

      _isRecording = true;
      _isPaused = false;
      _recordingDuration = 0;
      
      // Start audio streaming to backend
      // Amplitude callback removed - not available with sound_stream
      
      await _streamingService.startStreaming('session_${DateTime.now().millisecondsSinceEpoch}_$patientId');
      
      _startRecordingTimer();
      // Don't start amplitude monitoring here - let streaming service handle it
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to start recording: $e');
    }
  }

  Future<void> pauseRecording() async {
    if (!_isRecording || _isPaused) return;

    try {
      await _recorder.pause();
      _isPaused = true;
      _recordingTimer?.cancel();
      // Amplitude monitoring removed
      
      // Pause audio streaming
      await _streamingService.pauseStreaming();
      
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to pause recording: $e');
    }
  }

  Future<void> resumeRecording() async {
    if (!_isRecording || !_isPaused) return;

    try {
      await _recorder.resume();
      _isPaused = false;
      _startRecordingTimer();
      // Don't start amplitude monitoring here - let streaming service handle it
      
      // Resume audio streaming
      await _streamingService.resumeStreaming();
      
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to resume recording: $e');
    }
  }

  Future<AudioRecording> stopRecording(int patientId) async {
    if (!_isRecording) throw Exception('No recording in progress');

    try {
      final path = await _recorder.stop();
      _isRecording = false;
      _isPaused = false;
      _recordingTimer?.cancel();
      // Amplitude monitoring removed
      
      // Stop audio streaming
      await _streamingService.stopStreaming();
      
      final recording = AudioRecording(
        id: DateTime.now().millisecondsSinceEpoch,
        patientId: patientId,
        fileName: path?.split('/').last ?? 'recording.mp3',
        filePath: path ?? '',
        duration: _recordingDuration,
        createdAt: DateTime.now(),
      );

      _recordings.add(recording);
      await _saveRecordings();
      
      _recordingDuration = 0;
      notifyListeners();
      
      return recording;
    } catch (e) {
      throw Exception('Failed to stop recording: $e');
    }
  }

  Future<void> playRecording(AudioRecording recording) async {
    try {
      if (_isPlaying) {
        await _player.stop();
      }
      
      await _player.play(DeviceFileSource(recording.filePath));
      _isPlaying = true;
      _currentlyPlayingId = recording.id;
      notifyListeners();
      
      // Listen for completion
      _player.onPlayerComplete.listen((_) {
        _isPlaying = false;
        _currentlyPlayingId = null;
        notifyListeners();
      });
    } catch (e) {
      throw Exception('Failed to play recording: $e');
    }
  }

  Future<void> stopPlayback() async {
    try {
      await _player.stop();
      _isPlaying = false;
      _currentlyPlayingId = null;
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to stop playback: $e');
    }
  }

  Future<void> deleteRecording(AudioRecording recording) async {
    try {
      // Delete file from storage
      final file = File(recording.filePath);
      if (await file.exists()) {
        await file.delete();
      }
      
      // Remove from list
      _recordings.removeWhere((r) => r.id == recording.id);
      await _saveRecordings();
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to delete recording: $e');
    }
  }

  List<AudioRecording> getRecordingsForPatient(int patientId) {
    return _recordings.where((r) => r.patientId == patientId).toList();
  }

  void _startRecordingTimer() {
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _recordingDuration++;
      notifyListeners();
    });
  }

  // Amplitude monitoring methods removed - not available with sound_stream

  Future<void> _loadRecordings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recordingsJson = prefs.getStringList('audio_recordings') ?? [];
      _recordings = recordingsJson
          .map((json) => AudioRecording.fromJson(jsonDecode(json)))
          .toList();
      notifyListeners();
    } catch (e) {
      // Handle error silently
    }
  }

  Future<void> _saveRecordings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recordingsJson = _recordings
          .map((recording) => jsonEncode(recording.toJson()))
          .toList();
      await prefs.setStringList('audio_recordings', recordingsJson);
    } catch (e) {
      // Handle error silently
    }
  }

  String formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  // Backend audio session methods
  Future<List<Map<String, dynamic>>> getPatientAudioSessions(int patientId) async {
    try {
      return await ApiService.getPatientAudioSessions(patientId);
    } catch (e) {
      print('Error fetching audio sessions: $e');
      return [];
    }
  }

  Future<void> playAudioFromBackend(String sessionId) async {
    try {
      // Initialize chunk player if not already done
      await _chunkPlayer.initialize();
      
      // Play session chunks using the chunk player with completion callback
      await _chunkPlayer.playSessionChunks(sessionId, onComplete: () {
        _isPlaying = false;
        _currentlyPlayingId = null;
        notifyListeners();
        print('✅ Audio playback completed for session: $sessionId');
      });
      
      _isPlaying = true;
      _currentlyPlayingId = sessionId.hashCode; // Use sessionId hash as ID
      notifyListeners();
      
    } catch (e) {
      print('Error playing audio from backend: $e');
      _isPlaying = false;
      _currentlyPlayingId = null;
      notifyListeners();
      throw Exception('Failed to play audio: $e');
    }
  }

  Future<void> stopAudioFromBackend() async {
    try {
      await _chunkPlayer.stop();
      _isPlaying = false;
      _currentlyPlayingId = null;
      notifyListeners();
    } catch (e) {
      print('Error stopping audio: $e');
    }
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    // Amplitude subscription removed
    _player.dispose();
    super.dispose();
  }
}
