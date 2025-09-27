class Patient {
  final String id;
  final String name;
  final String? pronouns;
  final String? email;
  final String? background;
  final String? medicalHistory;
  final String? familyHistory;
  final String? socialHistory;
  final String? previousTreatment;

  Patient({
    required this.id,
    required this.name,
    this.pronouns,
    this.email,
    this.background,
    this.medicalHistory,
    this.familyHistory,
    this.socialHistory,
    this.previousTreatment,
  });

  factory Patient.fromJson(Map<String, dynamic> json) {
    return Patient(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      pronouns: json['pronouns'],
      email: json['email'],
      background: json['background'],
      medicalHistory: json['medical_history'],
      familyHistory: json['family_history'],
      socialHistory: json['social_history'],
      previousTreatment: json['previous_treatment'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'pronouns': pronouns,
      'email': email,
      'background': background,
      'medical_history': medicalHistory,
      'family_history': familyHistory,
      'social_history': socialHistory,
      'previous_treatment': previousTreatment,
    };
  }
}