import 'dart:async';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class AppLifecycleService with ChangeNotifier {
  static final AppLifecycleService _instance = AppLifecycleService._internal();
  factory AppLifecycleService() => _instance;
  AppLifecycleService._internal();

  AppLifecycleState _currentState = AppLifecycleState.resumed;
  bool _isInBackground = false;
  
  // Getters
  AppLifecycleState get currentState => _currentState;
  bool get isInBackground => _isInBackground;
  bool get isInForeground => !_isInBackground;

  void initialize() {
    // Listen to app lifecycle changes
    SystemChannels.lifecycle.setMessageHandler((message) async {
      if (message == null) return null;
      
      switch (message) {
        case 'AppLifecycleState.paused':
          _handleAppPaused();
          break;
        case 'AppLifecycleState.resumed':
          _handleAppResumed();
          break;
        case 'AppLifecycleState.inactive':
          _handleAppInactive();
          break;
        case 'AppLifecycleState.detached':
          _handleAppDetached();
          break;
      }
      return null;
    });
  }

  void _handleAppPaused() {
    print('📱 App paused - going to background');
    _currentState = AppLifecycleState.paused;
    _isInBackground = true;
    notifyListeners();
  }

  void _handleAppResumed() {
    print('📱 App resumed - coming to foreground');
    _currentState = AppLifecycleState.resumed;
    _isInBackground = false;
    notifyListeners();
  }

  void _handleAppInactive() {
    print('📱 App inactive');
    _currentState = AppLifecycleState.inactive;
    notifyListeners();
  }

  void _handleAppDetached() {
    print('📱 App detached');
    _currentState = AppLifecycleState.detached;
    notifyListeners();
  }
}
