import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/license_gate_screen.dart';
import 'services/license_service.dart';

void main() {
  runApp(const CounselingTimerApp());
}

class CounselingTimerApp extends StatelessWidget {
  const CounselingTimerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '상담 타이머',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF3D6BFF),
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF6F7FB),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF3D6BFF),
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      home: const AppGate(),
    );
  }
}

/// 앱 시작 시 로컬에 저장된 라이선스 상태를 확인해
/// 인증 화면 또는 홈 화면으로 분기하는 게이트 위젯.
class AppGate extends StatefulWidget {
  const AppGate({super.key});

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  final _licenseService = LicenseService();
  bool? _licensed; // null = 확인 중

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final ok = await _licenseService.isLicensedLocally();
    if (mounted) setState(() => _licensed = ok);
    // 화면 전환을 막지 않고 백그라운드에서 서버 재확인 (실패해도 무시됨)
    unawaited(_licenseService.revalidateInBackground());
  }

  @override
  Widget build(BuildContext context) {
    if (_licensed == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_licensed == false) {
      return LicenseGateScreen(
        onActivated: () => setState(() => _licensed = true),
      );
    }
    return const HomeScreen();
  }
}
