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
  String? _actualSessionId;
  
  // WebSocket connection
  WebSocketChannel? _channel;
  
  // UI state
  double _currentAmplitude = 0.0;
  final List<double> _amplitudeHistory = List.generate(50, (index) => 0.0);
  late AnimationController _waveformController;
  late AnimationController _pulseController;
  late Animation<double> _waveformAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _apiService = Provider.of<ApiService>(context, listen: false);
    _nativeAudioService = Provider.of<NativeAudioService>(context, listen: false);
    
    // Initialize animations
    _waveformController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    
    _waveformAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _waveformController,
      curve: Curves.easeInOut,
    ));
    
    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.elasticOut,
    ));
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _channel?.sink.close();
    _waveformController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    try {
      // Create session on backend first
      final sessionId = await _apiService.createSession(widget.session);
      if (sessionId == null) {
        throw Exception('Failed to create session');
      }
      
      _actualSessionId = sessionId;
      
      // Start native audio recording
      final success = await _nativeAudioService.startRecording(widget.session);
      if (!success) {
        throw Exception('Failed to start native recording');
      }
      
      // Connect WebSocket
      await _connectWebSocket();
      
      setState(() {
        _isRecording = true;
        _recordingDuration = Duration.zero;
      });
      
      _startDurationTimer();
      _startAudioStreaming();
      _waveformController.repeat(reverse: true);
      _pulseController.repeat(reverse: true);
      
      HapticFeedback.mediumImpact();
    } catch (e) {
      debugPrint('Error starting recording: $e');
      _showSnackBar('Error starting recording: $e', Colors.red);
    }
  }

  Future<void> _connectWebSocket() async {
    try {
      final wsUrl = 'wss://medinote-app-backend-api.onrender.com/ws/audio-stream';
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      
      await _channel!.ready;
      
      // Send session info
      _channel!.sink.add(jsonEncode({
        'type': 'session_start',
        'session_id': _actualSessionId,
        'user_id': widget.session.userId,
        'patient_id': widget.session.patientId,
        'patient_name': widget.session.patientName,
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
    Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      if (!_isRecording || _isPaused) {
        timer.cancel();
        return;
      }
      
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
        
        // Update UI
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
      
      // Send stop message to server
      if (_channel != null && (_actualSessionId?.isNotEmpty ?? false)) {
        _channel!.sink.add(jsonEncode({
          'type': 'stop_streaming',
          'session_id': _actualSessionId,
        }));
        await Future.delayed(const Duration(milliseconds: 500));
        _channel!.sink.close();
        _channel = null;
      }
      
      HapticFeedback.heavyImpact();
      _showSnackBar('Recording completed successfully', Colors.green);
      
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Error stopping recording: $e');
      _showSnackBar('Error stopping recording: $e', Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_isRecording) {
          _showSnackBar('Please stop recording before going back', Colors.orange);
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.session.patientName),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              if (_isRecording) {
                _showSnackBar('Please stop recording before going back', Colors.orange);
                return;
              }
              Navigator.pop(context);
            },
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Patient info
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.person, size: 48, color: Colors.blue),
                    const SizedBox(height: 12),
                    Text(
                      widget.session.patientName,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Recording Session',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 40),
              
              // Duration display
              Text(
                _formatDuration(_recordingDuration),
                style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
              
              const SizedBox(height: 40),
              
              // Amplitude visualizer
              Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: CustomPaint(
                  painter: AmplitudeVisualizerPainter(
                    amplitudeHistory: _amplitudeHistory,
                    isRecording: _isRecording,
                    animation: _waveformAnimation,
                  ),
                ),
              ),
              
              const SizedBox(height: 40),
              
              // Control buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Stop button
                  _buildControlButton(
                    icon: Icons.stop,
                    onPressed: _isRecording ? _stopRecording : null,
                    color: Colors.red,
                  ),
                  
                  // Play/Pause button
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _pulseAnimation.value,
                        child: _buildControlButton(
                          icon: _isRecording 
                              ? (_isPaused ? Icons.play_arrow : Icons.pause)
                              : Icons.mic,
                          onPressed: _isRecording 
                              ? (_isPaused ? _resumeRecording : _pauseRecording)
                              : _startRecording,
                          color: _isRecording 
                              ? (_isPaused ? Colors.green : Colors.orange)
                              : Colors.blue,
                          size: 80,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required Color color,
    double size = 60,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: onPressed != null ? color : Colors.grey[300],
        boxShadow: onPressed != null
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.3),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(size / 2),
          onTap: onPressed,
          child: Icon(
            icon,
            size: size * 0.4,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class AmplitudeVisualizerPainter extends CustomPainter {
  final List<double> amplitudeHistory;
  final bool isRecording;
  final Animation<double> animation;
  
  AmplitudeVisualizerPainter({
    required this.amplitudeHistory,
    required this.isRecording,
    required this.animation,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill;
    
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
  bool shouldRepaint(AmplitudeVisualizerPainter oldDelegate) {
    return oldDelegate.amplitudeHistory != amplitudeHistory ||
        oldDelegate.isRecording != isRecording ||
        oldDelegate.animation.value != animation.value;
  }
}