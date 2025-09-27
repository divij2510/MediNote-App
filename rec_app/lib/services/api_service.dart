import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../models/patient.dart';
import '../models/session.dart';
import '../models/audio_chunk.dart';

class ApiService extends ChangeNotifier {
  static const String baseUrl = 'https://api.example.com'; // Replace with actual API URL
  static const String backendUrl = 'https://backend.example.com'; // Replace with actual backend URL

  final Dio _dio = Dio();
  String? _authToken;
  bool _isConnected = true;
  String? _userId;

  bool get isConnected => _isConnected;
  String? get userId => _userId;

  ApiService() {
    _initializeNetworkListener();
    _configureDio();
  }

  void _initializeNetworkListener() {
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      // Check if any of the connectivity results indicate a connection
      _isConnected = results.any((result) => result != ConnectivityResult.none);
      notifyListeners();
    });
  }

  void _configureDio() {
    _dio.options.baseUrl = baseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (_authToken != null) {
          options.headers['Authorization'] = 'Bearer $_authToken';
        }
        options.headers['Content-Type'] = 'application/json';
        handler.next(options);
      },
      onError: (error, handler) {
        debugPrint('API Error: ${error.message}');
        handler.next(error);
      },
    ));
  }

  Future<void> setAuthToken(String token) async {
    _authToken = token;
    notifyListeners();
  }

  Future<String?> getUserIdByEmail(String email) async {
    try {
      final response = await _dio.get('/users/asd3fd2faec', queryParameters: {
        'email': email,
      });

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        _userId = data['id'];
        return _userId;
      }
      return null;
    } catch (e) {
      debugPrint('Error getting user ID: $e');
      return null;
    }
  }

  Future<List<Patient>> getPatients(String userId) async {
    try {
      final response = await _dio.get('/v1/patients', queryParameters: {
        'userId': userId,
      });

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final patients = (data['patients'] as List)
            .map((p) => Patient.fromJson(p as Map<String, dynamic>))
            .toList();
        return patients;
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching patients: $e');
      return [];
    }
  }

  Future<Patient?> addPatient(String name, String userId) async {
    try {
      final response = await _dio.post('/v1/add-patient-ext', data: {
        'name': name,
        'userId': userId,
      });

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data as Map<String, dynamic>;
        return Patient.fromJson(data['patient'] as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('Error adding patient: $e');
      return null;
    }
  }

  Future<Patient?> getPatientDetails(String patientId) async {
    try {
      final response = await _dio.get('/v1/patient-details/$patientId');

      if (response.statusCode == 200) {
        return Patient.fromJson(response.data as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching patient details: $e');
      return null;
    }
  }

  Future<List<RecordingSession>> getPatientSessions(String patientId) async {
    try {
      final response = await _dio.get('/v1/fetch-session-by-patient/$patientId');

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final sessions = (data['sessions'] as List)
            .map((s) => RecordingSession.fromJson(s as Map<String, dynamic>))
            .toList();
        return sessions;
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching patient sessions: $e');
      return [];
    }
  }

  Future<List<RecordingSession>> getAllSessions(String userId) async {
    try {
      final response = await _dio.get('/v1/all-session', queryParameters: {
        'userId': userId,
      });

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final sessions = (data['sessions'] as List)
            .map((s) => RecordingSession.fromJson(s as Map<String, dynamic>))
            .toList();
        return sessions;
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching all sessions: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getTemplates(String userId) async {
    try {
      final response = await _dio.get('/v1/fetch-default-template-ext', queryParameters: {
        'userId': userId,
      });

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['data']);
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching templates: $e');
      return [];
    }
  }

  Future<String?> createSession(RecordingSession session) async {
    try {
      final response = await _dio.post('/v1/upload-session', data: {
        'patientId': session.patientId,
        'userId': session.userId,
        'patientName': session.patientName,
        'status': session.status,
        'startTime': session.startTime.toIso8601String(),
        'templateId': session.templateId ?? 'new_patient_visit',
      });

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data as Map<String, dynamic>;
        return data['id'];
      }
      return null;
    } catch (e) {
      debugPrint('Error creating session: $e');
      return null;
    }
  }

  Future<bool> uploadAudioChunk(AudioChunk chunk, String templateId, bool isLast) async {
    if (!_isConnected) {
      debugPrint('No network connection, queueing chunk');
      return false;
    }

    try {
      // Step 1: Get presigned URL
      final presignedResponse = await _dio.post('/v1/get-presigned-url', data: {
        'sessionId': chunk.sessionId,
        'chunkNumber': chunk.chunkNumber,
        'mimeType': chunk.mimeType,
      });

      if (presignedResponse.statusCode != 200) {
        return false;
      }

      final presignedData = presignedResponse.data as Map<String, dynamic>;
      final uploadUrl = presignedData['url'] as String;
      final gcsPath = presignedData['gcsPath'] as String;
      final publicUrl = presignedData['publicUrl'] as String;

      // Step 2: Upload to Google Cloud Storage
      final uploadResponse = await http.put(
        Uri.parse(uploadUrl),
        headers: {
          'Content-Type': chunk.mimeType,
        },
        body: chunk.data,
      );

      if (uploadResponse.statusCode != 200) {
        return false;
      }

      // Step 3: Notify backend of successful upload
      final notifyResponse = await _dio.post('/v1/notify-chunk-uploaded', data: {
        'sessionId': chunk.sessionId,
        'gcsPath': gcsPath,
        'chunkNumber': chunk.chunkNumber,
        'isLast': isLast,
        'totalChunksClient': chunk.chunkNumber, // Will be updated with actual total
        'publicUrl': publicUrl,
        'mimeType': chunk.mimeType,
        'selectedTemplate': templateId,
        'selectedTemplateId': templateId,
        'model': 'fast',
      });

      if (notifyResponse.statusCode == 200) {
        chunk.gcsPath = gcsPath;
        chunk.publicUrl = publicUrl;
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('Error uploading chunk: $e');
      return false;
    }
  }

  Future<bool> updateSessionStatus(String sessionId, String status, int totalChunks) async {
    try {
      // This endpoint might not exist in the API, but we'll implement it for completeness
      final response = await _dio.patch('/v1/session/$sessionId', data: {
        'status': status,
        'totalChunks': totalChunks,
        'endTime': DateTime.now().toIso8601String(),
      });

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error updating session status: $e');
      return false;
    }
  }
}