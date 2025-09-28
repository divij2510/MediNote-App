import 'package:flutter/material.dart';
import '../models/session.dart';
import '../models/patient.dart';

enum AppPage {
  home,
  patients,
  recording,
  playback,
  settings,
}

enum RecordingState {
  idle,
  initializing,
  recording,
  paused,
  stopping,
  error,
}

class AppState extends ChangeNotifier {
  // Current page
  AppPage _currentPage = AppPage.home;
  AppPage get currentPage => _currentPage;
  
  // Recording state
  RecordingState _recordingState = RecordingState.idle;
  RecordingState get recordingState => _recordingState;
  
  // Current session
  RecordingSession? _currentSession;
  RecordingSession? get currentSession => _currentSession;
  
  // Current patient
  Patient? _currentPatient;
  Patient? get currentPatient => _currentPatient;
  
  // Recording duration
  Duration _recordingDuration = Duration.zero;
  Duration get recordingDuration => _recordingDuration;
  
  // Audio level
  double _audioLevel = 0.0;
  double get audioLevel => _audioLevel;
  
  // Error state
  String? _errorMessage;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;
  
  // Loading state
  bool _isLoading = false;
  bool get isLoading => _isLoading;
  
  // Navigation methods
  void navigateTo(AppPage page) {
    _currentPage = page;
    notifyListeners();
  }
  
  // Recording methods
  void startRecording(Patient patient) {
    _currentPatient = patient;
    _currentSession = RecordingSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      patientId: patient.id,
      userId: 'hardcoded-user-id',
      patientName: patient.name,
      startTime: DateTime.now(),
      status: 'recording',
    );
    _recordingState = RecordingState.initializing;
    _recordingDuration = Duration.zero;
    _errorMessage = null;
    notifyListeners();
  }
  
  void setRecordingState(RecordingState state) {
    _recordingState = state;
    notifyListeners();
  }
  
  void updateRecordingDuration(Duration duration) {
    _recordingDuration = duration;
    notifyListeners();
  }
  
  void updateAudioLevel(double level) {
    _audioLevel = level;
    notifyListeners();
  }
  
  void pauseRecording() {
    if (_recordingState == RecordingState.recording) {
      _recordingState = RecordingState.paused;
      notifyListeners();
    }
  }
  
  void resumeRecording() {
    if (_recordingState == RecordingState.paused) {
      _recordingState = RecordingState.recording;
      notifyListeners();
    }
  }
  
  void stopRecording() {
    _recordingState = RecordingState.stopping;
    notifyListeners();
  }
  
  void finishRecording() {
    _recordingState = RecordingState.idle;
    _currentSession = null;
    _currentPatient = null;
    _recordingDuration = Duration.zero;
    _audioLevel = 0.0;
    notifyListeners();
  }
  
  // Error handling
  void setError(String? error) {
    _errorMessage = error;
    notifyListeners();
  }
  
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
  
  // Loading state
  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }
  
  // Reset app state
  void reset() {
    _currentPage = AppPage.home;
    _recordingState = RecordingState.idle;
    _currentSession = null;
    _currentPatient = null;
    _recordingDuration = Duration.zero;
    _audioLevel = 0.0;
    _errorMessage = null;
    _isLoading = false;
    notifyListeners();
  }
}
