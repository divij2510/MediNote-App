class RecordingSession {
  final String id;
  final String patientId;
  final String userId;
  final String patientName;
  final String status;
  final DateTime startTime;
  final DateTime? endTime;
  final String? templateId;
  final String? transcript;
  final String? sessionTitle;
  final String? sessionSummary;
  final int totalChunks;

  RecordingSession({
    required this.id,
    required this.patientId,
    required this.userId,
    required this.patientName,
    required this.status,
    required this.startTime,
    this.endTime,
    this.templateId,
    this.transcript,
    this.sessionTitle,
    this.sessionSummary,
    this.totalChunks = 0,
  });

  factory RecordingSession.fromJson(Map<String, dynamic> json) {
    return RecordingSession(
      id: json['id'] ?? '',
      patientId: json['patient_id'] ?? '',
      userId: json['user_id'] ?? '',
      patientName: json['patient_name'] ?? '',
      status: json['status'] ?? '',
      startTime: DateTime.parse(json['start_time'] ?? DateTime.now().toIso8601String()),
      endTime: json['end_time'] != null ? DateTime.parse(json['end_time']) : null,
      templateId: json['template_id'],
      transcript: json['transcript'],
      sessionTitle: json['session_title'],
      sessionSummary: json['session_summary'],
      totalChunks: json['total_chunks'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'patient_id': patientId,
      'user_id': userId,
      'patient_name': patientName,
      'status': status,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'template_id': templateId,
      'transcript': transcript,
      'session_title': sessionTitle,
      'session_summary': sessionSummary,
      'total_chunks': totalChunks,
    };
  }
}