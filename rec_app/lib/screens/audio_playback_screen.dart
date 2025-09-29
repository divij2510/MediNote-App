import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/session.dart';
import '../services/api_service.dart';
import '../services/audio_playback_service.dart';

class AudioPlaybackScreen extends StatefulWidget {
  final RecordingSession session;

  const AudioPlaybackScreen({
    Key? key,
    required this.session,
  }) : super(key: key);

  @override
  State<AudioPlaybackScreen> createState() => _AudioPlaybackScreenState();
}

class _AudioPlaybackScreenState extends State<AudioPlaybackScreen>
    with TickerProviderStateMixin {
  late AudioPlaybackService _playbackService;
  late AnimationController _waveformController;
  late AnimationController _playButtonController;
  late Animation<double> _waveformAnimation;
  late Animation<double> _playButtonAnimation;
  
  // Waveform data for visualization
  final List<double> _waveformData = List.generate(100, (index) => 0.0);
  
  @override
  void initState() {
    super.initState();
    _initializeServices();
    _initializeAnimations();
    _loadAudio();
  }
  
  void _initializeServices() {
    final apiService = Provider.of<ApiService>(context, listen: false);
    _playbackService = AudioPlaybackService(apiService);
  }
  
  void _initializeAnimations() {
    _waveformController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    
    _playButtonController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
    _waveformAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _waveformController,
      curve: Curves.easeInOut,
    ));
    
    _playButtonAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _playButtonController,
      curve: Curves.elasticOut,
    ));
  }
  
  Future<void> _loadAudio() async {
    final success = await _playbackService.loadSessionAudio(widget.session);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load audio: ${_playbackService.errorMessage}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  void _togglePlayPause() {
    if (_playbackService.isPlaying) {
      _playbackService.pause();
      _waveformController.stop();
    } else {
      _playbackService.play();
      _waveformController.repeat();
    }
    
    _playButtonController.forward().then((_) {
      _playButtonController.reverse();
    });
    
    HapticFeedback.lightImpact();
  }
  
  void _stopPlayback() {
    _playbackService.stop();
    _waveformController.stop();
    HapticFeedback.mediumImpact();
  }
  
  void _seekTo(double value) {
    final duration = _playbackService.duration;
    final position = Duration(
      milliseconds: (value * duration.inMilliseconds).round(),
    );
    _playbackService.seekTo(position);
    HapticFeedback.selectionClick();
  }
  
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  
  @override
  void dispose() {
    _waveformController.dispose();
    _playButtonController.dispose();
    _playbackService.dispose();
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
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => _shareRecording(),
            tooltip: 'Share Recording',
          ),
        ],
      ),
      body: Consumer<AudioPlaybackService>(
        builder: (context, playbackService, child) {
          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Session info
                _buildSessionInfo(),
                
                const SizedBox(height: 40),
                
                // Waveform visualization
                _buildWaveformVisualization(),
                
                const SizedBox(height: 40),
                
                // Progress bar
                _buildProgressBar(),
                
                const SizedBox(height: 20),
                
                // Time display
                _buildTimeDisplay(),
                
                const SizedBox(height: 40),
                
                // Playback controls
                _buildPlaybackControls(),
                
                const SizedBox(height: 20),
                
                // Error message
                if (playbackService.errorMessage != null)
                  _buildErrorMessage(),
              ],
            ),
          );
        },
      ),
    );
  }
  
  Widget _buildSessionInfo() {
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
            Icons.mic,
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
          const SizedBox(height: 8),
          Text(
            'Started: ${_formatDateTime(widget.session.startTime)}',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildWaveformVisualization() {
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
                'Audio Waveform',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Consumer<AudioPlaybackService>(
                builder: (context, playbackService, child) {
                  if (playbackService.isPlaying) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'PLAYING',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: AnimatedBuilder(
              animation: _waveformAnimation,
              builder: (context, child) {
                return CustomPaint(
                  size: const Size(double.infinity, double.infinity),
                  painter: WaveformPainter(
                    waveformData: _waveformData,
                    isPlaying: _playbackService.isPlaying,
                    animation: _waveformAnimation,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildProgressBar() {
    return Consumer<AudioPlaybackService>(
      builder: (context, playbackService, child) {
        final duration = playbackService.duration;
        final position = playbackService.position;
        
        if (duration == Duration.zero) {
          return const SizedBox.shrink();
        }
        
        final progress = position.inMilliseconds / duration.inMilliseconds;
        
        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: Colors.blue,
                inactiveTrackColor: Colors.grey[600],
                thumbColor: Colors.blue,
                overlayColor: Colors.blue.withValues(alpha: 0.2),
                trackHeight: 4.0,
              ),
              child: Slider(
                value: progress.clamp(0.0, 1.0),
                onChanged: _seekTo,
              ),
            ),
          ],
        );
      },
    );
  }
  
  Widget _buildTimeDisplay() {
    return Consumer<AudioPlaybackService>(
      builder: (context, playbackService, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatDuration(playbackService.position),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontFamily: 'monospace',
              ),
            ),
            Text(
              _formatDuration(playbackService.duration),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontFamily: 'monospace',
              ),
            ),
          ],
        );
      },
    );
  }
  
  Widget _buildPlaybackControls() {
    return Consumer<AudioPlaybackService>(
      builder: (context, playbackService, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Stop button
            _buildControlButton(
              icon: Icons.stop,
              onPressed: playbackService.isPlaying || playbackService.position > Duration.zero
                  ? _stopPlayback
                  : null,
              color: Colors.red,
            ),
            
            // Play/Pause button
            AnimatedBuilder(
              animation: _playButtonAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _playButtonAnimation.value,
                  child: _buildControlButton(
                    icon: playbackService.isPlaying ? Icons.pause : Icons.play_arrow,
                    onPressed: playbackService.isLoading ? null : _togglePlayPause,
                    color: playbackService.isPlaying ? Colors.orange : Colors.green,
                    size: 80,
                  ),
                );
              },
            ),
            
            // Speed control
            _buildControlButton(
              icon: Icons.speed,
              onPressed: () => _showSpeedDialog(),
              color: Colors.blue,
            ),
          ],
        );
      },
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
        color: onPressed != null ? color : Colors.grey[600],
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
  
  Widget _buildErrorMessage() {
    return Consumer<AudioPlaybackService>(
      builder: (context, playbackService, child) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.red),
          ),
          child: Row(
            children: [
              const Icon(Icons.error, color: Colors.red),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  playbackService.errorMessage ?? 'Unknown error',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.red),
                onPressed: () => playbackService.clearError(),
              ),
            ],
          ),
        );
      },
    );
  }
  
  void _showSpeedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Playback Speed',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSpeedOption(0.5, '0.5x'),
            _buildSpeedOption(0.75, '0.75x'),
            _buildSpeedOption(1.0, '1.0x (Normal)'),
            _buildSpeedOption(1.25, '1.25x'),
            _buildSpeedOption(1.5, '1.5x'),
            _buildSpeedOption(2.0, '2.0x'),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSpeedOption(double speed, String label) {
    return ListTile(
      title: Text(
        label,
        style: const TextStyle(color: Colors.white),
      ),
      onTap: () {
        _playbackService.setSpeed(speed);
        Navigator.pop(context);
      },
    );
  }
  
  void _shareRecording() {
    // TODO: Implement sharing functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sharing functionality coming soon'),
      ),
    );
  }
  
  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}

class WaveformPainter extends CustomPainter {
  final List<double> waveformData;
  final bool isPlaying;
  final Animation<double> animation;
  
  WaveformPainter({
    required this.waveformData,
    required this.isPlaying,
    required this.animation,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    
    final centerY = size.height / 2;
    final barWidth = size.width / waveformData.length;
    
    for (int i = 0; i < waveformData.length; i++) {
      final barHeight = (waveformData[i] / 100.0) * (size.height * 0.8);
      final x = i * barWidth;
      
      if (isPlaying) {
        final opacity = 0.3 + (0.7 * animation.value);
        paint.color = Colors.blue.withValues(alpha: opacity);
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
  bool shouldRepaint(WaveformPainter oldDelegate) {
    return oldDelegate.waveformData != waveformData ||
        oldDelegate.isPlaying != isPlaying ||
        oldDelegate.animation.value != animation.value;
  }
}