import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/moodle_browser_login.dart';
import '../services/moodle_calendar_link.dart';

/// Guided Moodle sign-in. Only generated calendar subscription links are
/// returned to Flutter; passwords, cookies and sesskeys remain in the WebView.
class MoodleCalendarBrowser extends StatefulWidget {
  const MoodleCalendarBrowser({
    super.key,
    required this.server,
    required this.arabic,
  });

  final String server;
  final bool arabic;

  @override
  State<MoodleCalendarBrowser> createState() => _MoodleCalendarBrowserState();
}

class _MoodleCalendarBrowserState extends State<MoodleCalendarBrowser> {
  late final WebViewController _browser;
  late final Uri _login;
  late final Uri _export;
  bool _loading = true;
  bool _openedExport = false;
  String? _error;

  String t(String en, String ar) => widget.arabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _login = MoodleBrowserLogin.universityLoginUrl(widget.server)!;
    _export = MoodleCalendarLink.exportPage(widget.server)!;
    _browser = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'MasariCalendarExport',
        onMessageReceived: (message) async {
          // Reject tokens sent by any unrelated login/SSO origin.
          final current = Uri.tryParse(await _browser.currentUrl() ?? '');
          if (!mounted ||
              current == null ||
              current.scheme != 'https' ||
              current.host != _export.host ||
              current.port != _export.port) {
            return;
          }
          final link = MoodleCalendarLink.fromBrowser(
            message.message,
            widget.server,
          );
          if (link != null && mounted) Navigator.of(context).pop(link);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final url = Uri.tryParse(request.url);
            if (url == null ||
                (url.scheme != 'https' && url.scheme != 'about')) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (value) {
            if (!mounted) return;
            setState(() => _loading = false);
            final url = Uri.tryParse(value);
            if (url == null ||
                url.scheme != 'https' ||
                url.host != _export.host ||
                url.port != _export.port) {
              return;
            }
            // Only follow the authenticated Moodle dashboard to the export
            // screen; cross-site SSO pages are never inspected.
            if (!_openedExport &&
                (url.path.endsWith('/my/') ||
                    url.path.endsWith('/my/index.php'))) {
              _openedExport = true;
              _browser.loadRequest(_export);
            } else if (url.path == _export.path) {
              _scanForCalendarLink(autoGenerate: true);
            }
          },
          onWebResourceError: (error) {
            if (!mounted || error.isForMainFrame != true) return;
            setState(() {
              _loading = false;
              _error = t(
                'Unable to load the Moodle page. Check the connection and try again.',
                'تعذّر تحميل صفحة Moodle. تحقّق من الاتصال ثم حاول مجددًا.',
              );
            });
          },
        ),
      )
      ..loadRequest(_login);
  }

  Future<void> _scanForCalendarLink({bool autoGenerate = false}) async {
    // Inspect only the originating university's calendar export screen.
    final current = Uri.tryParse(await _browser.currentUrl() ?? '');
    if (current == null ||
        current.scheme != 'https' ||
        current.host != _export.host ||
        current.port != _export.port ||
        current.path != _export.path) {
      return;
    }
    const readUrl = r"""
      (() => {
        const candidates = Array.from(document.querySelectorAll(
          'input, textarea, a[href]'
        ));
        for (const el of candidates) {
          const value = (el.value || el.href || el.textContent || '').trim();
          if (value.includes('/calendar/export_execute.php') &&
              value.includes('authtoken=')) {
            MasariCalendarExport.postMessage(value);
            return true;
          }
        }
        return false;
      })();
    """;
    try {
      final found = await _browser.runJavaScriptReturningResult(readUrl);
      if (found == true || !autoGenerate) return;
      // Moodle's standard export form has a "Get calendar URL" action.
      // Clicking that action only asks Moodle to generate its own link.
      await _browser.runJavaScript(r"""
        (() => {
          const buttons = Array.from(document.querySelectorAll(
            'button, input[type="submit"]'
          ));
          const button = buttons.find((el) => {
            const label = (el.textContent || el.value || '').toLowerCase();
            return label.includes('get calendar url') ||
                   label.includes('get url address') ||
                   label.includes('الحصول على رابط');
          });
          if (button) button.click();
        })();
      """);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = t(
            'Generate a calendar URL in Moodle, then select Capture URL.',
            'أنشئ رابط التقويم داخل Moodle ثم اضغط التقاط الرابط.',
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t('Moodle calendar sign-in', 'دخول تقويم Moodle')),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_loading) const LinearProgressIndicator(),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                t(
                  'Sign in on your university website. Masari opens calendar export and captures the generated URL, when supported. Otherwise tap Get calendar URL, then Capture URL.',
                  'سجّل الدخول عبر موقع الجامعة. يفتح مساري تصدير التقويم ويلتقط الرابط عند دعمه. وإلا اضغط الحصول على رابط التقويم ثم التقاط الرابط.',
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(child: WebViewWidget(controller: _browser)),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _browser.loadRequest(_export),
                      child: Text(t('Open export', 'فتح التصدير')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _scanForCalendarLink,
                      child: Text(t('Capture URL', 'التقاط الرابط')),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
