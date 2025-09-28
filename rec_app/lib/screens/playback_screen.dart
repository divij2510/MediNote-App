import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/session.dart';
import '../services/audio_service.dart';
import '../services/api_service.dart';

class PlaybackScreen extends StatefulWidget {
  final RecordingSession session;

  const PlaybackScreen({
    super.key,
    required this.session,
  });

  @override
  State<PlaybackScreen> createState() => _PlaybackScreenState();
}

class _PlaybackScreenState extends State<PlaybackScreen> {
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Start loading immediately when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSessionAudio();
    });
  }

  @override
  void dispose() {
    // Stop playback when screen is closed - use Provider.of with listen: false
    try {
      final audioService = Provider.of<AudioService>(context, listen: false);
      audioService.stopAllPlayback();
    } catch (e) {
      debugPrint('Error stopping playback in dispose: $e');
    }
    super.dispose();
  }

  Future<void> _loadSessionAudio() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final audioService = context.read<AudioService>();
      
      // Start loading session audio
      await audioService.loadSessionForPlayback(widget.session.id);
      
      // Wait for the audio to be ready (merged or sequential)
      while (audioService.isLoadingPlayback && mounted) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      // Additional wait to ensure audio is fully ready
      await Future.delayed(const Duration(milliseconds: 500));
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading audio: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Playback - ${widget.session.patientName}'),
        centerTitle: true,
      ),
      body: Consumer<AudioService>(
        builder: (context, audioService, child) {
          if (_isLoading || audioService.isLoadingPlayback) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    _isLoading 
                        ? 'Loading session audio...' 
                        : 'Merging audio chunks...',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (audioService.playbackUrls.isNotEmpty)
                    Text(
                      'Found ${audioService.playbackUrls.length} audio chunks',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  const SizedBox(height: 8),
                  Text(
                    _isLoading 
                        ? 'Downloading and preparing audio...'
                        : 'Creating seamless audio file...',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                ],
              ),
            );
          }
          
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                      // Session info card
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Session Details',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              Text('Patient: ${widget.session.patientName}'),
                              Text('Start Time: ${_formatDateTime(widget.session.startTime)}'),
                              if (widget.session.endTime != null)
                                Text('End Time: ${_formatDateTime(widget.session.endTime!)}'),
                              Text('Status: ${widget.session.status}'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Playback controls
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            children: [
                              // Progress bar
                              LinearProgressIndicator(
                                value: audioService.playbackDuration.inMilliseconds > 0
                                    ? audioService.playbackPosition.inMilliseconds /
                                        audioService.playbackDuration.inMilliseconds
                                    : 0.0,
                              ),
                              const SizedBox(height: 16),

                              // Time display
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(_formatDuration(audioService.playbackPosition)),
                                  Text(_formatDuration(audioService.playbackDuration)),
                                ],
                              ),
                              const SizedBox(height: 24),

                              // Control buttons
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  IconButton(
                                    onPressed: () => audioService.seekTo(
                                      audioService.playbackPosition - const Duration(seconds: 10),
                                    ),
                                    icon: const Icon(Icons.replay_10),
                                    iconSize: 32,
                                  ),
                                  Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Theme.of(context).primaryColor,
                                    ),
                                    child: IconButton(
                                      onPressed: audioService.isPlaying
                                          ? () => audioService.pausePlayback()
                                          : () => audioService.playSession(),
                                      icon: Icon(
                                        audioService.isPlaying ? Icons.pause : Icons.play_arrow,
                                        color: Colors.white,
                                        size: 32,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => audioService.seekTo(
                                      audioService.playbackPosition + const Duration(seconds: 10),
                                    ),
                                    icon: const Icon(Icons.forward_10),
                                    iconSize: 32,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
