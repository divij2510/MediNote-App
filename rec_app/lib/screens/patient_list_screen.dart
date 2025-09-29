import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/patient.dart';
import '../models/session.dart';
import '../services/api_service.dart';
import 'simple_recording_screen.dart';
import 'audio_playback_screen.dart';

class PatientListScreen extends StatefulWidget {
  const PatientListScreen({super.key});

  @override
  State<PatientListScreen> createState() => _PatientListScreenState();
}

class _PatientListScreenState extends State<PatientListScreen> {
  List<Patient> _patients = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  final TextEditingController _searchController = TextEditingController();
  List<Patient> _filteredPatients = [];

  @override
  void initState() {
    super.initState();
    _loadPatients();
    _searchController.addListener(_filterPatients);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPatients() async {
    final apiService = context.read<ApiService>();

    // Use hardcoded user ID
    final userId = ApiService.hardcodedUserId;

    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final patients = await apiService.getPatients(userId);

      setState(() {
        _patients = patients;
        _filteredPatients = patients;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _filterPatients() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredPatients = _patients.where((patient) {
        return patient.name.toLowerCase().contains(query) ||
            (patient.email?.toLowerCase().contains(query) ?? false);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Patient'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadPatients,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search patients...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),

          // Patient list
          Expanded(
            child: _buildPatientList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddPatientDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildPatientList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error, size: 64, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(
              'Error loading patients',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(_error!),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadPatients,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_filteredPatients.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isEmpty
                  ? 'No patients found'
                  : 'No patients match your search',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _showAddPatientDialog(),
              child: const Text('Add First Patient'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPatients,
      child: ListView.builder(
        itemCount: _filteredPatients.length,
        itemBuilder: (context, index) {
          final patient = _filteredPatients[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).primaryColor,
                child: Text(
                  patient.name.isNotEmpty ? patient.name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(
                patient.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (patient.pronouns != null)
                    Text('Pronouns: ${patient.pronouns}'),
                  if (patient.email != null)
                    Text(patient.email!),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.history),
                    onPressed: () => _showPatientSessions(patient),
                    tooltip: 'View Sessions',
                  ),
                  const Icon(Icons.arrow_forward_ios),
                ],
              ),
              onTap: () => _selectPatient(patient),
            ),
          );
        },
      ),
    );
  }

  void _selectPatient(Patient patient) {
    // Create a session for real-time recording
    final session = RecordingSession(
      id: '', // Will be set by API
      patientId: patient.id,
      userId: ApiService.hardcodedUserId,
      patientName: patient.name,
      status: 'recording',
      startTime: DateTime.now(),
    );
    
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SimpleRecordingScreen(session: session),
            ),
          );
  }

  Future<void> _showAddPatientDialog() async {
    final nameController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Patient'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Patient Name',
                hintText: 'Enter patient name',
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result == true && nameController.text.trim().isNotEmpty) {
      await _addPatient(nameController.text.trim());
    }
  }

  Future<void> _addPatient(String name) async {
    final apiService = context.read<ApiService>();

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final userId = ApiService.hardcodedUserId;
      final patient = await apiService.addPatient(name, userId);

      if (patient != null) {
        setState(() {
          _patients.add(patient);
          _filterPatients();
        });

        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Patient "$name" added successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('Failed to add patient');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding patient: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _showPatientSessions(Patient patient) async {
    final apiService = context.read<ApiService>();
    
    try {
      final sessions = await apiService.getPatientSessions(patient.id);
      
      if (!mounted) return;
      
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          minChildSize: 0.5,
          builder: (context, scrollController) => Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sessions for ${patient.name}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: sessions.isEmpty
                      ? const Center(
                          child: Text('No sessions found for this patient'),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: sessions.length,
                          itemBuilder: (context, index) {
                            final session = sessions[index];
                            return Card(
                              child: ListTile(
                                leading: Icon(
                                  _getSessionIcon(session.status),
                                  color: _getSessionColor(session.status),
                                ),
                                title: Text(
                                  session.sessionTitle ?? 'Session ${index + 1}',
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Status: ${session.status}'),
                                    Text('Start: ${_formatDateTime(session.startTime)}'),
                                    if (session.endTime != null)
                                      Text('End: ${_formatDateTime(session.endTime!)}'),
                                  ],
                                ),
                                trailing: session.status == 'completed'
                                    ? IconButton(
                                        icon: const Icon(Icons.play_arrow),
                                        onPressed: () {
                                          Navigator.pop(context);
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => AudioPlaybackScreen(
                                                session: session,
                                              ),
                                            ),
                                          );
                                        },
                                        tooltip: 'Play Recording',
                                      )
                                    : null,
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading sessions: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  IconData _getSessionIcon(String status) {
    switch (status) {
      case 'recording':
        return Icons.fiber_manual_record;
      case 'paused':
        return Icons.pause;
      case 'completed':
        return Icons.check_circle;
      case 'processing':
        return Icons.hourglass_empty;
      default:
        return Icons.radio_button_unchecked;
    }
  }

  Color _getSessionColor(String status) {
    switch (status) {
      case 'recording':
        return Colors.red;
      case 'paused':
        return Colors.orange;
      case 'completed':
        return Colors.green;
      case 'processing':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}