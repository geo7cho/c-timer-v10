import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../config.dart';

enum ActivationResult {
  ok,
  notFound, // 존재하지 않는 일련번호
  blocked, // 관리자가 차단한 번호
  deviceMismatch, // 이미 다른 기기에 사용 중
  networkError,
}

/// 활성화 시도의 결과 + 실패 시 화면에 보여줄 진단용 상세 메시지.
class ActivationOutcome {
  final ActivationResult result;
  final String? detail;
  const ActivationOutcome(this.result, {this.detail});
}

/// 기기 바인딩형 온라인 라이선스(일련번호) 서비스.
///
/// 동작 방식:
/// 1) 이 앱이 설치된 기기마다 고유한 deviceId(UUID)를 한 번 생성해 로컬에 저장한다.
///    (하드웨어 시리얼이 아닌 "이 앱 설치본"에 대한 고유 ID이며,
///     앱을 삭제 후 재설치하면 새 ID가 생성됩니다 - 관리자가 시트에서
///     device_id 칸을 비워주면 그 번호로 재인증할 수 있습니다.)
/// 2) 최초 실행 시 사용자가 일련번호를 입력하면 서버(Apps Script)에
///    activate 요청을 보내 그 번호에 deviceId를 묶는다.
/// 3) 한 번 인증되면 로컬에 저장되어, 이후에는 오프라인에서도 바로 실행된다.
///    단, 실행할 때마다 백그라운드로 서버에 재확인을 시도해서
///    관리자가 차단했거나 다른 기기에서 이미 활성화된 경우 다음 실행부터
///    다시 인증을 요구하도록 한다.
class LicenseService {
  static const _kDeviceId = 'license_device_id';
  static const _kLicensed = 'license_activated';
  static const _kSerial = 'license_serial';

  Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_kDeviceId);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await prefs.setString(_kDeviceId, id);
    }
    return id;
  }

  Future<bool> isLicensedLocally() async {
    if (licenseServerUrl.isEmpty && skipLicenseWhenUrlEmpty) return true;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kLicensed) ?? false;
  }

  Future<void> _setLicensed(bool value, {String? serial}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLicensed, value);
    if (serial != null) await prefs.setString(_kSerial, serial);
  }

  Future<ActivationOutcome> activate(String serial) async {
    if (licenseServerUrl.isEmpty) {
      // 서버 주소가 아직 설정되지 않은 개발/테스트 단계
      await _setLicensed(true, serial: serial);
      return const ActivationOutcome(ActivationResult.ok);
    }
    final normalizedSerial = serial.trim().toUpperCase();
    final deviceId = await getOrCreateDeviceId();
    http.Response res;
    try {
      res = await _postJsonFollowingRedirects(
        Uri.parse(licenseServerUrl),
        {
          'action': 'activate',
          'serial': normalizedSerial,
          'deviceId': deviceId,
        },
        const Duration(seconds: 12),
      );
    } catch (e) {
      // 여기 들어오면 진짜로 서버에 도달조차 못한 것 (오프라인, DNS 실패, 타임아웃 등)
      return ActivationOutcome(ActivationResult.networkError, detail: '요청 실패: ${e}');
    }

    try {
      if (res.statusCode != 200) {
        return ActivationOutcome(
          ActivationResult.networkError,
          detail: 'HTTP ${res.statusCode}\n${_snippet(res.body)}',
        );
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      switch (body['result']) {
        case 'ok':
          await _setLicensed(true, serial: normalizedSerial);
          return const ActivationOutcome(ActivationResult.ok);
        case 'blocked':
          return const ActivationOutcome(ActivationResult.blocked);
        case 'device_mismatch':
          return const ActivationOutcome(ActivationResult.deviceMismatch);
        case 'not_found':
          return const ActivationOutcome(ActivationResult.notFound);
        default:
          return ActivationOutcome(
            ActivationResult.notFound,
            detail: '서버 응답: ${_snippet(res.body)}',
          );
      }
    } catch (e) {
      // 서버 응답이 JSON이 아니었던 경우 (예: 구글 로그인 페이지, 오류 HTML 등)
      // → 배포 URL은 맞지만 "액세스 권한" 설정 문제일 가능성이 높음
      return ActivationOutcome(
        ActivationResult.networkError,
        detail: '응답 해석 실패 (HTTP ${res.statusCode}): ${_snippet(res.body)}',
      );
    }
  }

  String _snippet(String s) => s.length > 200 ? '${s.substring(0, 200)}...' : s;

  /// Google Apps Script 웹 앱은 POST 요청에 대해 실제 결과를
  /// script.googleusercontent.com 쪽 임시 주소로 302 리다이렉트하는 경우가 있다.
  /// 일부 HTTP 클라이언트(안드로이드의 dart:io 포함)는 POST 요청에 대해서는
  /// 리다이렉트를 자동으로 따라가지 않으므로, 직접 Location 헤더를 읽어
  /// 최종 결과가 나올 때까지 따라간다.
  Future<http.Response> _postJsonFollowingRedirects(
    Uri uri,
    Map<String, dynamic> payload,
    Duration timeout,
  ) async {
    var res = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(timeout);

    var hops = 0;
    while (res.statusCode >= 300 && res.statusCode < 400 && hops < 5) {
      final location = res.headers['location'];
      if (location == null || location.isEmpty) break;
      res = await http.get(Uri.parse(location)).timeout(timeout);
      hops++;
    }
    return res;
  }

  /// 앱 시작 시 백그라운드로 호출 - 실패하거나 네트워크가 없어도 무시하고
  /// 기존 로컬 라이선스 상태를 그대로 유지한다. 서버가 명시적으로
  /// "차단됨" 또는 "다른 기기로 이전됨"이라고 답할 때만 로컬 인증을 해제한다.
  Future<void> revalidateInBackground() async {
    if (licenseServerUrl.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final serial = prefs.getString(_kSerial);
    final licensed = prefs.getBool(_kLicensed) ?? false;
    if (!licensed || serial == null) return;

    final deviceId = await getOrCreateDeviceId();
    try {
      final res = await _postJsonFollowingRedirects(
        Uri.parse(licenseServerUrl),
        {
          'action': 'check',
          'serial': serial,
          'deviceId': deviceId,
        },
        const Duration(seconds: 8),
      );
      if (res.statusCode != 200) return;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['result'] == 'blocked' || body['result'] == 'device_mismatch') {
        await _setLicensed(false);
      }
    } catch (_) {
      // 오프라인 등 - 그대로 둔다 (상담 중 인터넷이 없어도 앱은 계속 동작)
    }
  }
}
