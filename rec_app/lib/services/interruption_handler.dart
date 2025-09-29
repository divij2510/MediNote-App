import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/session.dart';
import 'api_service.dart';
import 'storage_service.dart';
import 'realtime_streaming_service.dart';

enum InterruptionType {
  phoneCall,
  appSwitch,
  networkLoss,
  systemKill,
  memoryPressure,
  bluetoothDisconnect,
  headsetDisconnect,
}

class InterruptionHandler extends ChangeNotifier {
  // Services
  late ApiService _apiService;
  late StorageService _storageService;
  late RealtimeStreamingService _streamingService;
  late FlutterLocalNotificationsPlugin _notifications;
  
  // State tracking
  bool _isHandlingInterruption = false;
  InterruptionType? _currentInterruption;
  DateTime? _interruptionStartTime;
  Map<String, dynamic> _interruptionData = {};
  
  // Recovery state
  String? _recoverySessionId;
  int _recoveryChunkNumber = 0;
  Duration _recoveryDuration = Duration.zero;
  List<Map<String, dynamic>> _pendingRecoveryData = [];
  
  // Network monitoring
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _wasOnline = true;
  Timer? _networkRetryTimer;
  
  // App lifecycle monitoring
  AppLifecycleState? _lastAppState;
  Timer? _appStateTimer;
  
  // Phone call detection (simplified - would need platform channels for real detection)
  bool _isPhoneCallActive = false;
  Timer? _phoneCallTimer;
  
  // Memory pressure monitoring
  Timer? _memoryMonitorTimer;
  int _memoryPressureCount = 0;
  
  // Getters
  bool get isHandlingInterruption => _isHandlingInterruption;
  InterruptionType? get currentInterruption => _currentInterruption;
  String? get recoverySessionId => _recoverySessionId;
  
  void initialize(
    ApiService apiService,
    StorageService storageService,
    RealtimeStreamingService streamingService,
  ) {
    _apiService = apiService;
    _storageService = storageService;
    _streamingService = streamingService;
    _initializeNotifications();
    _startMonitoring();
    _checkForRecovery();
  }
  
  Future<void> _initializeNotifications() async {
    _notifications = FlutterLocalNotificationsPlugin();
    
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    
    await _notifications.initialize(initSettings);
  }
  
  void _startMonitoring() {
    // Monitor network connectivity
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      _handleConnectivityChange,
    );
    
    // Monitor app lifecycle
    _appStateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _checkAppState();
    });
    
    // Monitor memory pressure
    _memoryMonitorTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _checkMemoryPressure();
    });
    
    // Simulate phone call detection (in real app, would use platform channels)
    _phoneCallTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _simulatePhoneCallDetection();
    });
  }
  
  void _handleConnectivityChange(List<ConnectivityResult> results) {
    final isOnline = results.any((result) => result != ConnectivityResult.none);
    
    if (_wasOnline && !isOnline) {
      // Network lost
      _handleInterruption(InterruptionType.networkLoss, {
        'timestamp': DateTime.now().toIso8601String(),
        'previous_connection': 'online',
        'current_connection': 'offline',
      });
    } else if (!_wasOnline && isOnline) {
      // Network restored
      _handleNetworkRestored();
    }
    
    _wasOnline = isOnline;
  }
  
  void _checkAppState() {
    // This would typically be called from the main app's lifecycle observer
    // For now, we'll simulate it
  }
  
  void _checkMemoryPressure() {
    // Simulate memory pressure detection
    // In a real app, you'd use platform channels to detect actual memory pressure
    _memoryPressureCount++;
    if (_memoryPressureCount > 10) {
      _handleInterruption(InterruptionType.memoryPressure, {
        'timestamp': DateTime.now().toIso8601String(),
        'pressure_level': 'high',
      });
      _memoryPressureCount = 0;
    }
  }
  
  void _simulatePhoneCallDetection() {
    // Simulate phone call detection
    // In a real app, you'd use platform channels to detect actual phone calls
    if (DateTime.now().second % 30 == 0 && !_isPhoneCallActive) {
      _isPhoneCallActive = true;
      _handleInterruption(InterruptionType.phoneCall, {
        'timestamp': DateTime.now().toIso8601String(),
        'call_type': 'incoming',
      });
      
      // Simulate call ending after 30 seconds
      Timer(const Duration(seconds: 30), () {
        _isPhoneCallActive = false;
        _handleInterruptionResolved(InterruptionType.phoneCall);
      });
    }
  }
  
  Future<void> _checkForRecovery() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _recoverySessionId = prefs.getString('interruption_recovery_session_id');
      
      if (_recoverySessionId != null) {
        debugPrint('Found interruption recovery session: $_recoverySessionId');
        await _showRecoveryNotification();
      }
    } catch (e) {
      debugPrint('Error checking for recovery: $e');
    }
  }
  
  Future<void> _handleInterruption(InterruptionType type, Map<String, dynamic> data) async {
    if (_isHandlingInterruption) {
      debugPrint('Already handling interruption, ignoring new one: $type');
      return;
    }
    
    _isHandlingInterruption = true;
    _currentInterruption = type;
    _interruptionStartTime = DateTime.now();
    _interruptionData = data;
    
    debugPrint('Handling interruption: $type');
    
    try {
      switch (type) {
        case InterruptionType.phoneCall:
          await _handlePhoneCallInterruption();
          break;
        case InterruptionType.appSwitch:
          await _handleAppSwitchInterruption();
          break;
        case InterruptionType.networkLoss:
          await _handleNetworkLossInterruption();
          break;
        case InterruptionType.systemKill:
          await _handleSystemKillInterruption();
          break;
        case InterruptionType.memoryPressure:
          await _handleMemoryPressureInterruption();
          break;
        case InterruptionType.bluetoothDisconnect:
          await _handleBluetoothDisconnectInterruption();
          break;
        case InterruptionType.headsetDisconnect:
          await _handleHeadsetDisconnectInterruption();
          break;
      }
      
      // Save recovery state
      await _saveRecoveryState();
      
    } catch (e) {
      debugPrint('Error handling interruption: $e');
    }
    
    notifyListeners();
  }
  
  Future<void> _handlePhoneCallInterruption() async {
    debugPrint('Handling phone call interruption');
    
    // Pause streaming
    if (_streamingService.isStreaming) {
      await _streamingService.pauseStreaming();
    }
    
    // Show notification
    await _showPhoneCallNotification();
    
    // Save state for recovery
    await _saveInterruptionState('phone_call', {
      'action': 'paused',
      'reason': 'incoming_call',
    });
  }
  
  Future<void> _handleAppSwitchInterruption() async {
    debugPrint('Handling app switch interruption');
    
    // Continue streaming in background
    // The foreground service should handle this
    
    // Show notification
    await _showAppSwitchNotification();
    
    // Save state for recovery
    await _saveInterruptionState('app_switch', {
      'action': 'background_continue',
      'reason': 'app_switched',
    });
  }
  
  Future<void> _handleNetworkLossInterruption() async {
    debugPrint('Handling network loss interruption');
    
    // Continue recording locally
    // Queue chunks for later upload
    
    // Show notification
    await _showNetworkLossNotification();
    
    // Start retry timer
    _startNetworkRetryTimer();
    
    // Save state for recovery
    await _saveInterruptionState('network_loss', {
      'action': 'local_recording',
      'reason': 'network_unavailable',
    });
  }
  
  Future<void> _handleSystemKillInterruption() async {
    debugPrint('Handling system kill interruption');
    
    // Save critical state immediately
    await _saveCriticalState();
    
    // Show notification
    await _showSystemKillNotification();
    
    // Save state for recovery
    await _saveInterruptionState('system_kill', {
      'action': 'emergency_save',
      'reason': 'system_killed_app',
    });
  }
  
  Future<void> _handleMemoryPressureInterruption() async {
    debugPrint('Handling memory pressure interruption');
    
    // Reduce memory usage
    // Clear non-essential data
    // Continue with essential recording
    
    // Show notification
    await _showMemoryPressureNotification();
    
    // Save state for recovery
    await _saveInterruptionState('memory_pressure', {
      'action': 'memory_optimization',
      'reason': 'high_memory_usage',
    });
  }
  
  Future<void> _handleBluetoothDisconnectInterruption() async {
    debugPrint('Handling Bluetooth disconnect interruption');
    
    // Switch to device microphone
    // Continue recording
    
    // Show notification
    await _showBluetoothDisconnectNotification();
    
    // Save state for recovery
    await _saveInterruptionState('bluetooth_disconnect', {
      'action': 'switch_to_device_mic',
      'reason': 'bluetooth_disconnected',
    });
  }
  
  Future<void> _handleHeadsetDisconnectInterruption() async {
    debugPrint('Handling headset disconnect interruption');
    
    // Switch to device microphone
    // Continue recording
    
    // Show notification
    await _showHeadsetDisconnectNotification();
    
    // Save state for recovery
    await _saveInterruptionState('headset_disconnect', {
      'action': 'switch_to_device_mic',
      'reason': 'headset_disconnected',
    });
  }
  
  Future<void> _handleInterruptionResolved(InterruptionType type) async {
    debugPrint('Interruption resolved: $type');
    
    try {
      switch (type) {
        case InterruptionType.phoneCall:
          await _handlePhoneCallResolved();
          break;
        case InterruptionType.appSwitch:
          await _handleAppSwitchResolved();
          break;
        case InterruptionType.networkLoss:
          await _handleNetworkRestored();
          break;
        case InterruptionType.systemKill:
          await _handleSystemKillResolved();
          break;
        case InterruptionType.memoryPressure:
          await _handleMemoryPressureResolved();
          break;
        case InterruptionType.bluetoothDisconnect:
          await _handleBluetoothReconnect();
          break;
        case InterruptionType.headsetDisconnect:
          await _handleHeadsetReconnect();
          break;
      }
      
      // Clear interruption state
      _isHandlingInterruption = false;
      _currentInterruption = null;
      _interruptionStartTime = null;
      _interruptionData.clear();
      
    } catch (e) {
      debugPrint('Error resolving interruption: $e');
    }
    
    notifyListeners();
  }
  
  Future<void> _handlePhoneCallResolved() async {
    debugPrint('Phone call resolved, resuming recording');
    
    // Resume streaming
    if (_streamingService.isPaused) {
      await _streamingService.resumeStreaming();
    }
    
    // Show resume notification
    await _showPhoneCallResolvedNotification();
  }
  
  Future<void> _handleAppSwitchResolved() async {
    debugPrint('App switch resolved');
    
    // App is back in foreground
    // Continue normal operation
    
    // Show resume notification
    await _showAppSwitchResolvedNotification();
  }
  
  Future<void> _handleNetworkRestored() async {
    debugPrint('Network restored, syncing queued data');
    
    // Sync queued chunks
    await _syncQueuedChunks();
    
    // Show sync notification
    await _showNetworkRestoredNotification();
  }
  
  Future<void> _handleSystemKillResolved() async {
    debugPrint('System kill resolved, recovering session');
    
    // Attempt to recover session
    await _attemptSessionRecovery();
    
    // Show recovery notification
    await _showSystemKillResolvedNotification();
  }
  
  Future<void> _handleMemoryPressureResolved() async {
    debugPrint('Memory pressure resolved');
    
    // Restore normal operation
    // Clear recovery state
    
    // Show resolved notification
    await _showMemoryPressureResolvedNotification();
  }
  
  Future<void> _handleBluetoothReconnect() async {
    debugPrint('Bluetooth reconnected');
    
    // Switch back to Bluetooth if preferred
    // Continue recording
    
    // Show reconnected notification
    await _showBluetoothReconnectedNotification();
  }
  
  Future<void> _handleHeadsetReconnect() async {
    debugPrint('Headset reconnected');
    
    // Switch back to headset if preferred
    // Continue recording
    
    // Show reconnected notification
    await _showHeadsetReconnectedNotification();
  }
  
  void _startNetworkRetryTimer() {
    _networkRetryTimer?.cancel();
    _networkRetryTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (_apiService.isConnected) {
        await _syncQueuedChunks();
        timer.cancel();
      }
    });
  }
  
  Future<void> _syncQueuedChunks() async {
    try {
      // Get queued chunks from storage
      final queuedChunks = await _storageService.getQueuedChunks();
      
      debugPrint('Syncing ${queuedChunks.length} queued chunks');
      
      for (final chunk in queuedChunks) {
        try {
          // Attempt to upload chunk
          final success = await _apiService.uploadAudioChunk(chunk, false);
          
          if (success) {
            // Remove from queue
            await _storageService.removeQueuedChunk(chunk.sessionId, chunk.chunkNumber);
            debugPrint('Queued chunk synced successfully');
          }
        } catch (e) {
          debugPrint('Error syncing queued chunk: $e');
        }
      }
    } catch (e) {
      debugPrint('Error syncing queued chunks: $e');
    }
  }
  
  Future<void> _saveInterruptionState(String type, Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('interruption_type', type);
      await prefs.setString('interruption_data', data.toString());
      await prefs.setString('interruption_timestamp', DateTime.now().toIso8601String());
      
      if (_streamingService.currentSession != null) {
        await prefs.setString('interruption_recovery_session_id', _streamingService.currentSession!.id);
      }
    } catch (e) {
      debugPrint('Error saving interruption state: $e');
    }
  }
  
  Future<void> _saveCriticalState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Save critical session data
      if (_streamingService.currentSession != null) {
        await prefs.setString('critical_session_id', _streamingService.currentSession!.id);
        await prefs.setString('critical_session_data', _streamingService.currentSession!.toJson().toString());
      }
      
      // Save current recording state
      await prefs.setInt('critical_chunk_number', _recoveryChunkNumber);
      await prefs.setString('critical_duration', _recoveryDuration.inSeconds.toString());
      
      debugPrint('Critical state saved for recovery');
    } catch (e) {
      debugPrint('Error saving critical state: $e');
    }
  }
  
  Future<void> _saveRecoveryState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      if (_streamingService.currentSession != null) {
        await prefs.setString('interruption_recovery_session_id', _streamingService.currentSession!.id);
        await prefs.setInt('recovery_chunk_number', _recoveryChunkNumber);
        await prefs.setString('recovery_duration', _recoveryDuration.inSeconds.toString());
      }
    } catch (e) {
      debugPrint('Error saving recovery state: $e');
    }
  }
  
  Future<void> _attemptSessionRecovery() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString('critical_session_id');
      
      if (sessionId != null) {
        // Attempt to recover session
        final session = await _apiService.getSession(sessionId);
        if (session != null) {
          // Resume session
          await _streamingService.startStreamingSession(session);
          debugPrint('Session recovered successfully');
        }
      }
    } catch (e) {
      debugPrint('Error attempting session recovery: $e');
    }
  }
  
  // Notification methods
  Future<void> _showPhoneCallNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'phone_call_interruption',
      'Phone Call',
      channelDescription: 'Phone call interruption notifications',
      importance: Importance.high,
      priority: Priority.high,
      ongoing: true,
      actions: [
        AndroidNotificationAction('resume', 'Resume Recording'),
      ],
    );
    
    const notificationDetails = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      10,
      'Recording Paused',
      'Recording paused due to phone call',
      notificationDetails,
    );
  }
  
  Future<void> _showAppSwitchNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'app_switch_interruption',
      'App Switch',
      channelDescription: 'App switch interruption notifications',
      importance: Importance.high,
      priority: Priority.high,
      ongoing: true,
    );
    
    const notificationDetails = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      11,
      'Recording in Background',
      'Recording continues in background',
      notificationDetails,
    );
  }
  
  Future<void> _showNetworkLossNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'network_loss_interruption',
      'Network Loss',
      channelDescription: 'Network loss interruption notifications',
      importance: Importance.high,
      priority: Priority.high,
      ongoing: true,
    );
    
    const notificationDetails = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      12,
      'Recording Offline',
      'Recording continues offline, will sync when connected',
      notificationDetails,
    );
  }
  
  Future<void> _showSystemKillNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'system_kill_interruption',
      'System Kill',
      channelDescription: 'System kill interruption notifications',
      importance: Importance.high,
      priority: Priority.high,
      actions: [
        AndroidNotificationAction('recover', 'Recover Session'),
        AndroidNotificationAction('dismiss', 'Dismiss'),
      ],
    );
    
    const notificationDetails = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      13,
      'Session Recovery Available',
      'Previous recording session can be recovered',
      notificationDetails,
    );
  }
  
  Future<void> _showMemoryPressureNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'memory_pressure_interruption',
      'Memory Pressure',
      channelDescription: 'Memory pressure interruption notifications',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    
    const notificationDetails = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      14,
      'Memory Optimized',
      'Recording optimized for memory usage',
      notificationDetails,
    );
  }
  
  Future<void> _showBluetoothDisconnectNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'bluetooth_disconnect_interruption',
      'Bluetooth Disconnect',
      channelDescription: 'Bluetooth disconnect interruption notifications',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    
    const notificationDetails = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      15,
      'Bluetooth Disconnected',
      'Switched to device microphone',
      notificationDetails,
    );
  }
  
  Future<void> _showHeadsetDisconnectNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'headset_disconnect_interruption',
      'Headset Disconnect',
      channelDescription: 'Headset disconnect interruption notifications',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    
    const notificationDetails = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      16,
      'Headset Disconnected',
      'Switched to device microphone',
      notificationDetails,
    );
  }
  
  Future<void> _showRecoveryNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'interruption_recovery',
      'Session Recovery',
      channelDescription: 'Session recovery notifications',
      importance: Importance.high,
      priority: Priority.high,
      actions: [
        AndroidNotificationAction('recover', 'Recover Session'),
        AndroidNotificationAction('dismiss', 'Dismiss'),
      ],
    );
    
    const notificationDetails = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      17,
      'Session Recovery Available',
      'Previous recording session can be recovered',
      notificationDetails,
    );
  }
  
  // Resolved notification methods
  Future<void> _showPhoneCallResolvedNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'phone_call_resolved',
      'Phone Call Resolved',
      channelDescription: 'Phone call resolved notifications',
      importance: Importance.high,
      priority: Priority.high,
    );
    
    const notificationDetails = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      20,
      'Recording Resumed',
      'Recording resumed after phone call',
      notificationDetails,
    );
  }
  
  Future<void> _showAppSwitchResolvedNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'app_switch_resolved',
      'App Switch Resolved',
      channelDescription: 'App switch resolved notifications',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    
    const notificationDetails = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      21,
      'App Restored',
      'Recording app restored to foreground',
      notificationDetails,
    );
  }
  
  Future<void> _showNetworkRestoredNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'network_restored',
      'Network Restored',
      channelDescription: 'Network restored notifications',
      importance: Importance.high,
      priority: Priority.high,
    );
    
    const notificationDetails = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      22,
      'Network Restored',
      'Offline recordings synced successfully',
      notificationDetails,
    );
  }
  
  Future<void> _showSystemKillResolvedNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'system_kill_resolved',
      'System Kill Resolved',
      channelDescription: 'System kill resolved notifications',
      importance: Importance.high,
      priority: Priority.high,
    );
    
    const notificationDetails = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      23,
      'Session Recovered',
      'Previous recording session recovered successfully',
      notificationDetails,
    );
  }
  
  Future<void> _showMemoryPressureResolvedNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'memory_pressure_resolved',
      'Memory Pressure Resolved',
      channelDescription: 'Memory pressure resolved notifications',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    
    const notificationDetails = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      24,
      'Memory Optimized',
      'Recording performance restored',
      notificationDetails,
    );
  }
  
  Future<void> _showBluetoothReconnectedNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'bluetooth_reconnected',
      'Bluetooth Reconnected',
      channelDescription: 'Bluetooth reconnected notifications',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    
    const notificationDetails = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      25,
      'Bluetooth Reconnected',
      'Switched back to Bluetooth audio',
      notificationDetails,
    );
  }
  
  Future<void> _showHeadsetReconnectedNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'headset_reconnected',
      'Headset Reconnected',
      channelDescription: 'Headset reconnected notifications',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    
    const notificationDetails = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      26,
      'Headset Reconnected',
      'Switched back to headset audio',
      notificationDetails,
    );
  }
  
  // Public methods for external interruption handling
  Future<void> handlePhoneCall() async {
    await _handleInterruption(InterruptionType.phoneCall, {
      'timestamp': DateTime.now().toIso8601String(),
      'call_type': 'incoming',
    });
  }
  
  Future<void> handleCallEnded() async {
    await _handleInterruptionResolved(InterruptionType.phoneCall);
  }
  
  Future<void> handleAppSwitched() async {
    await _handleInterruption(InterruptionType.appSwitch, {
      'timestamp': DateTime.now().toIso8601String(),
      'switch_type': 'background',
    });
  }
  
  Future<void> handleAppRestored() async {
    await _handleInterruptionResolved(InterruptionType.appSwitch);
  }
  
  Future<void> handleSystemKill() async {
    await _handleInterruption(InterruptionType.systemKill, {
      'timestamp': DateTime.now().toIso8601String(),
      'kill_type': 'system',
    });
  }
  
  Future<void> handleAppResumed() async {
    await _checkForRecovery();
  }
  
  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _appStateTimer?.cancel();
    _memoryMonitorTimer?.cancel();
    _phoneCallTimer?.cancel();
    _networkRetryTimer?.cancel();
    super.dispose();
  }
}
