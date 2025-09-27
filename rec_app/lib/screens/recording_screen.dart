import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/patient.dart';
import '../models/session.dart';
import '../services/api_service.dart';
import '../services/audio_service.dart';
import '../widgets/audio_visualizer.dart';
import '../widgets/recording_controls.dart';

class RecordingScreen extends StatefulWidget {
  final Patient patient;

  const RecordingScreen({
    super.key,
    required this.patient,
  });

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen>
    with WidgetsBindingObserver {
  bool _isInitialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeRecording();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final audioService = context.read<AudioService>();

    switch (state) {
      case AppLifecycleState.paused:
      // App went to background - pause recording if active
        if (audioService.isRecording) {
          audioService.pauseRecording();
        }
        break;
      case AppLifecycleState.resumed:
      // App came to foreground - resume recording if it was paused
        if (audioService.isPaused) {
          audioService.resumeRecording();
        }
        break;
      default:
        break;
    }
  }

  Future<void> _initializeRecording() async {
    try {
      setState(() {
        _isInitialized = true;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isInitialized = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.patient.name),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _onWillPop().then((shouldPop) {
              if (shouldPop) Navigator.pop(context);
            }),
          ),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (!_isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error, size: 64, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(
              'Error initializing recording',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(_error!),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _initializeRecording,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return Consumer<AudioService>(
      builder: (context, audioService, child) {
        return Column(
          children: [
            // Patient info card
            Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Theme.of(context).primaryColor,
                          child: Text(
                            widget.patient.name[0].toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.patient.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (widget.patient.pronouns != null)
                                Text(
                                  'Pronouns: ${widget.patient.pronouns}',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (widget.patient.background != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Background: ${widget.patient.background}',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Recording status
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          _getStatusIcon(audioService.recordingState),
                          color: _getStatusColor(audioService.recordingState),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _getStatusText(audioService.recordingState),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _getStatusColor(audioService.recordingState),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _formatDuration(audioService.recordingDuration),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    if (audioService.pendingChunks.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.cloud_upload,
                            size: 16,
                            color: Colors.orange.shade600,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${audioService.pendingChunks.length} chunks uploading',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Audio visualizer
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(16),
                child: const AudioVisualizer(),
              ),
            ),

            // Recording controls
            Padding(
              padding: const EdgeInsets.all(16),
              child: RecordingControls(
                patient: widget.patient,
                onRecordingComplete: () {
                  // Navigate back or to session details
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  IconData _getStatusIcon(RecordingState state) {
    switch (state) {
      case RecordingState.idle:
        return Icons.mic_off;
      case RecordingState.recording:
        return Icons.fiber_manual_record;
      case RecordingState.paused:
        return Icons.pause;
      case RecordingState.stopped:
        return Icons.stop;
      case RecordingState.error:
        return Icons.error;
    }
  }

  Color _getStatusColor(RecordingState state) {
    switch (state) {
      case RecordingState.idle:
        return Colors.grey;
      case RecordingState.recording:
        return Colors.red;
      case RecordingState.paused:
        return Colors.orange;
      case RecordingState.stopped:
        return Colors.blue;
      case RecordingState.error:
        return Colors.red;
    }
  }

  String _getStatusText(RecordingState state) {
    switch (state) {
      case RecordingState.idle:
        return 'Ready to Record';
      case RecordingState.recording:
        return 'Recording';
      case RecordingState.paused:
        return 'Paused';
      case RecordingState.stopped:
        return 'Stopped';
      case RecordingState.error:
        return 'Error';
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<bool> _onWillPop() async {
    final audioService = context.read<AudioService>();

    if (audioService.isRecording || audioService.isPaused) {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Stop Recording?'),
          content: const Text(
            'You have an active recording. Do you want to stop and save it?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                audioService.stopRecording();
                Navigator.pop(context, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Stop & Save'),
            ),
          ],
        ),
      );
      return result ?? false;
    }

    return true;
  }
}