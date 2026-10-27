import 'package:flutter/material.dart';

import '../services/ai_assistant_client.dart';
import 'google_account_screen.dart';

/// Opt-in text-only AI chat. No calendar events or tokens are included.
class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key, required this.arabic});

  final bool arabic;

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  final _question = TextEditingController();
  final _client = AiAssistantClient();
  bool _consent = false;
  bool _loading = false;
  String? _answer;
  String? _error;

  String t(String en, String ar) => widget.arabic ? ar : en;

  @override
  void dispose() {
    _question.dispose();
    _client.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    if (_loading || !_consent) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _answer = null;
      _error = null;
    });
    try {
      final answer = await _client.ask(
        message: _question.text,
        language: widget.arabic ? 'ar' : 'en',
        consent: _consent,
      );
      if (mounted) setState(() => _answer = answer);
    } on AiAssistantException catch (error) {
      if (mounted) setState(() => _error = _message(error.code));
    } catch (_) {
      if (mounted) {
        setState(() => _error = t('Unable to connect.', 'تعذّر الاتصال.'));
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _consent = false;
        });
      }
    }
  }

  String _message(String code) {
    switch (code) {
      case 'sign_in_required':
        return t(
          'Sign in with Google first.',
          'سجّل الدخول بحساب Google أولاً.',
        );
      case 'app_check_failed':
        return t(
          'App verification failed. Check Play Integrity registration or your device.',
          'فشل التحقق من التطبيق. افحص تسجيل Play Integrity أو جهازك.',
        );
      case 'quota_exceeded':
        return t('Daily or minute limit reached.', 'وصلت إلى حد الاستخدام.');
      case 'invalid_message':
        return t('Enter a shorter question.', 'أدخل سؤالًا أقصر.');
      case 'sensitive_content':
        return t(
          'Do not include links, passwords or calendar tokens.',
          'لا تُدخل روابط أو كلمات مرور أو رموز التقويم.',
        );
      case 'timeout':
        return t('The model took too long.', 'استغرق النموذج وقتًا طويلًا.');
      case 'consent_required':
        return t('Consent is required.', 'الموافقة مطلوبة.');
      default:
        return t(
          'The AI service is unavailable. Try again later.',
          'خدمة الذكاء الاصطناعي غير متاحة. حاول لاحقًا.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('Study assistant', 'المساعد الدراسي'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            t(
              'Optional online assistant. Only the question you type is '
                  'sent to the Masari proxy and the external TokenRouter model. '
                  'Do not include private information. The assistant cannot '
                  'read tasks or schedule reminders.',
              'مساعد اختياري عبر الإنترنت. يُرسل نص السؤال الذي تكتبه '
                  'فقط إلى خادم مساري ونموذج TokenRouter الخارجي. '
                  'لا تُدخل معلومات خاصة. لا يستطيع المساعد قراءة '
                  'المهام أو جدولة التذكيرات.',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _question,
            maxLines: 5,
            minLines: 2,
            maxLength: 500,
            enabled: !_loading,
            decoration: InputDecoration(
              labelText: t('Your question', 'سؤالك'),
              hintText: t(
                'How can I plan revision for an exam?',
                'كيف أُنظّم المراجعة قبل الامتحان؟',
              ),
            ),
          ),
          CheckboxListTile(
            value: _consent,
            onChanged: _loading
                ? null
                : (value) {
                    setState(() => _consent = value ?? false);
                  },
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              t(
                'I agree to send this question to an external AI provider.',
                'أوافق على إرسال هذا السؤال إلى مزوّد ذكاء اصطناعي خارجي.',
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _loading || !_consent ? null : _ask,
            icon: const Icon(Icons.send_outlined),
            label: Text(t('Ask AI', 'اسأل المساعد')),
          ),
          if (_loading) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            if (_error == _message('sign_in_required'))
              OutlinedButton.icon(
                icon: const Icon(Icons.account_circle_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => GoogleAccountScreen(arabic: widget.arabic),
                  ),
                ),
                label: Text(t('Google account', 'حساب Google')),
              ),
          ],
          if (_answer != null) ...[
            const SizedBox(height: 16),
            SelectableText(_answer!),
          ],
        ],
      ),
    );
  }
}
