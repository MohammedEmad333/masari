import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/moodle_browser_login.dart';

/// Isolated, experimental Moodle browser session.
/// Passwords, cookies and sesskeys are never read into Dart or sent to a server.
class MoodleSessionPilotScreen extends StatefulWidget {
  const MoodleSessionPilotScreen({
    super.key,
    required this.moodleServer,
    required this.isArabic,
  });

  final String moodleServer;
  final bool isArabic;

  @override
  State<MoodleSessionPilotScreen> createState() =>
      _MoodleSessionPilotScreenState();
}

class _MoodleSessionPilotScreenState extends State<MoodleSessionPilotScreen> {
  late final WebViewController _webView;
  bool _busy = true;
  bool _dashboardReached = false;
  String? _error;

  String t(String english, String arabic) =>
      widget.isArabic ? arabic : english;

  @override
  void initState() {
    super.initState();
    final login = MoodleBrowserLogin.universityLoginUrl(
      widget.moodleServer,
    )!;
    _webView = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _busy = true);
          },
          onPageFinished: (url) {
            if (!mounted) return;
            final current = Uri.tryParse(url);
            final sameHost =
                current != null &&
                current.scheme == 'https' &&
                current.host == login.host &&
                current.port == login.port;
            setState(() {
              _busy = false;
              if (sameHost && current.path.endsWith('/my/')) {
                _dashboardReached = true;
              }
            });
          },
          onWebResourceError: (error) {
            if (!error.isForMainFrame || !mounted) return;
            setState(() {
              _busy = false;
              _error = error.description;
            });
          },
        ),
      )
      ..loadRequest(login);
  }

  Future<void> _clearSession() async {
    await _webView.clearCache();
    await WebViewCookieManager().clearCookies();
  }

  @override
  void dispose() {
    // WebView sessions are intentionally not exported to application storage.
    // Cookie cleanup is performed on explicit exit.
    super.dispose();
  }

  Future<void> _exit() async {
    await _clearSession();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _exit,
          ),
          title: Text(t('Experimental Moodle session', 'جلسة Moodle التجريبية')),
        ),
        body: Column(
          children: [
            if (_busy) const LinearProgressIndicator(),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _dashboardReached
                    ? t(
                        'Dashboard reached. Session import is not enabled yet; use iCalendar to sync deadlines.',
                        'تم الوصول للوحة الطالب. استيراد الجلسة غير مفعّل بعد؛ استخدم iCalendar لمزامنة المهام.',
                      )
                    : t(
                        'Sign in on your university website. This browser session stays separate from the app. No password is saved.',
                        'سجّل الدخول في موقع الجامعة. هذه الجلسة منفصلة عن التطبيق ولا تُحفظ كلمة المرور.',
                      ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_error!),
              ),
            Expanded(child: WebViewWidget(controller: _webView)),
            TextButton.icon(
              onPressed: () {
                final login = MoodleBrowserLogin.universityLoginUrl(
                  widget.moodleServer,
                )!;
                _webView.loadRequest(login.resolve('../my/'));
              },
              icon: const Icon(Icons.fact_check_outlined),
              label: Text(t('Check my dashboard', 'فحص لوحة الطالب')),
            ),
          ],
        ),
      ),
    );
  }
}
