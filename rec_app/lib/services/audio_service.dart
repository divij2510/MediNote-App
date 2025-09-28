import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../models/audio_chunk.dart';
import '../models/session.dart';
import 'api_service.dart';
import 'storage_service.dart';

enum RecordingState { idle, recording, paused, stopped, error }

class AudioService extends ChangeNotifier {
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _mounted = true;
  
  RecordingState _recordingState = RecordingState.idle;
  RecordingSession? _currentSession;
  final List<AudioChunk> _pendingChunks = [];
  Timer? _chunkTimer;
  int _currentChunkNumber = 0;
  final int _chunkDurationMs = 5000; // 5 seconds per chunk
  bool _isProcessingChunks = false;
  String? _currentRecordingPath;
  bool _isRecording = false;

  // Audio metrics
  double _currentAmplitude = 0.0;
  double _gainLevel = 1.0; // Gain control (0.1 to 3.0)
  Duration _recordingDuration = Duration.zero;
  Timer? _durationTimer;
  Timer? _amplitudeTimer;

  // Services
  late ApiService _apiService;
  late StorageService _storageService;

  // Playback state
  bool _isPlaying = false;
  Duration _playbackPosition = Duration.zero;
  Duration _playbackDuration = Duration.zero;
  List<String> _playbackUrls = [];
  int _currentChunkIndex = 0;
  bool _isLoadingPlayback = false;

  RecordingState get recordingState => _recordingState;
  RecordingSession? get currentSession => _currentSession;
  List<AudioChunk> get pendingChunks => List.unmodifiable(_pendingChunks);
  double get currentAmplitude => _currentAmplitude;
  bool get isLoadingPlayback => _isLoadingPlayback;
  double get gainLevel => _gainLevel;
  Duration get recordingDuration => _recordingDuration;
  bool get isRecording => _recordingState == RecordingState.recording;
  bool get isPaused => _recordingState == RecordingState.paused;
  int get recordedChunks => _currentChunkNumber;
  
  // Playback getters
  bool get isPlaying => _isPlaying;
  Duration get playbackPosition => _playbackPosition;
  List<String> get playbackUrls => List.unmodifiable(_playbackUrls);
  Duration get playbackDuration => _playbackDuration;
  int get currentChunkIndex => _currentChunkIndex;
  int get totalPlaybackChunks => _playbackUrls.length;

  void initialize(ApiService apiService, StorageService storageService) {
    _apiService = apiService;
    _storageService = storageService;
    _initializeForegroundService();
    _setupAudioPlayer();
    
    // Listen for connectivity changes to sync offline chunks
    _apiService.addListener(_onApiServiceChanged);
  }
  
  void _onApiServiceChanged() {
    // Sync offline chunks when back online
    if (_apiService.isConnected) {
      syncOfflineChunks();
    }
  }

  void _setupAudioPlayer() {
    _audioPlayer.playerStateStream.listen((state) {
      _isPlaying = state.playing;
      notifyListeners();
    });

    _audioPlayer.positionStream.listen((position) {
      _playbackPosition = position;
      notifyListeners();
    });

    _audioPlayer.durationStream.listen((duration) {
      _playbackDuration = duration ?? Duration.zero;
      notifyListeners();
    });
  }

  void _initializeForegroundService() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'rec_app_recording',
        channelName: 'Medical Recording',
        channelDescription: 'Recording medical consultations',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<bool> _requestPermissions() async {
    // Request microphone permission
    final micStatus = await Permission.microphone.request();
    if (micStatus != PermissionStatus.granted) {
      debugPrint('Microphone permission denied');
      return false;
    }

    // Request notification permission for background recording
    final notificationStatus = await Permission.notification.request();
    if (notificationStatus != PermissionStatus.granted) {
      debugPrint('Notification permission denied');
    }

    // For Android 11+ (API 30+), we don't need storage permission for app-specific directories
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt <= 29) {
        final storageStatus = await Permission.storage.request();
        if (storageStatus != PermissionStatus.granted) {
          debugPrint('Storage permission denied');
          return false;
        }
      }
    }

    return true;
  }

  Future<bool> startRecording(RecordingSession session) async {
    if (_recordingState != RecordingState.idle) {
      debugPrint('Cannot start recording: already in state $_recordingState');
      return false;
    }
    
    if (_currentSession != null) {
      debugPrint('Cannot start recording: session already exists');
      return false;
    }

    try {
      // Request permissions first
      final hasPermissions = await _requestPermissions();
      if (!hasPermissions) {
        _recordingState = RecordingState.error;
        notifyListeners();
        return false;
      }

      // Check if recorder is available
      if (!await _audioRecorder.hasPermission()) {
        debugPrint('Audio recorder permission not granted');
        _recordingState = RecordingState.error;
        notifyListeners();
        return false;
      }

      _currentSession = session;
      _recordingState = RecordingState.recording;
      _currentChunkNumber = 0;
      _recordingDuration = Duration.zero;
      _pendingChunks.clear();

      // Start foreground service
      await _startForegroundService();

      // Create unique file path
      final directory = await getApplicationDocumentsDirectory();
      _currentRecordingPath = '${directory.path}/recording_${session.id}_${DateTime.now().millisecondsSinceEpoch}.m4a';

      // Start recording
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 44100,
          bitRate: 128000,
        ),
        path: _currentRecordingPath!,
      );

      _isRecording = true;
      debugPrint('Recording started at: $_currentRecordingPath');

      // Start timers
      _startDurationTimer();
      _startAmplitudeMonitoring();
      _startChunkProcessingTimer();

      notifyListeners();
      debugPrint('Recording started successfully');
      return true;
    } catch (e) {
      debugPrint('Error starting recording: $e');
      _recordingState = RecordingState.error;
      notifyListeners();
      return false;
    }
  }

  Future<void> pauseRecording() async {
    if (_recordingState != RecordingState.recording) return;

    try {
      await _audioRecorder.pause();
      _recordingState = RecordingState.paused;
      _chunkTimer?.cancel();
      _durationTimer?.cancel();
      _amplitudeTimer?.cancel();
      notifyListeners();
      debugPrint('Recording paused');
    } catch (e) {
      debugPrint('Error pausing recording: $e');
    }
  }

  Future<void> resumeRecording() async {
    if (_recordingState != RecordingState.paused) return;

    try {
      await _audioRecorder.resume();
      _recordingState = RecordingState.recording;
      _startDurationTimer();
      _startAmplitudeMonitoring();
      _startChunkProcessingTimer();
      notifyListeners();
      debugPrint('Recording resumed');
    } catch (e) {
      debugPrint('Error resuming recording: $e');
    }
  }

  Future<void> stopRecording() async {
    if (_recordingState == RecordingState.idle) return;

    try {
      // Stop recording and get final file
      final path = await _audioRecorder.stop();
      _isRecording = false;

      // Process final chunk
      if (path != null && File(path).existsSync()) {
        await _processFinalChunk(path);
      }

      // Clean up timers
      _chunkTimer?.cancel();
      _durationTimer?.cancel();
      _amplitudeTimer?.cancel();

      // Stop foreground service
      await FlutterForegroundTask.stopService();

      // Update session status
      if (_currentSession != null) {
        final sessionId = _currentSession!.id;
        debugPrint('Updating session status to completed: $sessionId');
        debugPrint('Total chunks: $_currentChunkNumber, Duration: ${_recordingDuration.inSeconds}s');
        
        try {
          final success = await _apiService.updateSessionStatus(
              sessionId,
              'completed',
              _currentChunkNumber,
              _recordingDuration.inSeconds
          );
          debugPrint('Session status update result: $success');
        } catch (e) {
          debugPrint('Error updating session status: $e');
        }
      } else {
        debugPrint('Warning: _currentSession is null, cannot update session status');
      }

      _recordingState = RecordingState.stopped;
      notifyListeners();
      debugPrint('Recording stopped successfully');
    } catch (e) {
      debugPrint('Error stopping recording: $e');
      _recordingState = RecordingState.error;
      notifyListeners();
    }
  }

  void _startChunkProcessingTimer() {
    _chunkTimer = Timer.periodic(Duration(milliseconds: _chunkDurationMs), (timer) {
      if (_recordingState == RecordingState.recording) {
        _processCurrentChunk();
      }
    });
  }

  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_recordingState == RecordingState.recording) {
        _recordingDuration += const Duration(seconds: 1);
        notifyListeners();
      }
    });
  }

  void _startAmplitudeMonitoring() {
    _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      if (_recordingState == RecordingState.recording && _isRecording) {
        try {
          final amplitude = await _audioRecorder.getAmplitude();
          // Convert dB to percentage (0-100) for display
          // -60 dB = 0%, 0 dB = 100%
          final rawAmplitude = amplitude.current;
          final adjustedAmplitude = rawAmplitude + (20 * (1 - _gainLevel));
          _currentAmplitude = ((adjustedAmplitude + 60) / 60 * 100).clamp(0.0, 100.0);
          
          // Ensure we have some variation for visualization
          if (_currentAmplitude < 5.0) {
            _currentAmplitude = 5.0 + (rawAmplitude.abs() % 10); // Add some base level
          }
          
          debugPrint('Raw: ${rawAmplitude.toStringAsFixed(1)} dB, Adjusted: ${adjustedAmplitude.toStringAsFixed(1)} dB, Display: ${_currentAmplitude.toStringAsFixed(1)}%');
          if (_mounted) {
            notifyListeners();
          }
        } catch (e) {
          _currentAmplitude = 5.0; // Show some base level instead of 0
          debugPrint('Amplitude error: $e');
        }
      } else {
        _currentAmplitude = 0.0;
        timer.cancel();
      }
    });
  }

  Future<void> _startForegroundService() async {
    final result = await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'Recording Medical Consultation',
      notificationText: 'Recording in progress - Tap to return',
      callback: startCallback,
    );

    debugPrint('Foreground service start result: $result');
  }

  Future<void> _processCurrentChunk() async {
    if (_isProcessingChunks || _currentSession == null || _currentRecordingPath == null) return;
    _isProcessingChunks = true;

    try {
      _currentChunkNumber++;

      // Create a temporary file for this chunk
      final directory = await getApplicationDocumentsDirectory();
      final tempChunkPath = '${directory.path}/temp_chunk_${_currentChunkNumber}_${DateTime.now().millisecondsSinceEpoch}.m4a';
      
      // Stop current recording and copy the data
      await _audioRecorder.stop();
      
      // Copy the current recording to a temporary chunk file
      final currentFile = File(_currentRecordingPath!);
      if (currentFile.existsSync()) {
        final fileBytes = await currentFile.readAsBytes();
        
        if (fileBytes.isNotEmpty) {
          // Write chunk data to temporary file
          final tempFile = File(tempChunkPath);
          await tempFile.writeAsBytes(fileBytes);
          
          // Create chunk with the temporary file data
          final chunk = AudioChunk(
            sessionId: _currentSession!.id,
            chunkNumber: _currentChunkNumber,
            data: fileBytes,
            mimeType: 'audio/mp4',
            timestamp: DateTime.now(),
          );

          _pendingChunks.add(chunk);
          await _uploadChunk(chunk, false); // Not the last chunk

          // Clean up temporary file
          if (tempFile.existsSync()) {
            await tempFile.delete();
          }
        }
      }

      // Start recording again with a new file
      if (_currentSession != null) {
        _currentRecordingPath = '${directory.path}/recording_${_currentSession!.id}_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            sampleRate: 44100,
            bitRate: 128000,
          ),
          path: _currentRecordingPath!,
        );
      } else {
        debugPrint('Warning: _currentSession is null, cannot restart recording');
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error processing chunk: $e');
    } finally {
      _isProcessingChunks = false;
    }
  }

  Future<void> _processFinalChunk(String filePath) async {
    try {
      if (_currentSession == null) {
        debugPrint('Cannot process final chunk: no current session');
        return;
      }

      final file = File(filePath);
      if (file.existsSync()) {
        final fileBytes = await file.readAsBytes();
        _currentChunkNumber++;

        final chunk = AudioChunk(
          sessionId: _currentSession!.id,
          chunkNumber: _currentChunkNumber,
          data: fileBytes,
          mimeType: 'audio/mp4',
          timestamp: DateTime.now(),
        );

        _pendingChunks.add(chunk);
        await _uploadChunk(chunk, true); // This is the last chunk

        // Clean up file only if it exists
        try {
          if (file.existsSync()) {
            await file.delete();
          }
        } catch (deleteError) {
          debugPrint('Warning: Could not delete file $filePath: $deleteError');
        }
      }
    } catch (e) {
      debugPrint('Error processing final chunk: $e');
    }
  }

  Future<void> _uploadChunk(AudioChunk chunk, bool isLast) async {
    if (_currentSession == null) {
      debugPrint('Cannot upload chunk: _currentSession is null');
      return;
    }

    try {
      chunk.status = ChunkStatus.uploading;
      notifyListeners();

      // Check if we're online
      if (!_apiService.isConnected) {
        debugPrint('Offline: storing chunk locally');
        chunk.status = ChunkStatus.failed;
        await _storageService.storeFailedChunk(chunk);
        notifyListeners();
        return;
      }

      final success = await _apiService.uploadAudioChunk(chunk, isLast);

      if (success) {
        chunk.status = ChunkStatus.uploaded;
        _pendingChunks.remove(chunk);
        debugPrint('Chunk ${chunk.chunkNumber} uploaded successfully');
      } else {
        chunk.status = ChunkStatus.failed;
        chunk.retryCount++;
        await _storageService.storeFailedChunk(chunk);
        debugPrint('Chunk ${chunk.chunkNumber} upload failed - stored locally');
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error uploading chunk: $e');
      chunk.status = ChunkStatus.failed;
      chunk.error = e.toString();
      chunk.retryCount++;
      await _storageService.storeFailedChunk(chunk);
      notifyListeners();
    }
  }

  Future<void> retryFailedChunks() async {
    final failedChunks = _pendingChunks.where((c) => c.shouldRetry).toList();
    for (final chunk in failedChunks) {
      chunk.status = ChunkStatus.retrying;
      await _uploadChunk(chunk, false);
    }
  }

  Future<void> syncOfflineChunks() async {
    if (!_apiService.isConnected) return;

    final offlineChunks = _storageService.failedChunks;
    debugPrint('Syncing ${offlineChunks.length} offline chunks');

    for (final chunk in offlineChunks) {
      try {
        chunk.status = ChunkStatus.retrying;
        final success = await _apiService.uploadAudioChunk(chunk, false);
        
        if (success) {
          await _storageService.removeFailedChunk(chunk);
          debugPrint('Offline chunk ${chunk.chunkNumber} synced successfully');
        } else {
          chunk.status = ChunkStatus.failed;
          chunk.retryCount++;
        }
      } catch (e) {
        debugPrint('Error syncing offline chunk: $e');
        chunk.status = ChunkStatus.failed;
        chunk.error = e.toString();
        chunk.retryCount++;
      }
    }
    
    notifyListeners();
  }

  // Playback methods
  Future<void> loadSessionForPlayback(String sessionId) async {
    try {
      // Get session audio URLs from backend
      final audioData = await _apiService.getSessionAudio(sessionId);
      debugPrint('Audio data from backend: $audioData');
      if (audioData != null) {
        final chunks = audioData['chunks'] as List<dynamic>? ?? [];
        debugPrint('Found ${chunks.length} chunks in backend response');
        _playbackUrls = chunks.map((chunk) {
          final chunkMap = chunk as Map<String, dynamic>;
          final storageUrl = chunkMap['storage_url'] as String?;
          final publicUrl = chunkMap['public_url'] as String?;
          final url = storageUrl ?? publicUrl ?? '';
          debugPrint('Chunk URL: $url');
          return url;
        }).where((url) => url.isNotEmpty).toList();
        debugPrint('Loaded ${_playbackUrls.length} audio chunks for playback');
      }
    } catch (e) {
      debugPrint('Error loading session for playback: $e');
    }
  }

  Future<void> playSession() async {
    if (_playbackUrls.isEmpty) {
      debugPrint('No audio URLs available for playback');
      return;
    }

    try {
      // Stop any current playback first
      await stopPlayback();
      
      _isLoadingPlayback = true;
      notifyListeners();
      
      debugPrint('Starting sequential playback of ${_playbackUrls.length} chunks');
      await _playAllChunksSequentially();
    } catch (e) {
      debugPrint('Error playing session: $e');
    } finally {
      _isLoadingPlayback = false;
      notifyListeners();
    }
  }

  Future<File?> _createMergedAudioFile() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final mergedFilePath = '${directory.path}/merged_session_${DateTime.now().millisecondsSinceEpoch}.m4a';
      
      if (_playbackUrls.isEmpty) {
        debugPrint('No playback URLs available for merging');
        return null;
      }

      debugPrint('Downloading ${_playbackUrls.length} audio chunks for sequential playback...');
      
      // Download all chunks to local files
      final List<String> localChunkPaths = [];
      
      for (int i = 0; i < _playbackUrls.length; i++) {
        final url = _playbackUrls[i];
        final chunkPath = '${directory.path}/chunk_${i + 1}_${DateTime.now().millisecondsSinceEpoch}.m4a';
        
        debugPrint('Downloading chunk ${i + 1}/${_playbackUrls.length}: $url');
        
        try {
          final response = await http.get(Uri.parse(url));
          if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
            final chunkFile = File(chunkPath);
            await chunkFile.writeAsBytes(response.bodyBytes);
            localChunkPaths.add(chunkPath);
            debugPrint('Chunk ${i + 1}: ${response.bodyBytes.length} bytes saved to $chunkPath');
          } else {
            debugPrint('Failed to download chunk ${i + 1}: ${response.statusCode}');
          }
        } catch (e) {
          debugPrint('Error downloading chunk ${i + 1}: $e');
        }
      }
      
      if (localChunkPaths.isEmpty) {
        debugPrint('No valid chunks downloaded');
        return null;
      }
      
      // For now, return the first chunk as a simple solution
      // In a real implementation, you'd use FFmpeg to properly merge the chunks
      final firstChunkPath = localChunkPaths.first;
      final firstChunkFile = File(firstChunkPath);
      
      if (firstChunkFile.existsSync()) {
        // Copy first chunk to merged file location
        final mergedFile = File(mergedFilePath);
        await firstChunkFile.copy(mergedFilePath);
        
        // Clean up temporary chunk files
        for (final chunkPath in localChunkPaths) {
          try {
            await File(chunkPath).delete();
          } catch (e) {
            debugPrint('Error cleaning up chunk file $chunkPath: $e');
          }
        }
        
        debugPrint('Created merged file with ${localChunkPaths.length} chunks (using first chunk as placeholder)');
        return mergedFile;
      }
      
      return null;
    } catch (e) {
      debugPrint('Error creating merged audio file: $e');
      return null;
    }
  }

  Future<void> _playAllChunksSequentially() async {
    for (int i = 0; i < _playbackUrls.length; i++) {
      _currentChunkIndex = i;
      final url = _playbackUrls[i];
      debugPrint('Playing chunk ${i + 1}/${_playbackUrls.length}: $url');
      
      try {
        await _audioPlayer.setUrl(url);
        await _audioPlayer.play();
        _isPlaying = true;
        notifyListeners();
        
        // Wait for this chunk to finish playing
        await _waitForChunkToFinish();
        
        debugPrint('Finished playing chunk ${i + 1}');
      } catch (e) {
        debugPrint('Error playing chunk ${i + 1}: $e');
        // Continue with next chunk even if one fails
      }
    }
    
    debugPrint('Finished playing all chunks');
    _isPlaying = false;
    _currentChunkIndex = 0;
    notifyListeners();
  }

  Future<void> _waitForChunkToFinish() async {
    // Wait for the current chunk to finish playing
    while (_audioPlayer.playerState.playing) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> stopPlayback() async {
    try {
      await _audioPlayer.stop();
      _isPlaying = false;
      _currentChunkIndex = 0;
      _playbackPosition = Duration.zero;
      notifyListeners();
      debugPrint('Playback stopped');
    } catch (e) {
      debugPrint('Error stopping playback: $e');
    }
  }

  Future<void> pausePlayback() async {
    try {
      await _audioPlayer.pause();
      _isPlaying = false;
      notifyListeners();
    } catch (e) {
      debugPrint('Error pausing playback: $e');
    }
  }


  Future<void> seekTo(Duration position) async {
    try {
      await _audioPlayer.seek(position);
    } catch (e) {
      debugPrint('Error seeking: $e');
    }
  }

  // Gain control methods
  void setGainLevel(double gain) {
    _gainLevel = gain.clamp(0.1, 3.0);
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

  // Reset recording state for new recording
  void resetRecordingState() {
    _recordingState = RecordingState.idle;
    _currentSession = null;
    _currentChunkNumber = 0;
    _recordingDuration = Duration.zero;
    _pendingChunks.clear();
    _currentRecordingPath = null;
    _isRecording = false;
    _currentAmplitude = 0.0;
    notifyListeners();
  }

  @override
  void dispose() {
    _mounted = false;
    _chunkTimer?.cancel();
    _durationTimer?.cancel();
    _amplitudeTimer?.cancel();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    FlutterForegroundTask.stopService();
    _apiService.removeListener(_onApiServiceChanged);
    super.dispose();
  }

  // Method to stop playback when screen is closed
  Future<void> stopAllPlayback() async {
    await stopPlayback();
  }
}

// Top-level callback function for foreground task
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(RecordingTaskHandler());
}

class RecordingTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('Recording foreground service started by: ${starter.name}');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    FlutterForegroundTask.updateService(
      notificationTitle: 'Recording Medical Consultation',
      notificationText: 'Recording active - ${timestamp.toLocal().toString().split(' ')[1].substring(0, 8)}',
    );

    debugPrint('Recording service heartbeat: ${timestamp.toIso8601String()}');
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint('Recording foreground service destroyed.');
  }

  @override
  void onNotificationButtonPressed(String id) {
    debugPrint('Notification button pressed: $id');
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/recording');
    debugPrint('Notification pressed - launching app');
  }

  @override
  void onNotificationDismissed() {
    debugPrint('Recording notification dismissed');
  }

  @override
  void onReceiveData(Object data) {
    debugPrint('Received data in task handler: $data');
  }
}