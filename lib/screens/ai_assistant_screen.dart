import 'package:flutter/material.dart';

import '../services/ai_assistant_client.dart';
import '../services/google_oracle_auth_client.dart';
import '../services/google_account_service.dart';
import '../services/oracle_ai_session_store.dart';
import 'google_account_screen.dart';
import 'oracle_ai_pairing_screen.dart';

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
  final List<({String question, String answer})> _history = [];
  String? _error;
  bool _oracleConnected = false;
  bool _connectingGoogle = false;

  @override
  void initState() {
    super.initState();
    _refreshConnection();
    if (GoogleOracleAuthClient.enabled) _connectGoogle(silent: true);
  }

  Future<void> _connectGoogle({bool silent = false}) async {
    if (_connectingGoogle) return;
    setState(() => _connectingGoogle = true);
    final client = GoogleOracleAuthClient();
    try {
      await GoogleAccountService.instance.initialize();
      if (GoogleAccountService.instance.currentUser == null) {
        if (silent) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => GoogleAccountScreen(arabic: widget.arabic),
          ),
        );
      }
      if (GoogleAccountService.instance.currentUser == null) return;
      await client.exchange();
      await _refreshConnection();
    } on AiAssistantException catch (error) {
      if (mounted && !silent) setState(() => _error = _message(error.code));
    } catch (_) {
      if (mounted && !silent) {
        setState(
          () =>
              _error = t('Google connection failed.', 'تعذّر ربط حساب Google.'),
        );
      }
    } finally {
      client.dispose();
      if (mounted) setState(() => _connectingGoogle = false);
    }
  }

  Future<void> _refreshConnection() async {
    final session = await OracleAiSessionStore().read();
    if (mounted) setState(() => _oracleConnected = session?.isValid ?? false);
  }

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
      _error = null;
    });
    final question = _question.text.trim();
    try {
      final answer = await _client.ask(
        message: _question.text,
        language: widget.arabic ? 'ar' : 'en',
        consent: _consent,
      );
      if (mounted) {
        setState(() => _history.add((question: question, answer: answer)));
        _question.clear();
      }
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
        await _refreshConnection();
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
      case 'oracle_session_expired':
        return t(
          'Your Oracle AI session has expired or was revoked. Re-pair the device.',
          'انتهت جلسة مساعد Oracle أو أُلغيت. يلزم إعادة ربط الجهاز.',
        );
      case 'session_storage_error':
        return t(
          'Secure session storage is unavailable.',
          'تعذّر الوصول إلى التخزين الآمن لجلسة المساعد.',
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

  // Lightweight display formatting for model responses. Do not interpret HTML
  // or execute links: all content remains plain, selectable text.
  Widget _answerText(String value) {
    final base = DefaultTextStyle.of(context).style;
    final spans = <TextSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*|\*([^*\n]+)\*');
    var cursor = 0;
    for (final match in pattern.allMatches(value)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: value.substring(cursor, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(1) ?? match.group(2) ?? '',
          style: match.group(1) != null
              ? base.copyWith(fontWeight: FontWeight.bold)
              : base.copyWith(fontStyle: FontStyle.italic),
        ),
      );
      cursor = match.end;
    }
    if (cursor < value.length) {
      spans.add(TextSpan(text: value.substring(cursor)));
    }
    return Directionality(
      textDirection: widget.arabic ? TextDirection.rtl : TextDirection.ltr,
      child: SelectableText.rich(
        TextSpan(style: base, children: spans),
        textAlign: TextAlign.start,
      ),
    );
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
          const SizedBox(height: 12),
          Text(
            _oracleConnected
                ? t('Connected with Oracle', 'متصل عبر Oracle')
                : t(
                    'Oracle not paired — Google sign-in may be required',
                    'Oracle غير مرتبط — قد يلزم تسجيل Google',
                  ),
          ),
          const SizedBox(height: 12),
          if (GoogleOracleAuthClient.enabled)
            OutlinedButton.icon(
              onPressed: _loading || _connectingGoogle
                  ? null
                  : () => _connectGoogle(),
              icon: const Icon(Icons.account_circle_outlined),
              label: Text(
                t('Continue with Google', 'المتابعة باستخدام Google'),
              ),
            ),
          if (!GoogleOracleAuthClient.enabled)
            OutlinedButton.icon(
              onPressed: _loading
                  ? null
                  : () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              OracleAiPairingScreen(arabic: widget.arabic),
                        ),
                      );
                      await _refreshConnection();
                    },
              icon: const Icon(Icons.phonelink_lock_outlined),
              label: Text(t('Pair AI device', 'ربط جهاز المساعد')),
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
          for (final item in _history) ...[
            const SizedBox(height: 16),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(item.question),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _answerText(item.answer),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
