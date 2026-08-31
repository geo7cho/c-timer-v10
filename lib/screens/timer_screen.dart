import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/alarm_sound_service.dart';
import '../services/recorder_service.dart';
import 'recordings_screen.dart';

class TimerScreen extends StatefulWidget {
  final Duration totalDuration;
  final bool recordingEnabled;

  const TimerScreen({
    super.key,
    required this.totalDuration,
    required this.recordingEnabled,
  });

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

enum _SessionState { running, paused, finished }

class _TimerScreenState extends State<TimerScreen> {
  late Duration _remaining;
  Timer? _ticker;
  _SessionState _state = _SessionState.running;
  bool _recordingActive = false;
  String? _statusMessage;

  final RecorderService _recorderService = RecorderService();
  final AlarmSoundService _alarmSoundService = AlarmSoundService();

  @override
  void initState() {
    super.initState();
    _remaining = widget.totalDuration;
    _setup();
  }

  Future<void> _setup() async {
    await WakelockPlus.enable();

    if (widget.recordingEnabled) {
      final micStatus = await Permission.microphone.request();
      if (micStatus.isGranted) {
        try {
          await _recorderService.start();
          setState(() => _recordingActive = true);
        } catch (e) {
          setState(() => _statusMessage = '녹음을 시작하지 못했습니다: $e');
        }
      } else {
        setState(() => _statusMessage = '마이크 권한이 없어 녹음 없이 진행합니다');
      }
    }

    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_state != _SessionState.running) return;
      setState(() {
        if (_remaining.inSeconds <= 1) {
          _remaining = Duration.zero;
          _onTimeUp();
        } else {
          _remaining -= const Duration(seconds: 1);
        }
      });
    });
  }

  Future<void> _togglePause() async {
    if (_state == _SessionState.running) {
      setState(() => _state = _SessionState.paused);
      if (_recordingActive) await _recorderService.pause();
    } else if (_state == _SessionState.paused) {
      setState(() => _state = _SessionState.running);
      if (_recordingActive) await _recorderService.resume();
    }
  }

  Future<void> _confirmCancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('세션 종료'),
        content: const Text('지금 종료하면 녹음이 저장되지 않고 폐기됩니다. 종료할까요?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true), child: const Text('종료')),
        ],
      ),
    );
    if (ok == true) {
      _ticker?.cancel();
      if (_recordingActive) {
        await _recorderService.cancel();
      }
      await WakelockPlus.disable();
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _onTimeUp() async {
    _ticker?.cancel();
    _state = _SessionState.finished;

    // 무음 모드여도 들리도록 알람음 반복 재생
    unawaited(_alarmSoundService.playLoop());

    File? savedFile;
    if (_recordingActive) {
      setState(() => _statusMessage = '녹음 파일을 MP3로 변환 중...');
      savedFile = await _recorderService.stopAndConvertToMp3();
      setState(() {
        _statusMessage = savedFile != null
            ? '녹음이 저장되었습니다: ${savedFile!.uri.pathSegments.last}'
            : '녹음 변환에 실패했습니다';
      });
    }

    await WakelockPlus.disable();
    if (mounted) setState(() {});
  }

  Future<void> _stopAlarm() async {
    await _alarmSoundService.stop();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _alarmSoundService.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  String _format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.totalDuration.inSeconds;
    final progress =
        total == 0 ? 0.0 : 1 - (_remaining.inSeconds / total).clamp(0.0, 1.0);

    return PopScope(
      canPop: _state == _SessionState.finished,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _state != _SessionState.finished) {
          _confirmCancel();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_state == _SessionState.finished ? '세션 종료' : '진행 중'),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                if (_recordingActive)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Chip(
                      avatar: Icon(Icons.fiber_manual_record, color: Colors.red, size: 16),
                      label: Text('녹음 중'),
                    ),
                  ),
                Expanded(
                  child: Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 240,
                          height: 240,
                          child: CircularProgressIndicator(
                            value: progress,
                            strokeWidth: 10,
                          ),
                        ),
                        Text(
                          _format(_remaining),
                          style: const TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_statusMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      _statusMessage!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                if (_state == _SessionState.finished) ...[
                  if (_alarmSoundService.isPlaying)
                    FilledButton.icon(
                      onPressed: _stopAlarm,
                      icon: const Icon(Icons.notifications_off),
                      label: const Text('알람 끄기'),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('홈으로'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (_) => const RecordingsScreen(),
                              ),
                            );
                          },
                          child: const Text('녹음 목록 보기'),
                        ),
                      ),
                    ],
                  ),
                ] else
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _confirmCancel,
                          icon: const Icon(Icons.stop),
                          label: const Text('종료'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _togglePause,
                          icon: Icon(_state == _SessionState.running
                              ? Icons.pause
                              : Icons.play_arrow),
                          label: Text(
                              _state == _SessionState.running ? '일시정지' : '계속'),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
