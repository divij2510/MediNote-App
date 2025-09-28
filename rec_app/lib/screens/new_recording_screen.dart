import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../models/patient.dart';

class NewRecordingScreen extends StatefulWidget {
  final Patient patient;

  const NewRecordingScreen({
    Key? key,
    required this.patient,
  }) : super(key: key);

  @override
  State<NewRecordingScreen> createState() => _NewRecordingScreenState();
}

class _NewRecordingScreenState extends State<NewRecordingScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _waveController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _waveAnimation;
  
  Timer? _durationTimer;
  Timer? _audioLevelTimer;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _startRecording();
  }

  void _setupAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    
    _waveController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _waveAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _waveController,
      curve: Curves.easeInOut,
    ));

    _pulseController.repeat(reverse: true);
    _waveController.repeat();
  }

  void _startRecording() {
    final appState = context.read<AppState>();
    appState.startRecording(widget.patient);
    _startTimers();
  }

  void _startTimers() {
    // Duration timer
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final appState = context.read<AppState>();
      if (appState.recordingState == RecordingState.recording) {
        appState.updateRecordingDuration(
          appState.recordingDuration + const Duration(seconds: 1),
        );
      }
    });

    // Audio level timer
    _audioLevelTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      final appState = context.read<AppState>();
      if (appState.recordingState == RecordingState.recording) {
        // Simulate audio level changes
        final level = (DateTime.now().millisecondsSinceEpoch % 100) / 100.0;
        appState.updateAudioLevel(level);
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
    _durationTimer?.cancel();
    _audioLevelTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: _buildAppBar(),
      body: Consumer<AppState>(
        builder: (context, appState, child) {
          return _buildBody(appState);
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppTheme.surface,
      elevation: 0,
      leading: IconButton(
        onPressed: _showExitDialog,
        icon: const Icon(Icons.close),
        tooltip: 'Exit Recording',
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recording',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: AppTheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            widget.patient.name,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppTheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        Consumer<AppState>(
          builder: (context, appState, child) {
            return IconButton(
              onPressed: appState.recordingState == RecordingState.recording
                  ? _pauseRecording
                  : _resumeRecording,
              icon: Icon(
                appState.recordingState == RecordingState.recording
                    ? Icons.pause
                    : Icons.play_arrow,
              ),
              tooltip: appState.recordingState == RecordingState.recording
                  ? 'Pause'
                  : 'Resume',
            );
          },
        ),
      ],
    );
  }

  Widget _buildBody(AppState appState) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildRecordingIndicator(appState),
          const SizedBox(height: 48),
          _buildPatientInfo(),
          const SizedBox(height: 48),
          _buildAudioVisualizer(appState),
          const SizedBox(height: 48),
          _buildControls(appState),
        ],
      ),
    );
  }

  Widget _buildRecordingIndicator(AppState appState) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: appState.recordingState == RecordingState.recording
              ? _pulseAnimation.value
              : 1.0,
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _getRecordingColor(appState.recordingState),
              boxShadow: [
                BoxShadow(
                  color: _getRecordingColor(appState.recordingState).withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Icon(
              _getRecordingIcon(appState.recordingState),
              size: 48,
              color: Colors.white,
            ),
          ),
        );
      },
    );
  }

  Widget _buildPatientInfo() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Icon(
                Icons.person,
                size: 30,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.patient.name,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Consumer<AppState>(
              builder: (context, appState, child) {
                return Text(
                  _formatDuration(appState.recordingDuration),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioVisualizer(AppState appState) {
    return Column(
      children: [
        // Audio level bar
        Container(
          width: double.infinity,
          height: 8,
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(4),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: appState.audioLevel,
            child: Container(
              decoration: BoxDecoration(
                color: appState.audioLevel > 0 ? AppTheme.primary : AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Audio Level: ${(appState.audioLevel * 100).toStringAsFixed(0)}%',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppTheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildControls(AppState appState) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildControlButton(
          icon: Icons.replay_10,
          label: 'Rewind',
          onPressed: _rewind,
          color: AppTheme.onSurfaceVariant,
        ),
        _buildMainControlButton(appState),
        _buildControlButton(
          icon: Icons.forward_10,
          label: 'Forward',
          onPressed: _forward,
          color: AppTheme.onSurfaceVariant,
        ),
      ],
    );
  }

  Widget _buildMainControlButton(AppState appState) {
    final isRecording = appState.recordingState == RecordingState.recording;
    final isPaused = appState.recordingState == RecordingState.paused;
    
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isRecording ? AppTheme.recording : AppTheme.primary,
            boxShadow: [
              BoxShadow(
                color: (isRecording ? AppTheme.recording : AppTheme.primary).withOpacity(0.3),
                blurRadius: 15,
                spreadRadius: 3,
              ),
            ],
          ),
          child: IconButton(
            onPressed: isRecording ? _pauseRecording : _resumeRecording,
            icon: Icon(
              isRecording ? Icons.pause : Icons.play_arrow,
              size: 32,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isRecording ? 'Pause' : 'Resume',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppTheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: IconButton(
            onPressed: onPressed,
            icon: Icon(icon, color: color),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppTheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Color _getRecordingColor(RecordingState state) {
    switch (state) {
      case RecordingState.recording:
        return AppTheme.recording;
      case RecordingState.paused:
        return AppTheme.paused;
      case RecordingState.stopping:
        return AppTheme.warning;
      case RecordingState.error:
        return AppTheme.error;
      default:
        return AppTheme.onSurfaceVariant;
    }
  }

  IconData _getRecordingIcon(RecordingState state) {
    switch (state) {
      case RecordingState.recording:
        return Icons.mic;
      case RecordingState.paused:
        return Icons.pause;
      case RecordingState.stopping:
        return Icons.stop;
      case RecordingState.error:
        return Icons.error;
      default:
        return Icons.mic_off;
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _pauseRecording() {
    final appState = context.read<AppState>();
    appState.pauseRecording();
    HapticFeedback.lightImpact();
  }

  void _resumeRecording() {
    final appState = context.read<AppState>();
    appState.resumeRecording();
    HapticFeedback.lightImpact();
  }

  void _rewind() {
    // TODO: Implement rewind functionality
    HapticFeedback.selectionClick();
  }

  void _forward() {
    // TODO: Implement forward functionality
    HapticFeedback.selectionClick();
  }

  void _showExitDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit Recording'),
        content: const Text('Are you sure you want to exit? Your recording will be saved.'),
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
            child: const Text('Exit'),
          ),
        ],
      ),
    );
  }

  void _stopRecording() {
    final appState = context.read<AppState>();
    appState.stopRecording();
    HapticFeedback.mediumImpact();
    
    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Recording saved successfully'),
        backgroundColor: AppTheme.success,
        action: SnackBarAction(
          label: 'View',
          textColor: Colors.white,
          onPressed: () {
            // TODO: Navigate to playback
          },
        ),
      ),
    );
    
    // Navigate back
    Navigator.pop(context);
  }
}
