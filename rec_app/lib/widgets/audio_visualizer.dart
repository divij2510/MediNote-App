import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/audio_service.dart';

class AudioVisualizer extends StatefulWidget {
  const AudioVisualizer({super.key});

  @override
  State<AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends State<AudioVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  final List<double> _waveformData = List.generate(50, (index) => 0.0);
  double _lastAmplitude = 0.0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _updateWaveform(double amplitude) {
    // Only update if amplitude has changed significantly to avoid unnecessary builds
    if ((_lastAmplitude - amplitude).abs() > 2.0) {
      _lastAmplitude = amplitude;

      // Use addPostFrameCallback to avoid setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            // Shift existing data left
            for (int i = 0; i < _waveformData.length - 1; i++) {
              _waveformData[i] = _waveformData[i + 1];
            }
            // Add new amplitude data
            _waveformData[_waveformData.length - 1] = amplitude;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AudioService>(
      builder: (context, audioService, child) {
        // Update animation controller based on recording state
        if (audioService.isRecording) {
          if (!_animationController.isAnimating) {
            _animationController.repeat();
          }
          // Update waveform data (this will schedule the setState for after build)
          _updateWaveform(audioService.currentAmplitude);
        } else {
          _animationController.stop();
          // Clear waveform when not recording
          _updateWaveform(0.0);
        }

        return Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.graphic_eq,
                      color: audioService.isRecording
                          ? Colors.red
                          : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Audio Levels',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: audioService.isRecording
                            ? Colors.red
                            : Colors.grey.shade600,
                      ),
                    ),
                    const Spacer(),
                    if (audioService.isRecording)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
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
              ),

              // Waveform visualization
              Expanded(
                child: AnimatedBuilder(
                  animation: _animationController,
                  builder: (context, child) {
                    return CustomPaint(
                      size: const Size(double.infinity, double.infinity),
                      painter: WaveformPainter(
                        waveformData: _waveformData,
                        isRecording: audioService.isRecording,
                        animation: _animationController,
                      ),
                    );
                  },
                ),
              ),

              // Volume meter
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      'Volume Level',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: (audioService.currentAmplitude / 100.0).clamp(0.0, 1.0),
                      backgroundColor: Colors.grey.shade300,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _getVolumeColor(audioService.currentAmplitude),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Low',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        Text(
                          '${audioService.currentAmplitude.toInt()}%',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'High',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _getVolumeColor(double amplitude) {
    if (amplitude < 20) return Colors.green;
    if (amplitude < 50) return Colors.yellow;
    if (amplitude < 80) return Colors.orange;
    return Colors.red;
  }
}

class WaveformPainter extends CustomPainter {
  final List<double> waveformData;
  final bool isRecording;
  final Animation<double> animation;

  WaveformPainter({
    required this.waveformData,
    required this.isRecording,
    required this.animation,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 2.0
      ..style = PaintingStyle.fill;

    final barWidth = size.width / waveformData.length;
    final centerY = size.height / 2;

    for (int i = 0; i < waveformData.length; i++) {
      final barHeight = (waveformData[i] / 100.0) * (size.height * 0.8);
      final x = i * barWidth;

      // Create gradient effect for active recording
      if (isRecording) {
        final opacity = 0.3 + (0.7 * (i / waveformData.length));
        paint.color = Colors.red.withOpacity(opacity * animation.value);
      } else {
        paint.color = Colors.grey.shade400;
      }

      // Draw bar (ensure minimum height for visibility)
      final actualBarHeight = math.max(barHeight, 4.0);
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
        oldDelegate.isRecording != isRecording ||
        oldDelegate.animation.value != animation.value;
  }
}