import 'dart:typed_data';

enum ChunkStatus { pending, uploading, uploaded, failed, retrying }

class AudioChunk {
  final String sessionId;
  final int chunkNumber;
  final Uint8List data;
  final String mimeType;
  final DateTime timestamp;
  ChunkStatus status;
  int retryCount;
  String? gcsPath;
  String? publicUrl;
  String? error;

  AudioChunk({
    required this.sessionId,
    required this.chunkNumber,
    required this.data,
    required this.mimeType,
    required this.timestamp,
    this.status = ChunkStatus.pending,
    this.retryCount = 0,
    this.gcsPath,
    this.publicUrl,
    this.error,
  });

  bool get canRetry => retryCount < 3;
  bool get isUploaded => status == ChunkStatus.uploaded;
  bool get shouldRetry => status == ChunkStatus.failed && canRetry;

  AudioChunk copyWith({
    ChunkStatus? status,
    int? retryCount,
    String? gcsPath,
    String? publicUrl,
    String? error,
  }) {
    return AudioChunk(
      sessionId: sessionId,
      chunkNumber: chunkNumber,
      data: data,
      mimeType: mimeType,
      timestamp: timestamp,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      gcsPath: gcsPath ?? this.gcsPath,
      publicUrl: publicUrl ?? this.publicUrl,
      error: error ?? this.error,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sessionId': sessionId,
      'chunkNumber': chunkNumber,
      'mimeType': mimeType,
      'timestamp': timestamp.toIso8601String(),
      'status': status.name,
      'retryCount': retryCount,
      'gcsPath': gcsPath,
      'publicUrl': publicUrl,
      'error': error,
    };
  }

  factory AudioChunk.fromJson(Map<String, dynamic> json, Uint8List data) {
    return AudioChunk(
      sessionId: json['sessionId'],
      chunkNumber: json['chunkNumber'],
      data: data,
      mimeType: json['mimeType'],
      timestamp: DateTime.parse(json['timestamp']),
      status: ChunkStatus.values.firstWhere(
            (s) => s.name == json['status'],
        orElse: () => ChunkStatus.pending,
      ),
      retryCount: json['retryCount'] ?? 0,
      gcsPath: json['gcsPath'],
      publicUrl: json['publicUrl'],
      error: json['error'],
    );
  }
}