import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 상담 시작 화면(내담자가 함께 볼 수 있는 화면)과 분리된 설정 화면.
/// 세션 녹음 여부를 미리 정해두면, 시작 화면에서는 토글할 필요 없이
/// 이 값 그대로 적용된다.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  static const kRecordingEnabledKey = 'pref_recording_enabled';

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _recordingEnabled = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _recordingEnabled =
          prefs.getBool(SettingsScreen.kRecordingEnabledKey) ?? false;
      _loaded = true;
    });
  }

  Future<void> _setRecordingEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsScreen.kRecordingEnabledKey, value);
    if (!mounted) return;
    setState(() => _recordingEnabled = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: SafeArea(
        child: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Card(
                    child: SwitchListTile(
                      title: const Text('세션 자동 녹음'),
                      subtitle: const Text(
                        '켜두면 다음 세션부터 시작하기를 누르는 즉시 자동으로 녹음됩니다.\n'
                        '내담자와 함께 보는 시작 화면에는 이 설정이 표시되지 않으므로, '
                        '상담 전에 미리 여기서 정해두세요.',
                      ),
                      value: _recordingEnabled,
                      onChanged: _setRecordingEnabled,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
