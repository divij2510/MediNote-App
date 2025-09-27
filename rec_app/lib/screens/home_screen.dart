import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/permission_service.dart';
import '../services/api_service.dart';
import '../services/audio_service.dart';
import '../services/storage_service.dart';
import 'patient_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    final permissionService = context.read<PermissionService>();
    final apiService = context.read<ApiService>();
    final audioService = context.read<AudioService>();
    final storageService = context.read<StorageService>();

    // Initialize services
    await storageService.initialize();
    audioService.initialize(apiService, storageService);

    // Check permissions
    await permissionService.checkAllPermissions();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MediNote Recorder'),
        centerTitle: true,
      ),
      body: Consumer<PermissionService>(
        builder: (context, permissionService, child) {
          if (permissionService.isCheckingPermissions) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (!permissionService.allPermissionsGranted) {
            return _buildPermissionRequest(permissionService);
          }

          return _buildMainContent();
        },
      ),
    );
  }

  Widget _buildPermissionRequest(PermissionService permissionService) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.mic,
            size: 80,
            color: Colors.grey,
          ),
          const SizedBox(height: 24),
          const Text(
            'Permissions Required',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'This app needs access to your microphone to record medical consultations.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 32),
          Column(
            children: [
              _buildPermissionTile(
                icon: Icons.mic,
                title: 'Microphone',
                subtitle: 'Record audio during consultations',
                isGranted: permissionService.microphoneGranted,
                onTap: () => permissionService.requestMicrophonePermission(),
              ),
              const SizedBox(height: 16),
              _buildPermissionTile(
                icon: Icons.notifications,
                title: 'Notifications',
                subtitle: 'Keep recording active in background',
                isGranted: permissionService.notificationGranted,
                onTap: () => permissionService.requestNotificationPermission(),
              ),
            ],
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: permissionService.allPermissionsGranted
                  ? null
                  : () => permissionService.requestAllPermissions(),
              child: const Text('Grant All Permissions'),
            ),
          ),
          if (!permissionService.allPermissionsGranted) ...[
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => permissionService.openAppSettings(),
              child: const Text('Open App Settings'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPermissionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isGranted,
    required VoidCallback onTap,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(
          icon,
          color: isGranted ? Colors.green : Colors.orange,
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Icon(
          isGranted ? Icons.check_circle : Icons.error,
          color: isGranted ? Colors.green : Colors.orange,
        ),
        onTap: isGranted ? null : onTap,
      ),
    );
  }

  Widget _buildMainContent() {
    return Consumer3<ApiService, AudioService, StorageService>(
      builder: (context, apiService, audioService, storageService, child) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Quick stats card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Today\'s Summary',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildStatTile(
                              'Failed Chunks',
                              '${storageService.failedChunks.length}',
                              Icons.cloud_off,
                              Colors.orange,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildStatTile(
                              'Sessions',
                              '${storageService.cachedSessions.length}',
                              Icons.history,
                              Colors.blue,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Action buttons
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const PatientListScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.people),
                  label: const Text('Select Patient'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    textStyle: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Network status
              Card(
                color: apiService.isConnected ? Colors.green.shade50 : Colors.red.shade50,
                child: ListTile(
                  leading: Icon(
                    apiService.isConnected ? Icons.cloud_done : Icons.cloud_off,
                    color: apiService.isConnected ? Colors.green : Colors.red,
                  ),
                  title: Text(
                    apiService.isConnected ? 'Connected' : 'Offline',
                    style: TextStyle(
                      color: apiService.isConnected ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    apiService.isConnected
                        ? 'Ready to upload recordings'
                        : 'Recordings will be queued for upload',
                  ),
                ),
              ),

              // Failed chunks retry section
              if (storageService.failedChunks.isNotEmpty) ...[
                const SizedBox(height: 16),
                Card(
                  color: Colors.orange.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.warning, color: Colors.orange.shade700),
                            const SizedBox(width: 8),
                            Text(
                              'Failed Uploads',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${storageService.failedChunks.length} audio chunks failed to upload',
                          style: TextStyle(color: Colors.orange.shade700),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: apiService.isConnected
                                    ? () => audioService.retryFailedChunks()
                                    : null,
                                child: const Text('Retry Upload'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () => _showClearChunksDialog(storageService),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Clear'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatTile(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _showClearChunksDialog(StorageService storageService) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Failed Chunks'),
        content: const Text(
          'This will permanently delete all failed audio chunks. '
              'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (result == true) {
      await storageService.clearFailedChunks();
    }
  }
}