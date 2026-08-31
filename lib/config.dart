/// 라이선스 서버(Google Apps Script 웹앱) 주소.
///
/// README의 "라이선스 설정" 안내대로 Google 시트 + Apps Script를 배포한 뒤,
/// 배포 시 발급되는 웹앱 URL(https://script.google.com/macros/s/.../exec)을
/// 아래에 붙여넣으세요. 값을 채우지 않으면 라이선스 확인 없이 바로 앱이
/// 실행됩니다(테스트용 기본값).
const String licenseServerUrl = 'https://script.google.com/macros/s/AKfycbzyM4SfR8gRg0o3gDG0wnh9DQlH2JGkHYKGU3frGInMBqs15JfCjRetZx9W7tT2qSwd/exec';

/// true로 두면 licenseServerUrl이 비어 있을 때 라이선스 화면을 건너뜁니다.
/// 실제 배포 전에는 licenseServerUrl을 채운 뒤 이 값을 신경 쓰지 않아도 됩니다.
const bool skipLicenseWhenUrlEmpty = true;
