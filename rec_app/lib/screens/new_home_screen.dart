import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../models/patient.dart';
import '../models/session.dart';
import '../services/api_service.dart';
import 'patient_list_screen.dart';
import 'recording_screen.dart';
import 'test_scenarios_screen.dart';
import 'past_recordings_screen.dart';
import 'audio_playback_screen.dart';
import '../services/audio_playback_service.dart';

class NewHomeScreen extends StatefulWidget {
  const NewHomeScreen({super.key});

  @override
  State<NewHomeScreen> createState() => _NewHomeScreenState();
}

class _NewHomeScreenState extends State<NewHomeScreen>
    with TickerProviderStateMixin {
  late AnimationController _fabAnimationController;
  late Animation<double> _fabAnimation;
  
  @override
  void initState() {
    super.initState();
    _setupAnimations();
  }
  
  void _setupAnimations() {
    _fabAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _fabAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fabAnimationController,
      curve: Curves.elasticOut,
    ));
    
    _fabAnimationController.forward();
  }
  
  @override
  void dispose() {
    _fabAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: _buildAppBar(),
      body: Consumer<AppState>(
        builder: (context, appState, child) {
          return _buildBody(appState);
        },
      ),
      floatingActionButton: _buildFloatingActionButton(),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppTheme.surface,
      elevation: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MediNote',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: AppTheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            'Medical Recording Assistant',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppTheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
        actions: [
          IconButton(
            onPressed: _showTestScenarios,
            icon: const Icon(Icons.science),
            tooltip: 'Test Scenarios',
          ),
          IconButton(
            onPressed: _showSettings,
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
          ),
        ],
    );
  }

  Widget _buildBody(AppState appState) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildQuickActions(),
          const SizedBox(height: 24),
          _buildRecentSessions(),
          const SizedBox(height: 24),
          _buildStats(),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: AppTheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildActionCard(
                icon: Icons.people_outline,
                title: 'Select Patient',
                subtitle: 'Start new recording',
                onTap: _navigateToPatients,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildActionCard(
                icon: Icons.history,
                title: 'Recent',
                subtitle: 'View recordings',
                onTap: _showRecentRecordings,
                color: AppTheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required Color color,
  }) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 24,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentSessions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Sessions',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppTheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextButton(
              onPressed: _showAllSessions,
              child: const Text('View All'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSessionList(),
      ],
    );
  }

  Widget _buildSessionList() {
    return Consumer<ApiService>(
      builder: (context, apiService, child) {
        return FutureBuilder<List<RecordingSession>>(
          future: apiService.getSessions(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Error loading sessions: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red),
                ),
              );
            }
            
            final sessions = snapshot.data ?? [];
            
            if (sessions.isEmpty) {
              return const Center(
                child: Text(
                  'No recordings yet',
                  style: TextStyle(color: Colors.grey),
                ),
              );
            }
            
            // Show only recent 3 sessions
            final recentSessions = sessions.take(3).toList();
            
            return Column(
              children: recentSessions.map((session) => _buildSessionCardFromData(session)).toList(),
            );
          },
        );
      },
    );
  }

  Widget _buildSessionCard(Map<String, String> session) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.play_circle_outline,
            color: AppTheme.primary,
            size: 20,
          ),
        ),
        title: Text(
          session['patient']!,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          '${session['time']} • ${session['duration']}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppTheme.onSurfaceVariant,
          ),
        ),
        trailing: IconButton(
          onPressed: () => _playSession(session),
          icon: const Icon(Icons.play_arrow),
          color: AppTheme.primary,
        ),
        onTap: () => _playSession(session),
      ),
    );
  }

  Widget _buildSessionCardFromData(RecordingSession session) {
    final duration = session.endTime != null 
        ? session.endTime!.difference(session.startTime)
        : Duration.zero;
    
    final durationText = _formatDuration(duration);
    final timeAgo = _getTimeAgo(session.startTime);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getStatusColor(session.status),
          child: Icon(
            _getStatusIcon(session.status),
            color: Colors.white,
          ),
        ),
        title: Text(session.patientName),
        subtitle: Text('$timeAgo • $durationText'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.play_arrow),
              onPressed: () => _playSessionFromData(session),
              tooltip: 'Play Recording',
            ),
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: () => _shareSession(session),
              tooltip: 'Share Recording',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStats() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Today\'s Summary',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: AppTheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: 'Recordings',
                value: '3',
                icon: Icons.mic,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildStatCard(
                title: 'Duration',
                value: '46:35',
                icon: Icons.timer,
                color: AppTheme.success,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildStatCard(
                title: 'Patients',
                value: '3',
                icon: Icons.people,
                color: AppTheme.warning,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: color,
                size: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppTheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingActionButton() {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        return AnimatedBuilder(
          animation: _fabAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _fabAnimation.value,
              child: FloatingActionButton(
                onPressed: _navigateToPatients,
                backgroundColor: AppTheme.primary,
                child: const Icon(
                  Icons.mic,
                  color: Colors.white,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBottomNavigationBar() {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        return BottomNavigationBar(
          currentIndex: _getCurrentIndex(appState.currentPage),
          onTap: (index) => _onBottomNavTap(index),
          type: BottomNavigationBarType.fixed,
          selectedItemColor: AppTheme.primary,
          unselectedItemColor: AppTheme.onSurfaceVariant,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people_outline),
              activeIcon: Icon(Icons.people),
              label: 'Patients',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history_outlined),
              activeIcon: Icon(Icons.history),
              label: 'History',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              activeIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        );
      },
    );
  }

  int _getCurrentIndex(AppPage page) {
    switch (page) {
      case AppPage.home:
        return 0;
      case AppPage.patients:
        return 1;
      case AppPage.playback:
        return 2;
      case AppPage.settings:
        return 3;
      default:
        return 0;
    }
  }

  void _onBottomNavTap(int index) {
    final appState = context.read<AppState>();
    switch (index) {
      case 0:
        appState.navigateTo(AppPage.home);
        break;
      case 1:
        appState.navigateTo(AppPage.patients);
        _navigateToPatients();
        break;
      case 2:
        _showRecentRecordings();
        break;
      case 3:
        _showSettings();
        break;
    }
  }

  void _navigateToPatients() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const PatientListScreen(),
      ),
    );
  }

  void _showRecentRecordings() {
    // TODO: Implement recent recordings screen
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Recent recordings feature coming soon'),
      ),
    );
  }

  void _showAllSessions() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const PastRecordingsScreen(),
      ),
    );
  }

  void _playSession(Map<String, String> session) {
    // TODO: Implement session playback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Playing session for ${session['patient']}'),
      ),
    );
  }

  void _playSessionFromData(RecordingSession session) {
    // Initialize audio playback service
    final audioPlaybackService = Provider.of<AudioPlaybackService>(context, listen: false);
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChangeNotifierProvider.value(
          value: audioPlaybackService,
          child: AudioPlaybackScreen(session: session),
        ),
      ),
    );
  }

  void _shareSession(RecordingSession session) {
    // TODO: Implement session sharing
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Sharing ${session.patientName} recording')),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
    } else {
      return 'Just now';
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Colors.green;
      case 'recording':
        return Colors.red;
      case 'paused':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Icons.check_circle;
      case 'recording':
        return Icons.mic;
      case 'paused':
        return Icons.pause_circle;
      default:
        return Icons.radio_button_unchecked;
    }
  }

  void _showTestScenarios() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const TestScenariosScreen(),
      ),
    );
  }

  void _showSettings() {
    // TODO: Implement settings screen
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Settings feature coming soon'),
      ),
    );
  }
}
