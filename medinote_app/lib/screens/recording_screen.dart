import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/patient.dart';
import '../models/audio_recording.dart';
import '../services/audio_recording_service.dart';
import '../services/audio_streaming_service.dart';
import '../services/offline_recording_service.dart';
import '../services/persistent_recording_service.dart';
import '../widgets/offline_recording_status.dart';

class RecordingScreen extends StatefulWidget {
  final Patient patient;
  final String? resumeSessionId;

  const RecordingScreen({super.key, required this.patient, this.resumeSessionId});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  
  // Cache for sessions to prevent repeated API calls during recording
  Future<List<Map<String, dynamic>>>? _cachedSessionsFuture;
  bool _wasRecording = false;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    
    // Auto-resume session if resumeSessionId is provided
    if (widget.resumeSessionId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _resumeIncompleteSession(widget.resumeSessionId!);
      });
    }
    
    // Set up offline recording notifications
    _setupOfflineNotifications();
  }
  
  void _setupOfflineNotifications() {
    final offlineService = context.read<OfflineRecordingService>();
    offlineService.setNotificationCallbacks(
      onUploadStart: (chunkCount) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.cloud_upload, color: Colors.white),
                  const SizedBox(width: 8),
                  Text('Uploading $chunkCount offline chunks...'),
                ],
              ),
              backgroundColor: Colors.blue[700],
              duration: const Duration(seconds: 3),
            ),
          );
        }
      },
      onUploadSuccess: (chunkCount) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.cloud_done, color: Colors.white),
                  const SizedBox(width: 8),
                  Text('Successfully uploaded $chunkCount offline chunks'),
                ],
              ),
              backgroundColor: Colors.green[700],
              duration: const Duration(seconds: 3),
            ),
          );
        }
      },
      onUploadError: (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Failed to upload offline chunks: $error')),
                ],
              ),
              backgroundColor: Colors.red[700],
              duration: const Duration(seconds: 5),
            ),
          );
        }
      },
      onOfflineRecordingEnd: () {
        if (mounted) {
          print('🔄 Offline recording ended, switching UI back to online mode');
          // The UI will automatically update when the offline recording service state changes
          // This callback ensures the UI knows to switch back to online mode
        }
      },
    );
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
  }

  Future<List<Map<String, dynamic>>> _getCachedSessions(AudioRecordingService audioService) {
    // Track recording state changes
    if (audioService.isRecording && !_wasRecording) {
      _wasRecording = true;
    } else if (!audioService.isRecording && _wasRecording) {
      _wasRecording = false;
      // Recording just ended, refresh the cache
      _cachedSessionsFuture = audioService.getPatientAudioSessions(widget.patient.id!);
      return _cachedSessionsFuture!;
    }
    
    // If we're recording, use cached sessions to prevent repeated API calls
    if (audioService.isRecording) {
      if (_cachedSessionsFuture == null) {
        _cachedSessionsFuture = audioService.getPatientAudioSessions(widget.patient.id!);
      }
      return _cachedSessionsFuture!;
    } else {
      // If no cache exists, create one
      if (_cachedSessionsFuture == null) {
        _cachedSessionsFuture = audioService.getPatientAudioSessions(widget.patient.id!);
      }
      return _cachedSessionsFuture!;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text('Recording - ${widget.patient.name}'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Consumer<AudioRecordingService>(
        builder: (context, audioService, child) {
          return Consumer<PersistentRecordingService>(
            builder: (context, persistentService, child) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    // Recording Status Card
                    _buildStatusCard(audioService),
                    
                    // Offline Recording Status
                    const OfflineRecordingStatus(),
                    
                    // Call Interruption Status
                    if (persistentService.wasPausedByCall)
                      _buildCallInterruptionStatus(),
                    
                    const SizedBox(height: 24),
                    
                    // Recording Status Display
                    _buildRecordingStatus(audioService),
                    
                    const SizedBox(height: 8),
                    
                    // Streaming Status Display
                    _buildStreamingStatus(audioService),
                    
                    const SizedBox(height: 20),
                    
                    // Recording Controls
                    _buildRecordingControls(audioService),
                    
                    const SizedBox(height: 20),
                    
                    // Recent Recordings
                    _buildRecentRecordings(),
                    
                    const SizedBox(height: 24),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildStatusCard(AudioRecordingService audioService) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            audioService.isRecording 
                ? (audioService.isPaused ? Icons.pause_circle : Icons.mic)
                : Icons.mic_none,
            size: 48,
            color: audioService.isRecording 
                ? (audioService.isPaused ? Colors.orange : Colors.red)
                : Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            audioService.isRecording 
                ? (audioService.isPaused ? 'Recording Paused' : 'Recording...')
                : 'Ready to Record',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            audioService.isRecording 
                ? audioService.formatDuration(audioService.recordingDuration)
                : 'Tap the record button to start',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallInterruptionStatus() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.red[50],
        border: Border.all(color: Colors.red[300]!),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.phone_paused, color: Colors.red[700]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recording Paused - Call in Progress',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red[700],
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Recording has been paused due to an incoming call. It will automatically resume when the call ends.',
                  style: TextStyle(
                    color: Colors.red[600],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingStatus(AudioRecordingService audioService) {
    return Container(
      height: 80,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: audioService.isRecording && !audioService.isPaused
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Recording Status',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Duration',
                            style: TextStyle(
                              fontSize: 8,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            audioService.formatDuration(audioService.recordingDuration),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[700],
                            ),
                          ),
                        ],
                      ),
                      Container(
                        width: 1,
                        height: 16,
                        color: Colors.grey[300],
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Status',
                            style: TextStyle(
                              fontSize: 8,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            'Recording',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.red[700],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            )
          : Center(
              child: Text(
                'Recording status will appear here',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 10,
                ),
              ),
            ),
    );
  }

    Widget _buildStreamingStatus(AudioRecordingService audioService) {
      return Container(
        height: 40,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: audioService.isRecording
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          audioService.isStreamingConnected ? Icons.wifi : Icons.wifi_off,
                          size: 10,
                          color: audioService.isStreamingConnected ? Colors.green[700] : Colors.red[700],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Stream',
                          style: TextStyle(
                            fontSize: 8,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    Container(
                      width: 1,
                      height: 12,
                      color: Colors.grey[300],
                    ),
                    Text(
                      '${(audioService.bytesStreamed / 1024).toStringAsFixed(1)}KB',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[700],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 12,
                      color: Colors.grey[300],
                    ),
                    Text(
                      '${audioService.chunksStreamed}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                    ),
                  ],
                ),
              )
            : Center(
                child: Text(
                  'Streaming status will appear here',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 8,
                  ),
                ),
              ),
      );
    }

  Widget _buildRecordingControls(AudioRecordingService audioService) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Stop Button
        if (audioService.isRecording)
          _buildControlButton(
            icon: Icons.stop,
            color: Colors.red[600]!,
            onPressed: () => _stopRecording(audioService),
            size: 60,
          ),
        
        // Main Record/Pause Button
        _buildControlButton(
          icon: audioService.isRecording 
              ? (audioService.isPaused ? Icons.play_arrow : Icons.pause)
              : Icons.mic,
          color: audioService.isRecording 
              ? (audioService.isPaused ? Colors.green[600]! : Colors.orange[600]!)
              : Colors.red[600]!,
          onPressed: () => _handleMainAction(audioService),
          size: 80,
          isMain: true,
        ),
        
        // Play Button (if not recording)
        if (!audioService.isRecording)
          _buildControlButton(
            icon: Icons.play_arrow,
            color: Colors.blue[600]!,
            onPressed: () => _showRecordingsList(),
            size: 60,
          ),
      ],
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    required double size,
    bool isMain = false,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: isMain ? 20 : 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: isMain ? 32 : 24,
        ),
      ),
    );
  }

  Widget _buildRecentRecordings() {
    return Consumer<AudioRecordingService>(
      builder: (context, audioService, child) {
        // Use a cached future that only refreshes when recording ends
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _getCachedSessions(audioService),
          builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final sessions = (snapshot.data ?? []).reversed.toList(); // Reverse to show newest first
        
        if (sessions.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Icon(
                  Icons.mic_off,
                  size: 40,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 12),
                Text(
                  'No recordings yet',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Recent Recordings',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              ...sessions.asMap().entries.map((entry) => _buildSessionItem(entry.value, entry.key)),
            ],
          ),
        );
          },
        );
      },
    );
  }

  Widget _buildSessionItem(Map<String, dynamic> session, int index) {
    final sessionId = session['session_id']?.toString() ?? '';
    
    return Consumer<AudioRecordingService>(
      builder: (context, audioService, child) {
        final isPlaying = audioService.currentlyPlayingId == sessionId.hashCode;
        final isLoading = audioService.isLoadingAudio && audioService.currentlyPlayingId == sessionId.hashCode;
        
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                Icons.audiotrack,
                color: Colors.blue[600],
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Session ${index + 1}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      '${_formatFileSize(session['file_size'] ?? 0)} • ${_formatDate(DateTime.parse(session['created_at'] ?? DateTime.now().toIso8601String()))}',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              if (isLoading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                  ),
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Show resume button for incomplete sessions
                    if (session['is_completed'] == 0)
                      IconButton(
                        icon: Icon(
                          Icons.restore,
                          color: Colors.orange[600],
                          size: 20,
                        ),
                        onPressed: () => _resumeIncompleteSession(sessionId),
                        tooltip: 'Resume recording',
                      ),
                    // Show play/pause button for all sessions
                    IconButton(
                      icon: Icon(
                        isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.blue[600],
                        size: 20,
                      ),
                      onPressed: () => _toggleBackendPlayback(sessionId, audioService),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRecordingItem(AudioRecording recording, AudioRecordingService audioService) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.audiotrack,
            color: Colors.blue[600],
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recording.fileName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '${audioService.formatDuration(recording.duration)} • ${_formatDate(recording.createdAt)}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              audioService.currentlyPlayingId == recording.id ? Icons.pause : Icons.play_arrow,
              color: Colors.blue[600],
              size: 20,
            ),
            onPressed: () => _togglePlayback(recording, audioService),
          ),
        ],
      ),
    );
  }

  void _handleMainAction(AudioRecordingService audioService) async {
    try {
      final persistentService = context.read<PersistentRecordingService>();
      
      if (!audioService.isRecording) {
        // Start persistent recording
        final sessionId = 'session_${DateTime.now().millisecondsSinceEpoch}_${widget.patient.id}';
        final streamingService = context.read<AudioStreamingService>();
        await persistentService.startRecording(sessionId, streamingService);
        await audioService.startRecording(widget.patient.id!);
        _pulseController.repeat(reverse: true);
        HapticFeedback.mediumImpact();
      } else if (audioService.isPaused) {
        await audioService.resumeRecording();
        _pulseController.repeat(reverse: true);
        HapticFeedback.mediumImpact();
      } else {
        await audioService.pauseRecording();
        _pulseController.stop();
        HapticFeedback.lightImpact();
      }
    } catch (e) {
      _showErrorSnackBar('Error: $e');
    }
  }

  void _stopRecording(AudioRecordingService audioService) async {
    try {
      final persistentService = context.read<PersistentRecordingService>();
      
      // Stop persistent recording
      await persistentService.stopRecording();
      await audioService.stopRecording(widget.patient.id!);
      _pulseController.stop();
      HapticFeedback.mediumImpact();
      _showSuccessSnackBar('Recording saved successfully!');
    } catch (e) {
      _showErrorSnackBar('Error: $e');
    }
  }

  void _toggleBackendPlayback(String sessionId, AudioRecordingService audioService) async {
    try {
      if (audioService.isPlaying) {
        await audioService.stopAudioFromBackend();
      } else {
        await audioService.playAudioFromBackend(sessionId);
      }
    } catch (e) {
      _showErrorSnackBar('Error playing audio: $e');
    }
  }

  void _resumeIncompleteSession(String sessionId) async {
    try {
      // Resume the existing incomplete session with the same session ID
      final audioService = context.read<AudioRecordingService>();
      final streamingService = context.read<AudioStreamingService>();
      
      // Start recording with the existing session ID
      await audioService.startRecording(widget.patient.id!);
      
      // Resume streaming with the existing session ID
      await streamingService.startStreaming(sessionId);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Resuming session: $sessionId'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to resume session: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }


  void _togglePlayback(AudioRecording recording, AudioRecordingService audioService) async {
    try {
      if (audioService.isPlaying) {
        await audioService.stopPlayback();
      } else {
        await audioService.playRecording(recording);
      }
    } catch (e) {
      _showErrorSnackBar('Error: $e');
    }
  }


  void _showRecordingsList() {
    // TODO: Navigate to recordings list screen
    _showInfoSnackBar('Recordings list coming soon!');
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[600],
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green[600],
      ),
    );
  }

  void _showInfoSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.blue[600],
      ),
    );
  }
}


