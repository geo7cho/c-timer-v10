/**
 * 상담 타이머 앱 - 기기 바인딩 라이선스 서버 (Google Apps Script)
 *
 * 사용 방법은 프로젝트의 README.md "라이선스 설정" 부분을 참고하세요.
 *
 * 이 스크립트가 연결된 Google 시트에는 "licenses" 라는 이름의 시트가 있어야 하고,
 * 1행(헤더)에 아래 6개 열이 정확히 이 순서/이름으로 있어야 합니다:
 *   serial | device_id | status | note | created_at | activated_at
 *
 * status 열 값은 "활성" 또는 "차단" 을 사용합니다.
 */

function doPost(e) {
  var result;
  try {
    var body = JSON.parse(e.postData.contents);
    var action = body.action;
    var serial = String(body.serial || '').trim();
    var deviceId = String(body.deviceId || '').trim();

    var sheet = _sheet();
    var data = sheet.getDataRange().getValues();
    var col = _columns(data[0]);

    var rowIndex = -1;
    for (var r = 1; r < data.length; r++) {
      if (String(data[r][col.serial]).trim() === serial) {
        rowIndex = r;
        break;
      }
    }

    if (rowIndex === -1) {
      result = { result: 'not_found' };
    } else {
      var row = data[rowIndex];
      var status = String(row[col.status] || '').trim();
      var boundDevice = String(row[col.device_id] || '').trim();

      if (status === '차단') {
        result = { result: 'blocked' };
      } else if (action === 'activate') {
        if (boundDevice === '') {
          sheet.getRange(rowIndex + 1, col.device_id + 1).setValue(deviceId);
          sheet.getRange(rowIndex + 1, col.activated_at + 1).setValue(new Date());
          result = { result: 'ok' };
        } else if (boundDevice === deviceId) {
          result = { result: 'ok' };
        } else {
          result = { result: 'device_mismatch' };
        }
      } else if (action === 'check') {
        result = boundDevice === deviceId
          ? { result: 'ok' }
          : { result: 'device_mismatch' };
      } else {
        result = { result: 'unknown_action' };
      }
    }
  } catch (err) {
    result = { result: 'error', message: String(err) };
  }

  return ContentService
    .createTextOutput(JSON.stringify(result))
    .setMimeType(ContentService.MimeType.JSON);
}

function _sheet() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName('licenses');
  if (!sheet) {
    throw new Error('licenses 라는 이름의 시트를 찾을 수 없습니다');
  }
  return sheet;
}

function _columns(header) {
  var col = {};
  for (var i = 0; i < header.length; i++) {
    col[String(header[i]).trim()] = i;
  }
  ['serial', 'device_id', 'status', 'note', 'created_at', 'activated_at'].forEach(function(name) {
    if (!(name in col)) throw new Error('헤더에 "' + name + '" 열이 없습니다');
  });
  return col;
}

/**
 * 시트 메뉴에 "일련번호 20개 생성" 버튼을 추가합니다.
 * (Apps Script 편집기에서 이 파일을 저장한 뒤 시트를 새로고침하면 메뉴가 보입니다)
 */
function onOpen() {
  SpreadsheetApp.getUi()
    .createMenu('라이선스 관리')
    .addItem('일련번호 20개 생성', 'generateSerials')
    .addToUi();
}

function generateSerials() {
  var sheet = _sheet();
  var count = 20;
  for (var i = 0; i < count; i++) {
    var serial = 'CT-' + Utilities.getUuid().split('-')[0].toUpperCase();
    sheet.appendRow([serial, '', '활성', '', new Date(), '']);
  }
  SpreadsheetApp.getUi().alert(count + '개의 일련번호가 생성되었습니다.');
}
