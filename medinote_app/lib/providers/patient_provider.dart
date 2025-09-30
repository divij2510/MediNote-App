import 'package:flutter/foundation.dart';
import '../models/patient.dart';
import '../services/api_service.dart';

class PatientProvider with ChangeNotifier {
  List<Patient> _patients = [];
  bool _isLoading = false;
  String? _error;

  List<Patient> get patients => _patients;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadPatients() async {
    _setLoading(true);
    try {
      _patients = await ApiService.getPatients();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> createPatient(Patient patient) async {
    try {
      final createdPatient = await ApiService.createPatient(patient);
      _patients.add(createdPatient);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      rethrow;
    }
  }

  Future<void> updatePatient(int id, Patient patient) async {
    try {
      final updatedPatient = await ApiService.updatePatient(id, patient);
      final index = _patients.indexWhere((p) => p.id == id);
      if (index != -1) {
        _patients[index] = updatedPatient;
        notifyListeners();
      }
    } catch (e) {
      _error = e.toString();
      rethrow;
    }
  }

  Future<void> deletePatient(int id) async {
    try {
      await ApiService.deletePatient(id);
      _patients.removeWhere((p) => p.id == id);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      rethrow;
    }
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}