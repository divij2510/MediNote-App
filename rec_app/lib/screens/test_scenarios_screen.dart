import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/test_scenarios_service.dart';
import '../services/api_service.dart';
import '../services/native_audio_service.dart';
import '../services/realtime_streaming_service.dart';
import '../services/interruption_handler.dart';
import '../services/system_integration_service.dart';

class TestScenariosScreen extends StatefulWidget {
  const TestScenariosScreen({Key? key}) : super(key: key);

  @override
  State<TestScenariosScreen> createState() => _TestScenariosScreenState();
}

class _TestScenariosScreenState extends State<TestScenariosScreen> {
  late TestScenariosService _testService;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  void _initializeServices() {
    _testService = Provider.of<TestScenariosService>(context, listen: false);
    
    // Initialize test service with all required services
    final apiService = Provider.of<ApiService>(context, listen: false);
    final nativeAudioService = Provider.of<NativeAudioService>(context, listen: false);
    final streamingService = Provider.of<RealtimeStreamingService>(context, listen: false);
    final interruptionHandler = Provider.of<InterruptionHandler>(context, listen: false);
    final systemIntegration = Provider.of<SystemIntegrationService>(context, listen: false);
    
    _testService.initialize(
      apiService,
      nativeAudioService,
      streamingService,
      interruptionHandler,
      systemIntegration,
    );
    
    setState(() {
      _isInitialized = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Test Scenarios'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _clearResults,
            icon: const Icon(Icons.clear),
            tooltip: 'Clear Results',
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: Consumer<TestScenariosService>(
        builder: (context, testService, child) {
          return Column(
            children: [
              // Test controls
              _buildTestControls(testService),
              
              // Test results
              Expanded(
                child: _buildTestResults(testService),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTestControls(TestScenariosService testService) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        border: Border(
          bottom: BorderSide(color: Colors.grey[800]!, width: 1),
        ),
      ),
      child: Column(
        children: [
          // Run all tests button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: testService.isRunningTests ? null : _runAllTests,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: testService.isRunningTests
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        ),
                        SizedBox(width: 12),
                        Text('Running Tests...'),
                      ],
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.play_arrow),
                        SizedBox(width: 8),
                        Text(
                          'Run All Tests',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Test summary
          _buildTestSummary(testService),
        ],
      ),
    );
  }

  Widget _buildTestSummary(TestScenariosService testService) {
    final passedTests = testService.testResults.values.where((result) => result).length;
    final totalTests = testService.testResults.length;
    final passRate = totalTests > 0 ? (passedTests / totalTests * 100).toStringAsFixed(1) : '0.0';
    
    return Row(
      children: [
        Expanded(
          child: _buildSummaryCard(
            'Total Tests',
            totalTests.toString(),
            Colors.blue,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildSummaryCard(
            'Passed',
            passedTests.toString(),
            Colors.green,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildSummaryCard(
            'Failed',
            (totalTests - passedTests).toString(),
            Colors.red,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildSummaryCard(
            'Pass Rate',
            '$passRate%',
            Colors.orange,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTestResults(TestScenariosService testService) {
    return Column(
      children: [
        // Test scenarios list
        Expanded(
          flex: 2,
          child: _buildTestScenariosList(testService),
        ),
        
        // Test logs
        Expanded(
          flex: 3,
          child: _buildTestLogs(testService),
        ),
      ],
    );
  }

  Widget _buildTestScenariosList(TestScenariosService testService) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[800]!),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.science, color: Colors.white),
                const SizedBox(width: 8),
                const Text(
                  'Test Scenarios',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: testService.testScenarios.length,
              itemBuilder: (context, index) {
                final scenario = testService.testScenarios[index];
                final result = testService.testResults[scenario];
                
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    leading: _getTestIcon(result),
                    title: Text(
                      scenario,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                    trailing: result != null
                        ? _getTestStatusChip(result)
                        : IconButton(
                            onPressed: testService.isRunningTests
                                ? null
                                : () => _runSpecificTest(scenario),
                            icon: const Icon(
                              Icons.play_arrow,
                              color: Colors.blue,
                            ),
                            tooltip: 'Run Test',
                          ),
                    onTap: result != null
                        ? null
                        : () => _runSpecificTest(scenario),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _getTestIcon(bool? result) {
    if (result == null) {
      return const Icon(Icons.radio_button_unchecked, color: Colors.grey);
    } else if (result) {
      return const Icon(Icons.check_circle, color: Colors.green);
    } else {
      return const Icon(Icons.cancel, color: Colors.red);
    }
  }

  Widget _getTestStatusChip(bool result) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: result ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: result ? Colors.green : Colors.red,
          width: 1,
        ),
      ),
      child: Text(
        result ? 'PASS' : 'FAIL',
        style: TextStyle(
          color: result ? Colors.green : Colors.red,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildTestLogs(TestScenariosService testService) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[800]!),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.terminal, color: Colors.white),
                const SizedBox(width: 8),
                const Text(
                  'Test Logs',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _clearResults,
                  icon: const Icon(Icons.clear, color: Colors.white),
                  tooltip: 'Clear Logs',
                ),
              ],
            ),
          ),
          Expanded(
            child: testService.testLogs.isEmpty
                ? const Center(
                    child: Text(
                      'No test logs yet. Run tests to see logs.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: testService.testLogs.length,
                    itemBuilder: (context, index) {
                      final log = testService.testLogs[index];
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text(
                          log,
                          style: TextStyle(
                            color: _getLogColor(log),
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Color _getLogColor(String log) {
    if (log.contains('PASSED')) {
      return Colors.green;
    } else if (log.contains('FAILED')) {
      return Colors.red;
    } else if (log.contains('ERROR')) {
      return Colors.red;
    } else if (log.contains('WARNING')) {
      return Colors.orange;
    } else {
      return Colors.white70;
    }
  }

  Future<void> _runAllTests() async {
    try {
      HapticFeedback.mediumImpact();
      await _testService.runAllTests();
    } catch (e) {
      _showErrorDialog('Error running tests: $e');
    }
  }

  Future<void> _runSpecificTest(String testName) async {
    try {
      HapticFeedback.lightImpact();
      await _testService.runSpecificTest(testName);
    } catch (e) {
      _showErrorDialog('Error running test: $e');
    }
  }

  void _clearResults() {
    HapticFeedback.lightImpact();
    _testService.clearTestResults();
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Error',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
