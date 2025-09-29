import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';

import '../models/session.dart';
import '../services/api_service.dart';
import '../services/native_audio_service.dart';

class SimpleRecordingScreen extends StatefulWidget {
  final RecordingSession session;

  const SimpleRecordingScreen({
    super.key,
    required this.session,
  });

  @override
  State<SimpleRecordingScreen> createState() => _SimpleRecordingScreenState();
}

class _SimpleRecordingScreenState extends State<SimpleRecordingScreen>
    with TickerProviderStateMixin {
  late ApiService _apiService;
  late NativeAudioService _nativeAudioService;
  
  // Recording state
  bool _isRecording = false;
  bool _isPaused = false;
  Duration _recordingDuration = Duration.zero;
  Timer? _durationTimer;
  String? _actualSessionId; // Store the actual session ID from backend
  
  // Audio visualization
  late AnimationController _waveformController;
  late AnimationController _pulseController;
  final List<double> _amplitudeHistory = List.generate(50, (index) => 0.0);
  double _currentAmplitude = 0.0;
  
  // WebSocket connection
  WebSocketChannel? _channel;
  Timer? _audioStreamTimer;
  int _chunkNumber = 0;
  
  @override
  void initState() {
    super.initState();
    _initializeServices();
    _initializeAnimations();
  }
  
  void _initializeServices() {
    _apiService = Provider.of<ApiService>(context, listen: false);
    _nativeAudioService = Provider.of<NativeAudioService>(context, listen: false);
  }
  
  void _initializeAnimations() {
    _waveformController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _waveformController.repeat();
    _pulseController.repeat(reverse: true);
  }
  
  Future<void> _startRecording() async {
    try {
      // Create session on backend first
      final sessionId = await _apiService.createSession(widget.session);
      if (sessionId == null) {
        throw Exception('Failed to create session');
      }
      
      // Store the actual session ID
      _actualSessionId = sessionId;
      
      // Update session with server ID
      final updatedSession = RecordingSession(
        id: sessionId,
        patientId: widget.session.patientId,
        userId: widget.session.userId,
        patientName: widget.session.patientName,
        status: 'recording',
        startTime: DateTime.now(),
      );
      
      // Start native audio recording
      final success = await _nativeAudioService.startRecording(updatedSession);
      if (!success) {
        throw Exception('Failed to start native recording');
      }
      
      // Connect to WebSocket
      await _connectWebSocket(updatedSession);
      
      // Start audio streaming
      _startAudioStreaming();
      
      // Start duration timer
      _startDurationTimer();
      
        setState(() {
        _isRecording = true;
        _isPaused = false;
      });
      
      HapticFeedback.mediumImpact();
      
    } catch (e) {
      debugPrint('Error starting recording: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error starting recording: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  Future<void> _connectWebSocket(RecordingSession session) async {
    try {
      final wsUrl = 'wss://medinote-app-backend-api.onrender.com/ws/audio-stream';
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      
      await _channel!.ready;
      
      // Send session info
      _channel!.sink.add(jsonEncode({
        'type': 'session_start',
        'session_id': _actualSessionId ?? session.id,
        'user_id': session.userId,
        'patient_id': session.patientId,
        'patient_name': session.patientName,
      }));
      
      // Listen for server messages
      _channel!.stream.listen(
        (message) {
          debugPrint('Received server message: $message');
        },
        onError: (error) {
          debugPrint('WebSocket error: $error');
        },
        onDone: () {
          debugPrint('WebSocket connection closed');
        },
      );
      
      debugPrint('WebSocket connected successfully');
    } catch (e) {
      debugPrint('Error connecting WebSocket: $e');
    }
  }
  
  void _startAudioStreaming() {
    // Stream audio data every 100ms
    _audioStreamTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      if (!_isRecording || _isPaused) return;
      
      try {
        // Get current amplitude
        final amplitude = await _nativeAudioService.getCurrentAmplitude();
        _currentAmplitude = ((amplitude.current + 60) / 60 * 100).clamp(0.0, 100.0);
        
        // Update amplitude history for visualization
        _amplitudeHistory.removeAt(0);
        _amplitudeHistory.add(_currentAmplitude);
        
        // Send binary audio data to WebSocket
        if (_channel != null && (_actualSessionId?.isNotEmpty ?? false)) {
          // Get audio data from native audio service
          final audioStream = _nativeAudioService.audioStream;
          if (audioStream != null) {
            audioStream.listen((audioData) {
              if (_channel != null && _isRecording && !_isPaused) {
                // Send binary audio data
                _channel!.sink.add(audioData);
                debugPrint('Sent binary audio data: ${audioData.length} bytes');
              }
            });
          }
        }
        
        // Use post-frame callback to avoid setState during build
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {});
            }
          });
        }
      } catch (e) {
        debugPrint('Error in audio streaming: $e');
      }
    });
  }
  
  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isRecording && !_isPaused) {
        setState(() {
          _recordingDuration += const Duration(seconds: 1);
        });
      }
    });
  }
  
  Future<void> _pauseRecording() async {
    try {
      await _nativeAudioService.pauseRecording();
      
      setState(() {
        _isPaused = true;
      });
      
      HapticFeedback.lightImpact();
      
      // Send pause message to server
      if (_channel != null && (_actualSessionId?.isNotEmpty ?? false)) {
        _channel!.sink.add(jsonEncode({
          'type': 'pause_streaming',
          'session_id': _actualSessionId,
        }));
      }
    } catch (e) {
      debugPrint('Error pausing recording: $e');
    }
  }
  
  Future<void> _resumeRecording() async {
    try {
      await _nativeAudioService.resumeRecording();
      
      setState(() {
        _isPaused = false;
      });
      
      HapticFeedback.lightImpact();
      
      // Send resume message to server
      if (_channel != null && (_actualSessionId?.isNotEmpty ?? false)) {
        _channel!.sink.add(jsonEncode({
          'type': 'resume_streaming',
          'session_id': _actualSessionId,
        }));
      }
    } catch (e) {
      debugPrint('Error resuming recording: $e');
    }
  }
  
  Future<void> _stopRecording() async {
    try {
      await _nativeAudioService.stopRecording();
      
      setState(() {
        _isRecording = false;
        _isPaused = false;
      });
      
      // Stop timers
      _durationTimer?.cancel();
      _audioStreamTimer?.cancel();
      
      // Send stop message to server and update session status
      if (_channel != null && (_actualSessionId?.isNotEmpty ?? false)) {
        _channel!.sink.add(jsonEncode({
          'type': 'stop_streaming',
          'session_id': _actualSessionId,
        }));
        
        // Wait a moment for the message to be sent
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Close the WebSocket connection
        _channel!.sink.close();
        _channel = null;
      }
      
      // Update session status to completed
      if (_actualSessionId != null) {
        await _apiService.updateSessionStatus(_actualSessionId!, 'completed', _chunkNumber);
      }
      
      HapticFeedback.heavyImpact();
      
      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Recording completed successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
      
      // Navigate back
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Error stopping recording: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error stopping recording: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  
  @override
  void dispose() {
    _durationTimer?.cancel();
    _audioStreamTimer?.cancel();
    _waveformController.dispose();
    _pulseController.dispose();
    _channel?.sink.close();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.session.patientName),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_isRecording) {
              _showExitDialog();
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
            // Patient info
            _buildPatientInfo(),
            
            const SizedBox(height: 40),
            
            // Amplitude visualizer
            _buildAmplitudeVisualizer(),
            
            const SizedBox(height: 40),
            
            // Recording duration
            _buildDurationDisplay(),
            
            const SizedBox(height: 40),
            
            // Recording controls
            _buildRecordingControls(),
            
            const SizedBox(height: 40),
            
            // Status indicator
            _buildStatusIndicator(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildPatientInfo() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[800]!),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.person,
            color: Colors.white,
            size: 32,
          ),
          const SizedBox(height: 12),
          Text(
            widget.session.patientName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Recording Session',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 16,
            ),
          ),
                ],
              ),
            );
          }
          
  Widget _buildAmplitudeVisualizer() {
    return Container(
      height: 200,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[800]!),
      ),
            child: Column(
        children: [
          Row(
              children: [
              const Icon(Icons.graphic_eq, color: Colors.white),
              const SizedBox(width: 8),
              const Text(
                'Audio Level',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (_isRecording)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'LIVE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                      ),
                    ],
                  ),
          const SizedBox(height: 20),
          Expanded(
            child: AnimatedBuilder(
              animation: _waveformController,
              builder: (context, child) {
                return CustomPaint(
                  size: const Size(double.infinity, double.infinity),
                  painter: AmplitudePainter(
                    amplitudeHistory: _amplitudeHistory,
                    isRecording: _isRecording,
                    animation: _waveformController,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
                Text(
            '${_currentAmplitude.toInt()}%',
                  style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
                    fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDurationDisplay() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Transform.scale(
          scale: _isRecording ? (1.0 + _pulseController.value * 0.1) : 1.0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: _isRecording ? Colors.red.withValues(alpha: 0.2) : Colors.grey[900],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isRecording ? Colors.red : Colors.grey[800]!,
                width: 2,
              ),
            ),
            child: Text(
              _formatDuration(_recordingDuration),
              style: TextStyle(
                color: _isRecording ? Colors.red : Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildRecordingControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Start/Resume button
        if (!_isRecording)
          _buildControlButton(
            icon: Icons.play_arrow,
            label: 'Start',
            color: Colors.green,
            onPressed: _startRecording,
          )
        else if (_isPaused)
          _buildControlButton(
            icon: Icons.play_arrow,
            label: 'Resume',
            color: Colors.blue,
            onPressed: _resumeRecording,
          )
        else
          _buildControlButton(
            icon: Icons.pause,
            label: 'Pause',
            color: Colors.orange,
            onPressed: _pauseRecording,
          ),
        
        // Stop button
        if (_isRecording)
          _buildControlButton(
            icon: Icons.stop,
            label: 'Stop',
            color: Colors.red,
            onPressed: _stopRecording,
          ),
      ],
    );
  }
  
  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Column(
      children: [
                Container(
          width: 80,
          height: 80,
                  decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.3),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(40),
              onTap: onPressed,
              child: Icon(
                icon,
                size: 40,
                color: Colors.white,
                      ),
                    ),
                  ),
                ),
        const SizedBox(height: 12),
                Text(
          label,
                        style: TextStyle(
            color: Colors.white,
                          fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
  
  Widget _buildStatusIndicator() {
    String status;
    Color statusColor;
    
    if (!_isRecording) {
      status = 'Ready to Record';
      statusColor = Colors.grey;
    } else if (_isPaused) {
      status = 'Recording Paused';
      statusColor = Colors.orange;
    } else {
      status = 'Recording Active';
      statusColor = Colors.red;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
                  children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            status,
            style: TextStyle(
              color: statusColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
      ),
    );
  }
  
  void _showExitDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Exit Recording?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to exit? The current recording will be lost.',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _stopRecording();
            },
            child: const Text(
              'Exit',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}

class AmplitudePainter extends CustomPainter {
  final List<double> amplitudeHistory;
  final bool isRecording;
  final Animation<double> animation;
  
  AmplitudePainter({
    required this.amplitudeHistory,
    required this.isRecording,
    required this.animation,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    
    final centerY = size.height / 2;
    final barWidth = size.width / amplitudeHistory.length;
    
    for (int i = 0; i < amplitudeHistory.length; i++) {
      final barHeight = (amplitudeHistory[i] / 100.0) * (size.height * 0.8);
      final x = i * barWidth;
      
      if (isRecording) {
        final opacity = 0.3 + (0.7 * animation.value);
        paint.color = Colors.red.withValues(alpha: opacity);
      } else {
        paint.color = Colors.grey[600]!;
      }
      
      final actualBarHeight = barHeight.clamp(4.0, size.height * 0.8);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            x + barWidth * 0.1,
            centerY - actualBarHeight / 2,
            barWidth * 0.8,
            actualBarHeight,
          ),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }
  
  @override
  bool shouldRepaint(AmplitudePainter oldDelegate) {
    return oldDelegate.amplitudeHistory != amplitudeHistory ||
        oldDelegate.isRecording != isRecording ||
        oldDelegate.animation.value != animation.value;
  }
}
