class AudioRecording {
  final int id;
  final int patientId;
  final String fileName;
  final String filePath;
  final int duration; // in seconds
  final DateTime createdAt;
  final bool isCompleted;

  AudioRecording({
    required this.id,
    required this.patientId,
    required this.fileName,
    required this.filePath,
    required this.duration,
    required this.createdAt,
    this.isCompleted = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'patientId': patientId,
      'fileName': fileName,
      'filePath': filePath,
      'duration': duration,
      'createdAt': createdAt.toIso8601String(),
      'isCompleted': isCompleted,
    };
  }

  factory AudioRecording.fromJson(Map<String, dynamic> json) {
    return AudioRecording(
      id: json['id'],
      patientId: json['patientId'],
      fileName: json['fileName'],
      filePath: json['filePath'],
      duration: json['duration'],
      createdAt: DateTime.parse(json['createdAt']),
      isCompleted: json['isCompleted'] ?? true,
    );
  }

  AudioRecording copyWith({
    int? id,
    int? patientId,
    String? fileName,
    String? filePath,
    int? duration,
    DateTime? createdAt,
    bool? isCompleted,
  }) {
    return AudioRecording(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      duration: duration ?? this.duration,
      createdAt: createdAt ?? this.createdAt,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}
