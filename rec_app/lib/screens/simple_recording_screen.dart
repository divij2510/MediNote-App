import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/session.dart';
import '../services/realtime_audio_service.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

class SimpleRecordingScreen extends StatefulWidget {
  final RecordingSession session;

  const SimpleRecordingScreen({
    Key? key,
    required this.session,
  }) : super(key: key);

  @override
  State<SimpleRecordingScreen> createState() => _SimpleRecordingScreenState();
}

class _SimpleRecordingScreenState extends State<SimpleRecordingScreen> {
  late RealtimeAudioService _audioService;
  late ApiService _apiService;
  late StorageService _storageService;
  
  bool _isInitialized = false;
  double _currentAmplitude = 0.0;
  
  @override
  void initState() {
    super.initState();
    _initializeServices();
    _startRecording();
  }
  
  void _initializeServices() {
    _apiService = Provider.of<ApiService>(context, listen: false);
    _storageService = Provider.of<StorageService>(context, listen: false);
    _audioService = Provider.of<RealtimeAudioService>(context, listen: false);
  }
  
  Future<void> _startRecording() async {
    try {
      // Initialize audio service
      _audioService.initialize(_apiService, _storageService);
      
      // Start streaming session
      final success = await _audioService.startStreamingSession(widget.session);
      
      if (success) {
        setState(() {
          _isInitialized = true;
        });
        
        // Haptic feedback
        HapticFeedback.lightImpact();
        
        // Start monitoring amplitude
        _startAmplitudeMonitoring();
      } else {
        _showErrorDialog('Failed to start recording session');
        // Navigate back on failure
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      _showErrorDialog('Error starting recording: $e');
      // Navigate back on error
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }
  
  void _startAmplitudeMonitoring() {
    // Monitor amplitude every 100ms
    Future.doWhile(() async {
      if (_isInitialized && _audioService.isStreaming) {
        setState(() {
          _currentAmplitude = _audioService.currentAmplitude;
        });
        await Future.delayed(const Duration(milliseconds: 100));
        return true;
      }
      return false;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        title: Text('Recording - ${widget.session.patientName}'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _stopRecording,
            icon: const Icon(Icons.stop),
            tooltip: 'Stop Recording',
          ),
        ],
      ),
      body: Consumer<RealtimeAudioService>(
        builder: (context, audioService, child) {
          if (!_isInitialized) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Starting recording...'),
                ],
              ),
            );
          }
          
          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Recording status
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: audioService.isStreaming ? Colors.red : Colors.grey,
                    boxShadow: [
                      BoxShadow(
                        color: (audioService.isStreaming ? Colors.red : Colors.grey).withOpacity(0.3),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Icon(
                    audioService.isStreaming ? Icons.mic : Icons.mic_off,
                    color: Colors.white,
                    size: 48,
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Status text
                Text(
                  audioService.isStreaming ? 'Recording...' : 'Stopped',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Duration
                Text(
                  _formatDuration(audioService.streamingDuration),
                  style: const TextStyle(
                    fontSize: 18,
                    color: Colors.black54,
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Audio level indicator
                Container(
                  width: double.infinity,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: _currentAmplitude / 100.0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: _currentAmplitude > 0 ? Colors.green : Colors.grey,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 8),
                
                Text(
                  'Audio Level: ${_currentAmplitude.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black54,
                  ),
                ),
                
                const SizedBox(height: 48),
                
                // Patient info
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Session Details',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('Patient: ${widget.session.patientName}'),
                      Text('Session ID: ${widget.session.id}'),
                      Text('Status: ${audioService.streamingState.name}'),
                    ],
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Control buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    if (audioService.isStreaming && !audioService.isPaused)
                      ElevatedButton.icon(
                        onPressed: _pauseRecording,
                        icon: const Icon(Icons.pause),
                        label: const Text('Pause'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                      ),
                    
                    if (audioService.isPaused)
                      ElevatedButton.icon(
                        onPressed: _resumeRecording,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Resume'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                      ),
                    
                    ElevatedButton.icon(
                      onPressed: _stopRecording,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
  
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  
  Future<void> _pauseRecording() async {
    try {
      await _audioService.pauseStreaming();
      HapticFeedback.lightImpact();
    } catch (e) {
      _showErrorDialog('Error pausing recording: $e');
    }
  }
  
  Future<void> _resumeRecording() async {
    try {
      await _audioService.resumeStreaming();
      HapticFeedback.lightImpact();
    } catch (e) {
      _showErrorDialog('Error resuming recording: $e');
    }
  }
  
  Future<void> _stopRecording() async {
    try {
      await _audioService.stopStreaming();
      HapticFeedback.mediumImpact();
      
      // Navigate back
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      _showErrorDialog('Error stopping recording: $e');
    }
  }
  
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
