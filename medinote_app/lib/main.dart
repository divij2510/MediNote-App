import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/patient_provider.dart';
import 'screens/patient_list_screen.dart';
import 'services/api_service.dart';
import 'services/audio_recording_service.dart';
import 'services/audio_streaming_service.dart';
import 'services/offline_recording_service.dart';
import 'services/app_lifecycle_service.dart';

void main() {
  runApp(const MediNoteApp());
}

class MediNoteApp extends StatelessWidget {
  const MediNoteApp({super.key});

  static final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => PatientProvider()),
        ChangeNotifierProvider(create: (context) => AudioRecordingService()),
        ChangeNotifierProvider(create: (context) => AudioStreamingService()),
        ChangeNotifierProvider(create: (context) => OfflineRecordingService()),
      ],
      child: MaterialApp(
        title: 'MediNote',
      theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            elevation: 0,
          ),
          cardTheme: CardThemeData(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        home: const BackendHealthWrapper(),
        navigatorObservers: [routeObserver],
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class BackendHealthWrapper extends StatefulWidget {
  const BackendHealthWrapper({super.key});

  @override
  State<BackendHealthWrapper> createState() => _BackendHealthWrapperState();
}

class _BackendHealthWrapperState extends State<BackendHealthWrapper> {
  bool _isLoading = true;
  bool _backendConnected = false;
  String _backendMessage = '';

  @override
  void initState() {
    super.initState();
    _checkBackendHealth();
    _initializeServices();
  }
  
  Future<void> _initializeServices() async {
    // Initialize app lifecycle service first
    final appLifecycleService = AppLifecycleService();
    appLifecycleService.initialize();
    print('📱 App lifecycle service initialized');
    
    // Initialize offline recording service first
    final offlineService = OfflineRecordingService();
    await offlineService.initialize();
    
    // Set up notification callbacks for offline service
    offlineService.setNotificationCallbacks(
      onUploadSuccess: (chunkCount) {
        print('📱 Offline upload success: $chunkCount chunks uploaded');
        // Note: We can't show SnackBar here as we don't have context
        // The UI will need to listen to the service state changes
      },
      onUploadError: (error) {
        print('📱 Offline upload error: $error');
      },
    );
    
    print('📱 Offline recording service initialized');
    
    // Initialize audio streaming service and inject offline service
    final audioStreamingService = AudioStreamingService();
    audioStreamingService.setOfflineService(offlineService);
    await audioStreamingService.initialize();
    print('🔄 Audio streaming service initialized with offline queue support');
  }

  Future<void> _checkBackendHealth() async {
    try {
      final healthData = await ApiService.checkHealth();
      setState(() {
        _backendConnected = true;
        _backendMessage = healthData['message'] ?? 'Backend connected';
        _isLoading = false;
      });
      
      // Show success snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ $_backendMessage'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
    setState(() {
        _backendConnected = false;
        _backendMessage = 'Backend connection failed: $e';
        _isLoading = false;
      });
      
      // Show error snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Backend not available: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _checkBackendHealth,
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Checking backend connection...'),
          ],
        ),
      ),
      );
    }

    return PatientListScreen(
      backendStatus: _backendConnected,
      backendMessage: _backendMessage,
      onRetryConnection: _checkBackendHealth,
    );
  }
}