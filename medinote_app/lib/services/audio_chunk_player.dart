import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'api_service.dart';

class AudioChunkPlayer {
  static final AudioChunkPlayer _instance = AudioChunkPlayer._internal();
  factory AudioChunkPlayer() => _instance;
  AudioChunkPlayer._internal();

  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  bool _isLoading = false;
  String? _currentSessionId;
  StreamSubscription? _audioSubscription;
  Function()? _onPlaybackComplete;

  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  String? get currentSessionId => _currentSessionId;

  // Stream controller for audio chunks
  final StreamController<Uint8List> _chunkController = StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get chunkStream => _chunkController.stream;

  Future<void> initialize() async {
    try {
      print('🎵 AudioChunkPlayer initialized successfully');
    } catch (e) {
      print('❌ Failed to initialize AudioChunkPlayer: $e');
      rethrow;
    }
  }

  Future<void> playSessionChunks(String sessionId, {Function()? onComplete}) async {
    try {
      if (_isPlaying) {
        await stop();
      }

      _currentSessionId = sessionId;
      _isLoading = true;
      _onPlaybackComplete = onComplete;
      
      print('🎵 Starting chunk streaming for session: $sessionId');
      
      // Fetch audio chunks and create a temporary WAV file
      final audioFile = await _createWavFileFromChunks(sessionId);
      
      if (audioFile != null) {
        _isLoading = false;
        _isPlaying = true;
        
        // Play the WAV file using AudioPlayer
        await _player.play(DeviceFileSource(audioFile.path));
        
        // Listen for completion
        _player.onPlayerComplete.listen((_) {
          _isPlaying = false;
          _currentSessionId = null;
          print('✅ Audio playback completed');
          _onPlaybackComplete?.call();
        });
        
        print('🎵 Audio playback started for session: $sessionId');
      } else {
        _isLoading = false;
        throw Exception('Failed to create audio file from chunks');
      }
      
    } catch (e) {
      print('❌ Error playing session chunks: $e');
      _isPlaying = false;
      _isLoading = false;
      _currentSessionId = null;
      rethrow;
    }
  }

  Future<File?> _createWavFileFromChunks(String sessionId) async {
    try {
      final audioUrl = await ApiService.getAudioFileUrl(sessionId);
      final fullUrl = '${ApiService.baseUrl}$audioUrl';
      
      print('🔗 Fetching audio chunks from: $fullUrl');
      
      final response = await http.get(Uri.parse(fullUrl));
      
      if (response.statusCode == 200) {
        print('✅ Received ${response.bodyBytes.length} bytes of audio data');
        
        // Get the raw audio data (PCM chunks)
        final audioData = response.bodyBytes;
        
        // Create WAV file with proper headers
        final wavFile = await _createWavFile(audioData, sessionId);
        
        print('✅ Created WAV file: ${wavFile.path}');
        return wavFile;
      } else {
        throw Exception('Failed to fetch audio chunks: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error creating WAV file from chunks: $e');
      return null;
    }
  }

  Future<File> _createWavFile(Uint8List pcmData, String sessionId) async {
    // Get temporary directory
    final tempDir = await getTemporaryDirectory();
    final wavFile = File('${tempDir.path}/${sessionId}.wav');
    
    // WAV file parameters for 16kHz, 16-bit, mono
    const sampleRate = 16000;
    const channels = 1;
    const bitsPerSample = 16;
    
    final dataLength = pcmData.length;
    final totalDataLen = dataLength + 36; // 36 bytes for WAV header
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;
    
    // Create WAV header
    final header = Uint8List(44);
    int offset = 0;
    
    // RIFF header
    header.setRange(offset, offset + 4, 'RIFF'.codeUnits); offset += 4;
    header.setRange(offset, offset + 4, _int32ToBytes(totalDataLen)); offset += 4;
    header.setRange(offset, offset + 4, 'WAVE'.codeUnits); offset += 4;
    
    // fmt chunk
    header.setRange(offset, offset + 4, 'fmt '.codeUnits); offset += 4;
    header.setRange(offset, offset + 4, _int32ToBytes(16)); offset += 4; // fmt chunk size
    header.setRange(offset, offset + 2, _int16ToBytes(1)); offset += 2;  // PCM format
    header.setRange(offset, offset + 2, _int16ToBytes(channels)); offset += 2;
    header.setRange(offset, offset + 4, _int32ToBytes(sampleRate)); offset += 4;
    header.setRange(offset, offset + 4, _int32ToBytes(byteRate)); offset += 4;
    header.setRange(offset, offset + 2, _int16ToBytes(blockAlign)); offset += 2;
    header.setRange(offset, offset + 2, _int16ToBytes(bitsPerSample)); offset += 2;
    
    // data chunk
    header.setRange(offset, offset + 4, 'data'.codeUnits); offset += 4;
    header.setRange(offset, offset + 4, _int32ToBytes(dataLength)); offset += 4;
    
    // Combine header and PCM data
    final wavData = Uint8List(44 + dataLength);
    wavData.setRange(0, 44, header);
    wavData.setRange(44, 44 + dataLength, pcmData);
    
    // Write to file
    await wavFile.writeAsBytes(wavData);
    
    return wavFile;
  }

  Uint8List _int32ToBytes(int value) {
    return Uint8List.fromList([
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ]);
  }

  Uint8List _int16ToBytes(int value) {
    return Uint8List.fromList([
      value & 0xFF,
      (value >> 8) & 0xFF,
    ]);
  }

  Future<void> stop() async {
    try {
      await _player.stop();
      _isPlaying = false;
      _isLoading = false;
      _currentSessionId = null;
      
      await _audioSubscription?.cancel();
      _audioSubscription = null;
      
      print('🛑 AudioChunkPlayer stopped');
    } catch (e) {
      print('❌ Error stopping AudioChunkPlayer: $e');
    }
  }

  void dispose() {
    _chunkController.close();
    _audioSubscription?.cancel();
    _player.dispose();
  }
}
