import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/offline_recording_service.dart';

class OfflineRecordingStatus extends StatelessWidget {
  const OfflineRecordingStatus({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<OfflineRecordingService>(
      builder: (context, offlineService, child) {
        if (!offlineService.isOfflineRecording) {
          return const SizedBox.shrink();
        }
        
        final status = offlineService.getOfflineStatus();
        
        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange[50],
            border: Border.all(color: Colors.orange[300]!),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                Icons.wifi_off,
                color: Colors.orange[700],
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Recording Offline',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[700],
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Session: ${status['session_id']}',
                      style: TextStyle(
                        color: Colors.orange[600],
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      'Chunks stored: ${status['chunk_count']}',
                      style: TextStyle(
                        color: Colors.orange[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.cloud_off,
                color: Colors.orange[700],
                size: 20,
              ),
            ],
          ),
        );
      },
    );
  }
}
