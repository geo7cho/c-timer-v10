import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// 세션 녹음 + MP3 변환을 담당하는 서비스.
///
/// 흐름:
/// 1) start() 호출 시 임시 폴더에 AAC(m4a)로 녹음을 시작한다.
///    (대부분의 단말이 AAC 하드웨어 인코더를 지원하므로 안정적으로 녹음 가능)
/// 2) stopAndConvertToMp3() 호출 시 녹음을 중지하고,
///    ffmpeg_kit으로 mp3로 변환한 뒤 "recordings" 폴더에
///    "상담_yyyyMMdd_HHmmss.mp3" 이름으로 저장한다.
/// 3) 변환이 끝나면 임시 파일은 삭제한다.
class RecorderService {
  final AudioRecorder _recorder = AudioRecorder();
  String? _tempPath;
  bool _isRecording = false;

  bool get isRecording => _isRecording;

  /// 마이크 권한이 있는지 확인
  Future<bool> hasPermission() => _recorder.hasPermission();

  /// 녹음 시작 (임시 파일에 AAC로 기록)
  Future<void> start() async {
    if (_isRecording) return;
    final dir = await getTemporaryDirectory();
    _tempPath =
        '${dir.path}/session_temp_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: _tempPath!,
    );
    _isRecording = true;
  }

  Future<void> pause() async {
    if (_isRecording && await _recorder.isRecording()) {
      await _recorder.pause();
    }
  }

  Future<void> resume() async {
    if (_isRecording) {
      await _recorder.resume();
    }
  }

  /// 녹음을 취소하고 임시 파일을 삭제한다 (변환 없이 폐기)
  Future<void> cancel() async {
    if (_isRecording) {
      await _recorder.stop();
      _isRecording = false;
    }
    if (_tempPath != null) {
      final f = File(_tempPath!);
      if (await f.exists()) {
        await f.delete();
      }
    }
    _tempPath = null;
  }

  /// 녹음을 종료하고 MP3로 변환하여 저장한다.
  /// 성공 시 최종 mp3 파일의 File 객체를 반환하고, 실패 시 null을 반환한다.
  Future<File?> stopAndConvertToMp3() async {
    if (!_isRecording) return null;
    final rawPath = await _recorder.stop();
    _isRecording = false;
    final sourcePath = rawPath ?? _tempPath;
    if (sourcePath == null) return null;

    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) return null;

    final recordingsDir = await _recordingsDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final outPath = '${recordingsDir.path}/상담_$timestamp.mp3';

    final session = await FFmpegKit.execute(
      '-y -i "$sourcePath" -vn -ar 44100 -ac 1 -b:a 128k "$outPath"',
    );
    final returnCode = await session.getReturnCode();

    // 원본 임시 파일은 성공/실패와 무관하게 정리
    if (await sourceFile.exists()) {
      await sourceFile.delete();
    }
    _tempPath = null;

    if (ReturnCode.isSuccess(returnCode)) {
      return File(outPath);
    }
    return null;
  }

  /// 녹음 결과가 저장되는 폴더 (앱 전용 문서 폴더 하위 recordings/)
  static Future<Directory> _recordingsDirectory() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${docsDir.path}/recordings');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 외부(화면)에서도 같은 폴더 경로를 쓸 수 있도록 공개 메서드 제공
  static Future<Directory> recordingsDirectory() => _recordingsDirectory();
}
