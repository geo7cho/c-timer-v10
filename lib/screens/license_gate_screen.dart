import 'package:flutter/material.dart';

import '../services/license_service.dart';

/// 최초 실행 시(또는 라이선스가 해제된 경우) 표시되는 일련번호 입력 화면.
class LicenseGateScreen extends StatefulWidget {
  final VoidCallback onActivated;

  const LicenseGateScreen({super.key, required this.onActivated});

  @override
  State<LicenseGateScreen> createState() => _LicenseGateScreenState();
}

class _LicenseGateScreenState extends State<LicenseGateScreen> {
  final _controller = TextEditingController();
  final _service = LicenseService();
  bool _checking = false;
  String? _error;
  String? _deviceIdPreview;

  @override
  void initState() {
    super.initState();
    _service.getOrCreateDeviceId().then((id) {
      if (mounted) setState(() => _deviceIdPreview = id);
    });
  }

  Future<void> _submit() async {
    final serial = _controller.text.trim();
    if (serial.isEmpty) {
      setState(() => _error = '일련번호를 입력해주세요');
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });

    final result = await _service.activate(serial);

    if (!mounted) return;
    setState(() => _checking = false);

    switch (result) {
      case ActivationResult.ok:
        widget.onActivated();
        break;
      case ActivationResult.notFound:
        setState(() => _error = '등록되지 않은 일련번호입니다');
        break;
      case ActivationResult.blocked:
        setState(() => _error = '차단된 일련번호입니다. 관리자에게 문의해주세요');
        break;
      case ActivationResult.deviceMismatch:
        setState(() => _error = '이 번호는 이미 다른 기기에서 사용 중입니다');
        break;
      case ActivationResult.networkError:
        setState(() => _error = '인터넷 연결을 확인한 뒤 다시 시도해주세요');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 56),
                const SizedBox(height: 16),
                Text('상담 타이머 인증', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text(
                  '관리자에게 받은 일련번호를 입력해주세요.\n이 기기에서 최초 1회만 입력하면 됩니다.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _controller,
                  textAlign: TextAlign.center,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '예: CT-A1B2C3',
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _checking ? null : _submit,
                    child: _checking
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('인증하기'),
                  ),
                ),
                if (_deviceIdPreview != null) ...[
                  const SizedBox(height: 24),
                  Text(
                    '기기 식별 코드 (문의 시 알려주세요)\n$_deviceIdPreview',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
