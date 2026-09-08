import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// 녹음 저장 결과 + 실패 시 화면에 보여줄 진단용 상세 메시지.
class ConversionResult {
  final File? file;
  final String? diagnostic;
  const ConversionResult({this.file, this.diagnostic});
}

/// 세션 녹음을 담당하는 서비스.
///
/// 흐름:
/// 1) start() 호출 시 임시 폴더에 AAC(m4a)로 녹음을 시작한다.
///    (대부분의 단말이 AAC 하드웨어 인코더를 지원하므로 안정적으로 녹음 가능)
/// 2) stopAndSaveRecording() 호출 시 녹음을 중지하고,
///    임시 파일을 그대로 "recordings" 폴더에
///    "상담_yyyyMMdd_HHmmss.m4a" 이름으로 옮겨 저장한다.
///    (m4a/AAC는 대부분의 플레이어에서 바로 재생 가능하므로,
///    별도의 mp3 변환 없이 원본을 그대로 최종 파일로 사용한다.
///    예전에는 ffmpeg로 mp3 변환을 시도했으나, 일부 기기/빌드 조합에서
///    ffmpeg가 mp3 인코더를 포함하지 않아 변환이 실패하는 문제가 있었음.)
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

  /// 녹음을 취소하고 임시 파일을 삭제한다 (저장 없이 폐기)
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

  /// 녹음을 종료하고 최종 위치로 저장한다.
  /// 성공 시 최종 파일을, 실패 시 진단 메시지를 담아 반환한다.
  Future<ConversionResult> stopAndSaveRecording() async {
    if (!_isRecording) {
      return const ConversionResult(diagnostic: '녹음이 진행 중이 아니었습니다');
    }
    String? rawPath;
    try {
      rawPath = await _recorder.stop();
    } catch (e) {
      _isRecording = false;
      return ConversionResult(diagnostic: '녹음 중지 실패: $e');
    }
    _isRecording = false;
    final sourcePath = rawPath ?? _tempPath;
    if (sourcePath == null) {
      return const ConversionResult(diagnostic: '녹음 원본 파일 경로를 찾을 수 없습니다');
    }

    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      return ConversionResult(diagnostic: '녹음 원본 파일이 존재하지 않습니다: $sourcePath');
    }
    final sourceSize = await sourceFile.length();
    if (sourceSize == 0) {
      await sourceFile.delete();
      _tempPath = null;
      return const ConversionResult(diagnostic: '녹음 원본 파일 용량이 0바이트입니다 (녹음 자체가 되지 않은 것으로 보입니다)');
    }

    final recordingsDir = await _recordingsDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final outPath = '${recordingsDir.path}/상담_$timestamp.m4a';

    try {
      await sourceFile.copy(outPath);
      await sourceFile.delete();
    } catch (e) {
      return ConversionResult(
        diagnostic: '원본 크기: ${sourceSize}bytes\n파일 저장 실패: $e',
      );
    }
    _tempPath = null;

    final outFile = File(outPath);
    if (await outFile.exists()) {
      return ConversionResult(file: outFile);
    }
    return ConversionResult(
      diagnostic: '원본 크기: ${sourceSize}bytes\n저장된 파일을 찾을 수 없습니다: $outPath',
    );
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
