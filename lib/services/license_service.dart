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

  Future<ActivationResult> activate(String serial) async {
    if (licenseServerUrl.isEmpty) {
      // 서버 주소가 아직 설정되지 않은 개발/테스트 단계
      await _setLicensed(true, serial: serial);
      return ActivationResult.ok;
    }
    final deviceId = await getOrCreateDeviceId();
    try {
      final res = await http
          .post(
            Uri.parse(licenseServerUrl),
            body: jsonEncode({
              'action': 'activate',
              'serial': serial.trim(),
              'deviceId': deviceId,
            }),
          )
          .timeout(const Duration(seconds: 12));

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      switch (body['result']) {
        case 'ok':
          await _setLicensed(true, serial: serial.trim());
          return ActivationResult.ok;
        case 'blocked':
          return ActivationResult.blocked;
        case 'device_mismatch':
          return ActivationResult.deviceMismatch;
        default:
          return ActivationResult.notFound;
      }
    } catch (_) {
      return ActivationResult.networkError;
    }
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
      final res = await http
          .post(
            Uri.parse(licenseServerUrl),
            body: jsonEncode({
              'action': 'check',
              'serial': serial,
              'deviceId': deviceId,
            }),
          )
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['result'] == 'blocked' || body['result'] == 'device_mismatch') {
        await _setLicensed(false);
      }
    } catch (_) {
      // 오프라인 등 - 그대로 둔다 (상담 중 인터넷이 없어도 앱은 계속 동작)
    }
  }
}
