import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'screens/splash_screen.dart';
import 'screens/new_home_screen.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'services/api_service.dart';
import 'services/audio_service.dart';
import 'services/realtime_audio_service.dart';
import 'services/realtime_streaming_service.dart';
import 'services/native_audio_service.dart';
import 'services/interruption_handler.dart';
import 'services/system_integration_service.dart';
import 'services/test_scenarios_service.dart';
import 'services/storage_service.dart';
import 'services/permission_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize port for communication between TaskHandler and UI
  FlutterForegroundTask.initCommunicationPort();

  runApp(const MediNoteApp());
}

class MediNoteApp extends StatelessWidget {
  const MediNoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider(create: (_) => ApiService()),
        ChangeNotifierProvider(create: (_) => AudioService()),
        ChangeNotifierProvider(create: (_) => RealtimeAudioService()),
        ChangeNotifierProvider(create: (_) => RealtimeStreamingService()),
        ChangeNotifierProvider(create: (_) => NativeAudioService()),
        ChangeNotifierProvider(create: (_) => InterruptionHandler()),
        ChangeNotifierProvider(create: (_) => SystemIntegrationService()),
        ChangeNotifierProvider(create: (_) => TestScenariosService()),
        ChangeNotifierProvider(create: (_) => StorageService()),
        ChangeNotifierProvider(create: (_) => PermissionService()),
      ],
      child: MaterialApp(
        title: 'MediNote',
        theme: AppTheme.lightTheme,
        home: const SplashScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}