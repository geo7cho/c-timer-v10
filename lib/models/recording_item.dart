import 'dart:io';

/// 저장된 녹음 파일 하나를 표현하는 모델
class RecordingItem {
  final File file;
  final DateTime modifiedAt;
  final int sizeBytes;

  RecordingItem({
    required this.file,
    required this.modifiedAt,
    required this.sizeBytes,
  });

  String get fileName => file.uri.pathSegments.last;

  String get sizeLabel {
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static Future<RecordingItem> fromFile(File file) async {
    final stat = await file.stat();
    return RecordingItem(
      file: file,
      modifiedAt: stat.modified,
      sizeBytes: stat.size,
    );
  }
}
