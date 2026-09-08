import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// mp3 변환 시도 결과 + 실패 시 화면에 보여줄 진단용 상세 메시지.
class ConversionResult {
  final File? file;
  final String? diagnostic;
  const ConversionResult({this.file, this.diagnostic});
}

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
  /// 성공 시 최종 mp3 파일을, 실패 시 진단 메시지를 담아 반환한다.
  Future<ConversionResult> stopAndConvertToMp3() async {
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
    final outPath = '${recordingsDir.path}/상담_$timestamp.mp3';

    String? ffmpegError;
    int? returnCodeValue;
    String logsSnippet = '';
    try {
      final session = await FFmpegKit.execute(
        '-y -i "$sourcePath" -vn -ar 44100 -ac 1 -b:a 128k "$outPath"',
      );
      final returnCode = await session.getReturnCode();
      returnCodeValue = returnCode?.getValue();
      if (!ReturnCode.isSuccess(returnCode)) {
        try {
          final logs = await session.getAllLogsAsString();
          logsSnippet = _snippet(logs ?? '');
        } catch (_) {}
      }
    } catch (e) {
      ffmpegError = '$e';
    }

    // 원본 임시 파일은 성공/실패와 무관하게 정리
    if (await sourceFile.exists()) {
      await sourceFile.delete();
    }
    _tempPath = null;

    if (ffmpegError != null) {
      return ConversionResult(
        diagnostic: '원본 크기: ${sourceSize}bytes\nffmpeg 실행 예외: $ffmpegError',
      );
    }

    final outFile = File(outPath);
    if (returnCodeValue == 0 && await outFile.exists()) {
      return ConversionResult(file: outFile);
    }

    return ConversionResult(
      diagnostic: '원본 크기: ${sourceSize}bytes\n'
          'ffmpeg 리턴 코드: $returnCodeValue\n'
          '출력 파일 존재: ${await outFile.exists()}\n'
          'ffmpeg 로그: $logsSnippet',
    );
  }

  String _snippet(String s) => s.length > 400 ? '${s.substring(0, 400)}...' : s;

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
