import 'package:flutter/material.dart';

import 'recordings_screen.dart';
import 'timer_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // 최소 30분(00:30) ~ 최대 180분(03:00), 5분 단위로 조절
  static const int _minMinutes = 30;
  static const int _maxMinutes = 180;

  int _totalMinutes = 50; // 기본값: 상담 세션에서 흔히 쓰는 50분
  bool _recordingEnabled = false;

  static const List<int> _presets = [30, 45, 50, 60, 90, 120, 180];

  String get _durationLabel {
    final h = _totalMinutes ~/ 60;
    final m = _totalMinutes % 60;
    if (h == 0) return '$m분';
    if (m == 0) return '$h시간';
    return '$h시간 $m분';
  }

  void _startSession() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TimerScreen(
          totalDuration: Duration(minutes: _totalMinutes),
          recordingEnabled: _recordingEnabled,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('상담 타이머'),
        actions: [
          IconButton(
            tooltip: '저장된 녹음',
            icon: const Icon(Icons.folder_open),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RecordingsScreen()),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _DurationCard(
              label: _durationLabel,
              minutes: _totalMinutes,
              minMinutes: _minMinutes,
              maxMinutes: _maxMinutes,
              onChanged: (v) => setState(() => _totalMinutes = v),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _presets.map((m) {
                final selected = m == _totalMinutes;
                final h = m ~/ 60;
                final mm = m % 60;
                final label = h == 0
                    ? '$mm분'
                    : (mm == 0 ? '$h시간' : '$h시간 $mm분');
                return ChoiceChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: (_) => setState(() => _totalMinutes = m),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            Card(
              child: SwitchListTile(
                title: const Text('세션 녹음'),
                subtitle: const Text('종료 시 날짜/시간 이름의 MP3 파일로 자동 저장됩니다'),
                value: _recordingEnabled,
                onChanged: (v) => setState(() => _recordingEnabled = v),
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _startSession,
              icon: const Icon(Icons.play_arrow),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('시작하기', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DurationCard extends StatelessWidget {
  final String label;
  final int minutes;
  final int minMinutes;
  final int maxMinutes;
  final ValueChanged<int> onChanged;

  const _DurationCard({
    required this.label,
    required this.minutes,
    required this.minMinutes,
    required this.maxMinutes,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final divisions = (maxMinutes - minMinutes) ~/ 5;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Slider(
              value: minutes.toDouble(),
              min: minMinutes.toDouble(),
              max: maxMinutes.toDouble(),
              divisions: divisions,
              label: label,
              onChanged: (v) => onChanged(v.round()),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text('00:30', style: TextStyle(color: Colors.grey)),
                Text('03:00', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
