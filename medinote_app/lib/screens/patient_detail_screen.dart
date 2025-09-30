import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/patient_provider.dart';
import '../models/patient.dart';
import '../services/audio_recording_service.dart';
import '../main.dart';
import 'add_patient_screen.dart';
import 'recording_screen.dart';

class PatientDetailScreen extends StatefulWidget {
  final Patient patient;

  const PatientDetailScreen({super.key, required this.patient});

  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen> with RouteAware {
  List<Map<String, dynamic>> _audioSessions = [];
  bool _isLoadingSessions = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to route changes
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      MediNoteApp.routeObserver.subscribe(this, route);
    }
    // Load audio sessions here instead of initState
    _loadAudioSessions();
  }

  @override
  void didPopNext() {
    // Called when the user returns to this screen from another screen
    super.didPopNext();
    _loadAudioSessions(); // Refresh the recordings list
  }

  @override
  void dispose() {
    MediNoteApp.routeObserver.unsubscribe(this);
    super.dispose();
  }

  Future<void> _loadAudioSessions() async {
    setState(() {
      _isLoadingSessions = true;
    });

    try {
      final audioService = context.read<AudioRecordingService>();
      final sessions = await audioService.getPatientAudioSessions(widget.patient.id!);
      if (mounted) {
        setState(() {
          _audioSessions = sessions.reversed.toList(); // Reverse to show newest first
          _isLoadingSessions = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingSessions = false;
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading audio sessions: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.patient.name),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAudioSessions,
            tooltip: 'Refresh recordings',
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AddPatientScreen(
                    patient: widget.patient,
                    isEditing: true,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Patient Info Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Patient Information',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildInfoRow(Icons.person, 'Name', widget.patient.name),
                    if (widget.patient.age != null)
                      _buildInfoRow(Icons.cake, 'Age', widget.patient.age.toString()),
                    if (widget.patient.phone != null)
                      _buildInfoRow(Icons.phone, 'Phone', widget.patient.phone!),
                    if (widget.patient.email != null)
                      _buildInfoRow(Icons.email, 'Email', widget.patient.email!),
                    if (widget.patient.medicalHistory != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Medical History',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.patient.medicalHistory!,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Audio Recording Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Audio Recordings',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => RecordingScreen(patient: widget.patient),
                              ),
                            );
                          },
                          icon: const Icon(Icons.mic),
                          label: const Text('New Recording'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red[600],
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildAudioSessionsSection(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Action Buttons
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Actions',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => AddPatientScreen(
                                    patient: widget.patient,
                                    isEditing: true,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.edit),
                            label: const Text('Edit Patient'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue[700],
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              _showDeleteDialog();
                            },
                            icon: const Icon(Icons.delete),
                            label: const Text('Delete Patient'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red[700],
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildAudioSessionsSection() {
    if (_isLoadingSessions) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_audioSessions.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Icon(
              Icons.mic_off,
              size: 48,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 8),
            Text(
              'No recordings yet',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 200, // Fixed height for scrollable area
      child: ListView.builder(
        itemCount: _audioSessions.length,
        itemBuilder: (context, index) {
          final session = _audioSessions[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.audiotrack,
                  color: Colors.blue[600],
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Session ${index + 1}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      '${_formatFileSize(session['file_size'] ?? 0)} • ${_formatDate(DateTime.parse(session['created_at'] ?? DateTime.now().toIso8601String()))}',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Consumer<AudioRecordingService>(
                builder: (context, audioService, child) {
                  final sessionId = session['session_id']?.toString() ?? '';
                  final isPlaying = audioService.currentlyPlayingId == sessionId.hashCode;
                  final isLoading = audioService.isLoadingAudio && audioService.currentlyPlayingId == sessionId.hashCode;
                  
                  if (isLoading) {
                    return const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                      ),
                    );
                  }
                  
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Show resume button for incomplete sessions
                      if (session['is_completed'] == 0)
                        IconButton(
                          icon: Icon(
                            Icons.restore,
                            color: Colors.orange[600],
                          ),
                          onPressed: () => _resumeIncompleteSession(sessionId),
                          tooltip: 'Resume recording',
                        ),
                      // Show play/pause button for all sessions
                      IconButton(
                        icon: Icon(
                          isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.blue[600],
                        ),
                        onPressed: () => _toggleBackendPlayback(sessionId, audioService),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
        },
      ),
    );
  }

  void _toggleBackendPlayback(String sessionId, AudioRecordingService audioService) async {
    try {
      if (audioService.isPlaying) {
        await audioService.stopAudioFromBackend();
      } else {
        await audioService.playAudioFromBackend(sessionId);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error playing audio: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _resumeIncompleteSession(String sessionId) async {
    try {
      // Navigate to recording screen to resume the session
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RecordingScreen(
            patient: widget.patient,
            resumeSessionId: sessionId,
          ),
        ),
      );
      
      // Show message that user should start recording to resume
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Resuming session: $sessionId'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to resume session: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Patient'),
        content: Text('Are you sure you want to delete ${widget.patient.name}? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              // Close the dialog first
              Navigator.pop(context);
              
              try {
                await context.read<PatientProvider>().deletePatient(widget.patient.id!);
                
                // Check if widget is still mounted before navigating
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Patient deleted successfully'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                // Handle error if widget is still mounted
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error deleting patient: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Delete'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ),
    );
  }
}