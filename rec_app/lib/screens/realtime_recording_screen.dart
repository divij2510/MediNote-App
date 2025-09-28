import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';

import '../models/session.dart';
import '../services/realtime_audio_service.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../widgets/audio_visualizer.dart';
import '../widgets/recording_controls.dart';

class RealtimeRecordingScreen extends StatefulWidget {
  final RecordingSession session;

  const RealtimeRecordingScreen({
    Key? key,
    required this.session,
  }) : super(key: key);

  @override
  State<RealtimeRecordingScreen> createState() => _RealtimeRecordingScreenState();
}

class _RealtimeRecordingScreenState extends State<RealtimeRecordingScreen>
    with TickerProviderStateMixin {
  late RealtimeAudioService _audioService;
  late ApiService _apiService;
  late StorageService _storageService;
  
  late AnimationController _pulseController;
  late AnimationController _waveController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _waveAnimation;
  
  bool _isInitialized = false;
  bool _showGainControl = false;
  
  @override
  void initState() {
    super.initState();
    _initializeServices();
    _initializeAnimations();
    _startRecording();
  }
  
  void _initializeServices() {
    _apiService = Provider.of<ApiService>(context, listen: false);
    _storageService = Provider.of<StorageService>(context, listen: false);
    _audioService = Provider.of<RealtimeAudioService>(context, listen: false);
  }
  
  void _initializeAnimations() {
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
        if (await Vibration.hasVibrator() ?? false) {
          Vibration.vibrate(duration: 100);
        }
        
        // System sound
        SystemSound.play(SystemSoundType.click);
      } else {
        _showErrorDialog('Failed to start recording session');
      }
    } catch (e) {
      _showErrorDialog('Error starting recording: $e');
    }
  }
  
  @override
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          'Recording - ${widget.session.patientName}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _showGainControl ? _hideGainControl : _showGainControl,
            icon: Icon(_showGainControl ? Icons.tune : Icons.settings),
            tooltip: 'Gain Control',
          ),
        ],
      ),
      body: Consumer<RealtimeAudioService>(
        builder: (context, audioService, child) {
          if (!_isInitialized) {
            return _buildLoadingScreen();
          }
          
          return _buildRecordingScreen(audioService);
        },
      ),
    );
  }
  
  Widget _buildLoadingScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
          ),
          const SizedBox(height: 24),
          Text(
            'Initializing Real-time Streaming...',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Connecting to server...',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildRecordingScreen(RealtimeAudioService audioService) {
    return Column(
      children: [
        // Status bar
        _buildStatusBar(audioService),
        
        // Main recording area
        Expanded(
          child: _buildMainRecordingArea(audioService),
        ),
        
        // Gain control (if visible)
        if (_showGainControl) _buildGainControl(audioService),
        
        // Controls
        _buildControls(audioService),
      ],
    );
  }
  
  Widget _buildStatusBar(RealtimeAudioService audioService) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        border: Border(
          bottom: BorderSide(color: Colors.grey[800]!, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Status indicator
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _getStatusColor(audioService.streamingState),
            ),
          ),
          const SizedBox(width: 12),
          
          // Status text
          Expanded(
            child: Text(
              _getStatusText(audioService.streamingState),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          
          // Duration
          Text(
            _formatDuration(audioService.streamingDuration),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildMainRecordingArea(RealtimeAudioService audioService) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Audio visualizer
          Expanded(
            flex: 3,
            child: _buildAudioVisualizer(audioService),
          ),
          
          const SizedBox(height: 32),
          
          // Patient info
          Expanded(
            flex: 1,
            child: _buildPatientInfo(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildAudioVisualizer(RealtimeAudioService audioService) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: audioService.isStreaming ? _pulseAnimation.value : 1.0,
          child: AudioVisualizer(
            amplitude: audioService.currentAmplitude,
            isRecording: audioService.isStreaming,
            color: Colors.red,
            barCount: 20,
            height: 200,
          ),
        );
      },
    );
  }
  
  Widget _buildPatientInfo() {
    return Card(
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Patient: ${widget.session.patientName}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Session ID: ${widget.session.id}',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildGainControl(RealtimeAudioService audioService) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        border: Border(
          top: BorderSide(color: Colors.grey[800]!, width: 1),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.volume_up, color: Colors.white),
              const SizedBox(width: 8),
              const Text(
                'Gain Control',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '${(audioService.gainLevel * 100).round()}%',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Slider(
            value: audioService.gainLevel,
            min: 0.1,
            max: 3.0,
            divisions: 29,
            activeColor: Colors.red,
            inactiveColor: Colors.grey[600],
            onChanged: (value) {
              audioService.setGainLevel(value);
            },
          ),
        ],
      ),
    );
  }
  
  Widget _buildControls(RealtimeAudioService audioService) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        border: Border(
          top: BorderSide(color: Colors.grey[800]!, width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Pause/Resume button
          _buildControlButton(
            icon: audioService.isPaused ? Icons.play_arrow : Icons.pause,
            label: audioService.isPaused ? 'Resume' : 'Pause',
            color: audioService.isPaused ? Colors.green : Colors.orange,
            onPressed: audioService.isPaused
                ? () => _resumeRecording()
                : () => _pauseRecording(),
          ),
          
          // Stop button
          _buildControlButton(
            icon: Icons.stop,
            label: 'Stop',
            color: Colors.red,
            onPressed: () => _stopRecording(),
          ),
          
          // Settings button
          _buildControlButton(
            icon: Icons.settings,
            label: 'Settings',
            color: Colors.blue,
            onPressed: _showSettings,
          ),
        ],
      ),
    );
  }
  
  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
          child: IconButton(
            onPressed: onPressed,
            icon: Icon(icon, color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
  
  Color _getStatusColor(StreamingState state) {
    switch (state) {
      case StreamingState.idle:
        return Colors.grey;
      case StreamingState.connecting:
        return Colors.orange;
      case StreamingState.streaming:
        return Colors.green;
      case StreamingState.paused:
        return Colors.orange;
      case StreamingState.reconnecting:
        return Colors.orange;
      case StreamingState.error:
        return Colors.red;
      case StreamingState.completed:
        return Colors.blue;
    }
  }
  
  String _getStatusText(StreamingState state) {
    switch (state) {
      case StreamingState.idle:
        return 'Ready';
      case StreamingState.connecting:
        return 'Connecting...';
      case StreamingState.streaming:
        return 'Streaming Live';
      case StreamingState.paused:
        return 'Paused';
      case StreamingState.reconnecting:
        return 'Reconnecting...';
      case StreamingState.error:
        return 'Error';
      case StreamingState.completed:
        return 'Completed';
    }
  }
  
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  
  void _showGainControl() {
    setState(() {
      _showGainControl = true;
    });
  }
  
  void _hideGainControl() {
    setState(() {
      _showGainControl = false;
    });
  }
  
  Future<void> _pauseRecording() async {
    try {
      await _audioService.pauseStreaming();
      
      // Haptic feedback
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(duration: 50);
      }
    } catch (e) {
      _showErrorDialog('Error pausing recording: $e');
    }
  }
  
  Future<void> _resumeRecording() async {
    try {
      await _audioService.resumeStreaming();
      
      // Haptic feedback
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(duration: 50);
      }
    } catch (e) {
      _showErrorDialog('Error resuming recording: $e');
    }
  }
  
  Future<void> _stopRecording() async {
    try {
      await _audioService.stopStreaming();
      
      // Haptic feedback
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(duration: 200);
      }
      
      // Navigate back
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      _showErrorDialog('Error stopping recording: $e');
    }
  }
  
  void _showSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Recording Settings',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            
            // Gain control
            ListTile(
              leading: const Icon(Icons.volume_up, color: Colors.white),
              title: const Text(
                'Gain Control',
                style: TextStyle(color: Colors.white),
              ),
              trailing: Switch(
                value: _showGainControl,
                onChanged: (value) {
                  setState(() {
                    _showGainControl = value;
                  });
                  Navigator.pop(context);
                },
              ),
            ),
            
            // Bluetooth settings
            ListTile(
              leading: const Icon(Icons.bluetooth, color: Colors.white),
              title: const Text(
                'Bluetooth Audio',
                style: TextStyle(color: Colors.white),
              ),
              trailing: Text(
                _audioService.isBluetoothConnected ? 'Connected' : 'Not Connected',
                style: const TextStyle(color: Colors.grey),
              ),
            ),
            
            // Wired headset
            ListTile(
              leading: const Icon(Icons.headphones, color: Colors.white),
              title: const Text(
                'Wired Headset',
                style: TextStyle(color: Colors.white),
              ),
              trailing: Text(
                _audioService.isWiredHeadsetConnected ? 'Connected' : 'Not Connected',
                style: const TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Error',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
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
