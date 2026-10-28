import 'package:flutter/material.dart';

import '../services/ai_assistant_client.dart';
import '../services/oracle_ai_pairing_client.dart';

class OracleAiPairingScreen extends StatefulWidget {
  const OracleAiPairingScreen({super.key, required this.arabic});

  final bool arabic;

  @override
  State<OracleAiPairingScreen> createState() => _OracleAiPairingScreenState();
}

class _OracleAiPairingScreenState extends State<OracleAiPairingScreen> {
  final _code = TextEditingController();
  final _client = OracleAiPairingClient();
  bool _busy = false;
  String? _error;

  String tr(String en, String ar) => widget.arabic ? ar : en;

  @override
  void dispose() {
    _code.dispose();
    _client.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _client.pair(_code.text);
      if (!mounted) return;
      _code.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Device paired.', 'تم ربط الجهاز بنجاح.'))),
      );
      Navigator.of(context).pop(true);
    } on AiAssistantException catch (error) {
      if (mounted) {
        setState(() {
          _error = switch (error.code) {
            'invalid_pairing_code' => tr(
              'Invalid or expired pairing code.',
              'رمز الربط غير صحيح أو انتهت صلاحيته.',
            ),
            'quota_exceeded' => tr(
              'Too many attempts. Try later.',
              'محاولات كثيرة. حاول لاحقًا.',
            ),
            _ => tr('Unable to pair this device.', 'تعذّر ربط هذا الجهاز.'),
          };
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Pair AI assistant', 'ربط مساعد مساري'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            tr(
              'Enter the one-time code issued from your trusted Oracle server. '
                  'The code expires after 10 minutes. Never share it.',
              'أدخل رمز الربط الذي أصدرته من خادم Oracle الموثوق. '
                  'تنتهي صلاحيته بعد 10 دقائق. لا تشاركه مع أحد.',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _code,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.visiblePassword,
            decoration: InputDecoration(
              labelText: tr('One-time pairing code', 'رمز الربط لمرة واحدة'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _pair,
            child: Text(tr('Pair device', 'ربط الجهاز')),
          ),
          if (_busy) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
