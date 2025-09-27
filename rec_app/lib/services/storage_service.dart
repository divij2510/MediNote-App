import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../models/audio_chunk.dart';
import '../models/session.dart';

class StorageService extends ChangeNotifier {
  static const String _chunksFileName = 'failed_chunks.json';
  static const String _sessionsFileName = 'sessions.json';

  Directory? _appDir;
  final List<AudioChunk> _failedChunks = [];
  final List<RecordingSession> _cachedSessions = [];

  List<AudioChunk> get failedChunks => List.unmodifiable(_failedChunks);
  List<RecordingSession> get cachedSessions => List.unmodifiable(_cachedSessions);

  Future<void> initialize() async {
    _appDir = await getApplicationDocumentsDirectory();
    await _loadFailedChunks();
    await _loadCachedSessions();
  }

  Future<void> _loadFailedChunks() async {
    try {
      if (_appDir == null) return;

      final file = File('${_appDir!.path}/$_chunksFileName');
      if (!await file.exists()) return;

      final jsonString = await file.readAsString();
      final jsonData = json.decode(jsonString) as List;

      _failedChunks.clear();
      for (final chunkJson in jsonData) {
        try {
          // Load chunk metadata
          final chunkData = chunkJson as Map<String, dynamic>;
          final chunkFile = File('${_appDir!.path}/chunk_${chunkData['sessionId']}_${chunkData['chunkNumber']}.m4a');

          if (await chunkFile.exists()) {
            final audioData = await chunkFile.readAsBytes();
            final chunk = AudioChunk.fromJson(chunkData, audioData);
            _failedChunks.add(chunk);
          }
        } catch (e) {
          debugPrint('Error loading chunk: $e');
        }
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading failed chunks: $e');
    }
  }

  Future<void> _saveFailedChunks() async {
    try {
      if (_appDir == null) return;

      final file = File('${_appDir!.path}/$_chunksFileName');
      final chunksJson = _failedChunks.map((c) => c.toJson()).toList();
      await file.writeAsString(json.encode(chunksJson));

      // Save audio data separately
      for (final chunk in _failedChunks) {
        final chunkFile = File('${_appDir!.path}/chunk_${chunk.sessionId}_${chunk.chunkNumber}.m4a');
        await chunkFile.writeAsBytes(chunk.data);
      }
    } catch (e) {
      debugPrint('Error saving failed chunks: $e');
    }
  }

  Future<void> _loadCachedSessions() async {
    try {
      if (_appDir == null) return;

      final file = File('${_appDir!.path}/$_sessionsFileName');
      if (!await file.exists()) return;

      final jsonString = await file.readAsString();
      final jsonData = json.decode(jsonString) as List;

      _cachedSessions.clear();
      for (final sessionJson in jsonData) {
        try {
          final session = RecordingSession.fromJson(sessionJson as Map<String, dynamic>);
          _cachedSessions.add(session);
        } catch (e) {
          debugPrint('Error loading session: $e');
        }
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading cached sessions: $e');
    }
  }

  Future<void> _saveCachedSessions() async {
    try {
      if (_appDir == null) return;

      final file = File('${_appDir!.path}/$_sessionsFileName');
      final sessionsJson = _cachedSessions.map((s) => s.toJson()).toList();
      await file.writeAsString(json.encode(sessionsJson));
    } catch (e) {
      debugPrint('Error saving cached sessions: $e');
    }
  }

  Future<void> storeFailedChunk(AudioChunk chunk) async {
    _failedChunks.add(chunk);
    await _saveFailedChunks();
    notifyListeners();
  }

  Future<void> removeFailedChunk(AudioChunk chunk) async {
    _failedChunks.removeWhere((c) =>
    c.sessionId == chunk.sessionId && c.chunkNumber == chunk.chunkNumber);

    // Delete associated file
    try {
      if (_appDir != null) {
        final chunkFile = File('${_appDir!.path}/chunk_${chunk.sessionId}_${chunk.chunkNumber}.m4a');
        if (await chunkFile.exists()) {
          await chunkFile.delete();
        }
      }
    } catch (e) {
      debugPrint('Error deleting chunk file: $e');
    }

    await _saveFailedChunks();
    notifyListeners();
  }

  Future<void> cacheSession(RecordingSession session) async {
    _cachedSessions.removeWhere((s) => s.id == session.id);
    _cachedSessions.add(session);
    await _saveCachedSessions();
    notifyListeners();
  }

  Future<void> clearFailedChunks() async {
    for (final chunk in _failedChunks) {
      try {
        if (_appDir != null) {
          final chunkFile = File('${_appDir!.path}/chunk_${chunk.sessionId}_${chunk.chunkNumber}.m4a');
          if (await chunkFile.exists()) {
            await chunkFile.delete();
          }
        }
      } catch (e) {
        debugPrint('Error deleting chunk file: $e');
      }
    }

    _failedChunks.clear();
    await _saveFailedChunks();
    notifyListeners();
  }

  Future<Uint8List?> readFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        return await file.readAsBytes();
      }
      return null;
    } catch (e) {
      debugPrint('Error reading file: $e');
      return null;
    }
  }

  Future<String?> createTempFile(String sessionId) async {
    try {
      if (_appDir == null) return null;

      final tempFile = File('${_appDir!.path}/temp_${sessionId}_${DateTime.now().millisecondsSinceEpoch}.m4a');
      await tempFile.create();
      return tempFile.path;
    } catch (e) {
      debugPrint('Error creating temp file: $e');
      return null;
    }
  }

  Future<void> deleteTempFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Error deleting temp file: $e');
    }
  }

  Future<double> getStorageUsage() async {
    try {
      if (_appDir == null) return 0.0;

      double totalSize = 0;
      final dir = Directory(_appDir!.path);

      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          final stat = await entity.stat();
          totalSize += stat.size;
        }
      }

      return totalSize / 1024 / 1024; // Return size in MB
    } catch (e) {
      debugPrint('Error calculating storage usage: $e');
      return 0.0;
    }
  }
}