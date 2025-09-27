import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path_provider/path_provider.dart';

import '../models/audio_chunk.dart';
import '../models/session.dart';
import 'api_service.dart';
import 'storage_service.dart';

enum RecordingState { idle, recording, paused, stopped, error }

class AudioService extends ChangeNotifier {
  late RecorderController _recorderController;
  RecordingState _recordingState = RecordingState.idle;
  RecordingSession? _currentSession;
  final List<AudioChunk> _pendingChunks = [];
  Timer? _chunkTimer;
  int _currentChunkNumber = 0;
  final int _chunkDurationMs = 5000; // 5 seconds per chunk
  bool _isProcessingChunks = false;

  // Audio metrics
  double _currentAmplitude = 0.0;
  Duration _recordingDuration = Duration.zero;
  Timer? _durationTimer;

  // Services
  late ApiService _apiService;
  late StorageService _storageService;

  RecordingState get recordingState => _recordingState;
  RecordingSession? get currentSession => _currentSession;
  List<AudioChunk> get pendingChunks => List.unmodifiable(_pendingChunks);
  double get currentAmplitude => _currentAmplitude;
  Duration get recordingDuration => _recordingDuration;
  bool get isRecording => _recordingState == RecordingState.recording;
  bool get isPaused => _recordingState == RecordingState.paused;
  int get totalChunks => _currentChunkNumber;

  void initialize(ApiService apiService, StorageService storageService) {
    _apiService = apiService;
    _storageService = storageService;
    _initializeRecorderController();
    _initializeForegroundService();
  }

  void _initializeRecorderController() {
    _recorderController = RecorderController()
      ..androidEncoder = AndroidEncoder.aac
      ..androidOutputFormat = AndroidOutputFormat.mpeg4
      ..iosEncoder = IosEncoder.kAudioFormatMPEG4AAC
      ..sampleRate = 16000
      ..bitRate = 128000;
  }

  void _initializeForegroundService() {
    // Initialize foreground task
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

  Future<bool> startRecording(RecordingSession session) async {
    if (_recordingState != RecordingState.idle) {
      return false;
    }

    try {
      _currentSession = session;
      _recordingState = RecordingState.recording;
      _currentChunkNumber = 0;
      _recordingDuration = Duration.zero;
      _pendingChunks.clear();

      // Start foreground service
      await _startForegroundService();

      // Start recording
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/temp_recording_${session.id}.m4a';

      await _recorderController.record(path: filePath);

      // Start chunk processing timer
      _startChunkTimer();

      // Start duration timer
      _startDurationTimer();

      // Start amplitude monitoring
      _startAmplitudeMonitoring();

      notifyListeners();
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
      await _recorderController.pause();
      _recordingState = RecordingState.paused;
      _chunkTimer?.cancel();
      _durationTimer?.cancel();
      notifyListeners();
    } catch (e) {
      debugPrint('Error pausing recording: $e');
    }
  }

  Future<void> resumeRecording() async {
    if (_recordingState != RecordingState.paused) return;

    try {
      // In audio_waveforms, continue recording with record() method
      await _recorderController.record();
      _recordingState = RecordingState.recording;
      _startChunkTimer();
      _startDurationTimer();
      notifyListeners();
    } catch (e) {
      debugPrint('Error resuming recording: $e');
    }
  }

  Future<void> stopRecording() async {
    if (_recordingState == RecordingState.idle) return;

    try {
      // Stop recording
      final path = await _recorderController.stop();

      // Process final chunk
      if (path != null) {
        await _processFinalChunk(path);
      }

      // Clean up timers
      _chunkTimer?.cancel();
      _durationTimer?.cancel();

      // Stop foreground service
      await FlutterForegroundTask.stopService();

      // Update session status
      if (_currentSession != null) {
        await _apiService.updateSessionStatus(_currentSession!.id, 'completed', _currentChunkNumber);
      }

      _recordingState = RecordingState.stopped;
      notifyListeners();
    } catch (e) {
      debugPrint('Error stopping recording: $e');
      _recordingState = RecordingState.error;
      notifyListeners();
    }
  }

  void _startChunkTimer() {
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
    // Simulate amplitude since getAmplitude() doesn't exist in current API
    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_recordingState == RecordingState.recording) {
        // Generate realistic amplitude simulation
        final time = DateTime.now().millisecondsSinceEpoch;
        _currentAmplitude = 20 + (40 * ((time % 3000) / 3000.0)) +
            (10 * ((time % 500) / 500.0));
        notifyListeners();
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
    if (_isProcessingChunks || _currentSession == null) return;
    _isProcessingChunks = true;

    try {
      _currentChunkNumber++;

      // For demo, create empty chunk - in real implementation you'd capture actual audio
      final chunkData = Uint8List.fromList([]);
      final chunk = AudioChunk(
        sessionId: _currentSession!.id,
        chunkNumber: _currentChunkNumber,
        data: chunkData,
        mimeType: 'audio/m4a',
        timestamp: DateTime.now(),
      );

      _pendingChunks.add(chunk);
      _uploadChunk(chunk);

      notifyListeners();
    } catch (e) {
      debugPrint('Error processing chunk: $e');
    } finally {
      _isProcessingChunks = false;
    }
  }

  Future<void> _processFinalChunk(String filePath) async {
    try {
      final file = await _storageService.readFile(filePath);
      if (file != null) {
        _currentChunkNumber++;
        final chunk = AudioChunk(
          sessionId: _currentSession!.id,
          chunkNumber: _currentChunkNumber,
          data: file,
          mimeType: 'audio/m4a',
          timestamp: DateTime.now(),
        );

        _pendingChunks.add(chunk);
        await _uploadChunk(chunk);
      }
    } catch (e) {
      debugPrint('Error processing final chunk: $e');
    }
  }

  Future<void> _uploadChunk(AudioChunk chunk) async {
    if (_currentSession == null) return;

    try {
      chunk.status = ChunkStatus.uploading;
      notifyListeners();

      final success = await _apiService.uploadAudioChunk(
        chunk,
        _currentSession!.templateId ?? 'new_patient_visit',
        chunk.chunkNumber == _currentChunkNumber, // isLast
      );

      if (success) {
        chunk.status = ChunkStatus.uploaded;
        _pendingChunks.remove(chunk);
      } else {
        chunk.status = ChunkStatus.failed;
        chunk.retryCount++;
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error uploading chunk: $e');
      chunk.status = ChunkStatus.failed;
      chunk.error = e.toString();
      notifyListeners();
    }
  }

  Future<void> retryFailedChunks() async {
    final failedChunks = _pendingChunks.where((c) => c.shouldRetry).toList();
    for (final chunk in failedChunks) {
      chunk.status = ChunkStatus.retrying;
      await _uploadChunk(chunk);
    }
  }

  @override
  void dispose() {
    _chunkTimer?.cancel();
    _durationTimer?.cancel();
    _recorderController.dispose();
    FlutterForegroundTask.stopService();
    super.dispose();
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
    // Update notification
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