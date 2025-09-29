import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/patient.dart';
import '../models/session.dart';
import '../services/api_service.dart';
import '../services/audio_service.dart';
import '../services/realtime_streaming_service.dart';

class RecordingControls extends StatefulWidget {
  final Patient patient;
  final VoidCallback? onRecordingComplete;

  const RecordingControls({
    super.key,
    required this.patient,
    this.onRecordingComplete,
  });

  @override
  State<RecordingControls> createState() => _RecordingControlsState();
}

class _RecordingControlsState extends State<RecordingControls> {
  bool _isStarting = false;

  @override
  Widget build(BuildContext context) {
    return Consumer3<AudioService, ApiService, RealtimeStreamingService>(
      builder: (context, audioService, apiService, streamingService, child) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Main recording button
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _getButtonColor(audioService.recordingState),
                boxShadow: [
                  BoxShadow(
                    color: _getButtonColor(audioService.recordingState).withOpacity(0.3),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(60),
                  onTap: _isStarting ? null : () => _handleMainButtonTap(audioService, apiService, streamingService),
                  child: Center(
                    child: _isStarting
                        ? const CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    )
                        : Icon(
                      _getButtonIcon(audioService.recordingState),
                      size: 48,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Action buttons row
            if (audioService.recordingState != RecordingState.idle) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Pause/Resume button
                  if (audioService.isRecording || audioService.isPaused)
                    _buildActionButton(
                      icon: audioService.isPaused ? Icons.play_arrow : Icons.pause,
                      label: audioService.isPaused ? 'Resume' : 'Pause',
                      onPressed: () => _handlePauseResume(audioService),
                      color: Colors.orange,
                    ),

                  // Stop button
                  if (audioService.isRecording || audioService.isPaused)
                    _buildActionButton(
                      icon: Icons.stop,
                      label: 'Stop',
                      onPressed: () => _handleStop(audioService),
                      color: Colors.red,
                    ),
                ],
              ),
            ],

            // Status text
            const SizedBox(height: 16),
            Text(
              _getStatusText(audioService.recordingState),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
            ),

            // Connection status
            if (!apiService.isConnected) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_off,
                      size: 16,
                      color: Colors.orange.shade700,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Offline - recordings will be queued',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(28),
              onTap: onPressed,
              child: Icon(
                icon,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Color _getButtonColor(RecordingState state) {
    switch (state) {
      case RecordingState.idle:
        return Colors.green;
      case RecordingState.recording:
        return Colors.red;
      case RecordingState.paused:
        return Colors.orange;
      case RecordingState.stopped:
        return Colors.blue;
      case RecordingState.error:
        return Colors.red.shade800;
    }
  }

  IconData _getButtonIcon(RecordingState state) {
    switch (state) {
      case RecordingState.idle:
        return Icons.mic;
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

  String _getStatusText(RecordingState state) {
    switch (state) {
      case RecordingState.idle:
        return 'Tap to start recording';
      case RecordingState.recording:
        return 'Recording in progress...';
      case RecordingState.paused:
        return 'Recording paused';
      case RecordingState.stopped:
        return 'Recording completed';
      case RecordingState.error:
        return 'Recording error occurred';
    }
  }

  Future<void> _handleMainButtonTap(AudioService audioService, ApiService apiService, RealtimeStreamingService streamingService) async {
    // Enhanced haptic feedback
    if (audioService.recordingState == RecordingState.idle) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.heavyImpact();
    }

    if (audioService.recordingState == RecordingState.idle) {
      await _startRecording(audioService, apiService, streamingService);
    } else if (audioService.recordingState == RecordingState.recording ||
        audioService.recordingState == RecordingState.paused) {
      await _handleStop(audioService);
    }
  }

  Future<void> _startRecording(AudioService audioService, ApiService apiService, RealtimeStreamingService streamingService) async {
    if (_isStarting) {
      debugPrint('Already starting recording, ignoring duplicate request');
      return;
    }
    
    setState(() {
      _isStarting = true;
    });

    try {
      // Create new session
      debugPrint("CREATING SESSION FOR PATIENT ID:"+widget.patient.id);

      final session = RecordingSession(
        id: '', // Will be set by API
        patientId: widget.patient.id,
        userId: ApiService.hardcodedUserId, // Use hardcoded user ID
        patientName: widget.patient.name,
        status: 'recording',
        startTime: DateTime.now(),
        // templateId: ''
      );


      // Create session on server
      final sessionId = await apiService.createSession(session);
      if (sessionId == null) {
        throw Exception('Failed to create session');
      }

      // Update session with server ID
      final updatedSession = RecordingSession(
        id: sessionId,
        patientId: session.patientId,
        userId: session.userId,
        patientName: session.patientName,
        status: session.status,
        startTime: session.startTime,
        // templateId: session.templateId,
      );

      // Start real-time streaming instead of regular recording
      final success = await streamingService.startStreamingSession(updatedSession);
      if (!success) {
        throw Exception('Failed to start streaming session');
      }
      
      // Also start regular recording as backup
      await audioService.startRecording(updatedSession);

      HapticFeedback.mediumImpact();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error starting recording: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isStarting = false;
      });
    }
  }

  Future<void> _handlePauseResume(AudioService audioService) async {
    HapticFeedback.lightImpact();

    if (audioService.isPaused) {
      await audioService.resumeRecording();
    } else {
      await audioService.pauseRecording();
    }
  }

  Future<void> _handleStop(AudioService audioService) async {
    HapticFeedback.mediumImpact();

    await audioService.stopRecording();
    
    // Reset the audio service state for next recording
    audioService.resetRecordingState();

    // Show success message instead of navigating
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recording saved successfully'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }

    if (widget.onRecordingComplete != null) {
      widget.onRecordingComplete!();
    }
  }
}