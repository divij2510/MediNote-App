import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/patient.dart';

class ApiService {
  static const String baseUrl = 'https://medinote-app-production.up.railway.app';
  
  // Health check
  static Future<Map<String, dynamic>> checkHealth() async {
    print('🏥 Health check URL: $baseUrl/health');
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/health'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'MediNote-Flutter-App',
        },
      );
      
      print('🏥 Health check response status: ${response.statusCode}');
      print('🏥 Health check response body: ${response.body}');
      
      if (response.statusCode == 200) {
        try {
          final jsonResponse = json.decode(response.body);
          return jsonResponse;
        } catch (jsonError) {
          throw Exception('Backend returned HTML instead of JSON. Check if dev tunnel is properly configured.');
        }
      }
      throw Exception('Health check failed with status: ${response.statusCode}');
    } catch (e) {
      throw Exception('Backend connection failed: $e');
    }
  }
  
  // Patient CRUD operations
  static Future<List<Patient>> getPatients() async {
    final response = await http.get(Uri.parse('$baseUrl/patients/'));
    if (response.statusCode == 200) {
      List<dynamic> jsonList = json.decode(response.body);
      return jsonList.map((json) => Patient.fromJson(json)).toList();
    }
    throw Exception('Failed to load patients');
  }

  static Future<Patient> createPatient(Patient patient) async {
    final response = await http.post(
      Uri.parse('$baseUrl/patients/'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(patient.toJson()),
    );
    if (response.statusCode == 200) {
      return Patient.fromJson(json.decode(response.body));
    }
    throw Exception('Failed to create patient');
  }

  static Future<Patient> updatePatient(int id, Patient patient) async {
    final response = await http.put(
      Uri.parse('$baseUrl/patients/$id'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(patient.toJson()),
    );
    if (response.statusCode == 200) {
      return Patient.fromJson(json.decode(response.body));
    }
    throw Exception('Failed to update patient');
  }

  static Future<void> deletePatient(int id) async {
    print('🗑️ Attempting to delete patient with ID: $id');
    print('🗑️ DELETE URL: $baseUrl/patients/$id');
    
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/patients/$id'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'MediNote-Flutter-App',
        },
      );
      
      print('🗑️ Delete response status: ${response.statusCode}');
      print('🗑️ Delete response body: ${response.body}');
      
      if (response.statusCode != 200) {
        throw Exception('Failed to delete patient: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('🗑️ Delete patient error: $e');
      rethrow;
    }
  }

  // Audio session operations
  static Future<List<Map<String, dynamic>>> getPatientAudioSessions(int patientId) async {
    final response = await http.get(Uri.parse('$baseUrl/patients/$patientId/sessions'));
    if (response.statusCode == 200) {
      List<dynamic> jsonList = json.decode(response.body);
      return jsonList.cast<Map<String, dynamic>>();
    }
    throw Exception('Failed to load audio sessions');
  }

  static Future<String> getAudioFileUrl(String sessionId) async {
    // Use the new amplitude-based audio streaming endpoint
    return '/sessions/$sessionId/audio-stream';
  }

  // Get incomplete sessions for a patient
  static Future<List<dynamic>> getIncompleteSessions(int patientId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/patients/$patientId/incomplete-sessions'),
      headers: {'Content-Type': 'application/json'},
    );
    
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to get incomplete sessions: ${response.statusCode}');
    }
  }

  // Resume an incomplete session
  static Future<Map<String, dynamic>> resumeSession(String sessionId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/sessions/$sessionId/resume'),
      headers: {'Content-Type': 'application/json'},
    );
    
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to resume session: ${response.statusCode}');
    }
  }

  // Check if session exists and get its status
  static Future<Map<String, dynamic>> getSessionStatus(String sessionId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/sessions/$sessionId/status'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'Dart/3.8 (dart:io)',
        },
      );
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 404) {
        return {'exists': false};
      } else {
        throw Exception('Failed to get session status: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error checking session status: $e');
    }
  }

  // Get session chunks for playback
  static Future<List<Map<String, dynamic>>> getSessionChunks(String sessionId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/sessions/$sessionId/chunks'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'Dart/3.8 (dart:io)',
        },
      );
      
      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        return List<Map<String, dynamic>>.from(jsonResponse['chunks']);
      } else {
        throw Exception('Failed to get session chunks: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error getting session chunks: $e');
    }
  }
}