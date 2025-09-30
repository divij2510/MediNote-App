import 'package:flutter/material.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  // Show success notification for offline upload
  static void showOfflineUploadSuccess(BuildContext context, int chunkCount) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.cloud_done, color: Colors.white),
            const SizedBox(width: 8),
            Text('Successfully uploaded $chunkCount offline chunks'),
          ],
        ),
        backgroundColor: Colors.green[700],
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // Show error notification for offline upload
  static void showOfflineUploadError(BuildContext context, String error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text('Failed to upload offline chunks: $error')),
          ],
        ),
        backgroundColor: Colors.red[700],
        duration: const Duration(seconds: 5),
      ),
    );
  }

  // Show offline recording started notification
  static void showOfflineRecordingStarted(BuildContext context, String sessionId) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.wifi_off, color: Colors.white),
            const SizedBox(width: 8),
            Text('Recording offline - Session: $sessionId'),
          ],
        ),
        backgroundColor: Colors.orange[700],
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // Show network restored notification
  static void showNetworkRestored(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.wifi, color: Colors.white),
            const SizedBox(width: 8),
            const Text('Network restored - Uploading offline chunks...'),
          ],
        ),
        backgroundColor: Colors.blue[700],
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
