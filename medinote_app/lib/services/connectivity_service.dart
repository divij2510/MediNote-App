import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

class ConnectivityService extends ChangeNotifier {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();
  
  bool _isOnline = true;
  Timer? _connectivityTimer;
  final List<String> _testUrls = [
    'https://www.google.com',
    'https://www.cloudflare.com',
    'https://httpbin.org/status/200',
  ];
  
  bool get isOnline => _isOnline;
  bool get isOffline => !_isOnline;
  
  /// Start monitoring connectivity
  void startMonitoring() {
    _connectivityTimer?.cancel();
    _connectivityTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkConnectivity();
    });
    
    // Initial check
    _checkConnectivity();
    print('🌐 Connectivity monitoring started');
  }
  
  /// Stop monitoring connectivity
  void stopMonitoring() {
    _connectivityTimer?.cancel();
    _connectivityTimer = null;
    print('🌐 Connectivity monitoring stopped');
  }
  
  /// Check connectivity by pinging multiple URLs
  Future<void> _checkConnectivity() async {
    bool wasOnline = _isOnline;
    
    try {
      // Try to connect to multiple test URLs
      for (String url in _testUrls) {
        try {
          final client = HttpClient();
          client.connectionTimeout = const Duration(seconds: 3);
          
          final request = await client.getUrl(Uri.parse(url));
          final response = await request.close();
          
          if (response.statusCode == 200) {
            _isOnline = true;
            client.close();
            break;
          }
          client.close();
        } catch (e) {
          // Try next URL
          continue;
        }
      }
      
      // If all URLs failed, we're offline
      if (!_isOnline) {
        _isOnline = false;
      }
    } catch (e) {
      _isOnline = false;
    }
    
    // Notify listeners if connectivity status changed
    if (wasOnline != _isOnline) {
      notifyListeners();
      if (_isOnline) {
        print('✅ Internet connection restored');
      } else {
        print('❌ Internet connection lost');
      }
    }
  }
  
  /// Force connectivity check
  Future<bool> checkConnectivityNow() async {
    await _checkConnectivity();
    return _isOnline;
  }
  
  /// Get connectivity status as string
  String get connectivityStatus => _isOnline ? 'Online' : 'Offline';
  
  /// Dispose resources
  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
}
