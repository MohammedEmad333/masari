import 'dart:async';
import '../models/deadline.dart';
import '../services/moodle_session_events.dart';
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
    required this.onImport,
  });

  final String moodleServer;
  final bool isArabic;
  final Future<void> Function(List<Deadline>) onImport;

  @override
  State<MoodleSessionPilotScreen> createState() =>
      _MoodleSessionPilotScreenState();
}

class _MoodleSessionPilotScreenState extends State<MoodleSessionPilotScreen> {
  late final WebViewController _webView;
  bool _busy = true;
  bool _dashboardReached = false;
  bool _importing = false;
  int? _importedCount;
  Completer<String>? _pendingImport;
  String? _error;

  String t(String english, String arabic) => widget.isArabic ? arabic : english;

  @override
  void initState() {
    super.initState();
    final login = MoodleBrowserLogin.universityLoginUrl(widget.moodleServer)!;
    _webView = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'MoodleSessionBridge',
        onMessageReceived: (message) {
          final pending = _pendingImport;
          if (pending != null && !pending.isCompleted) {
            pending.complete(message.message);
          }
        },
      )
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
            if (error.isForMainFrame != true || !mounted) return;
            setState(() {
              _busy = false;
              _error = error.description;
            });
          },
        ),
      )
      ..loadRequest(login);
  }

  Future<void> _importEvents() async {
    if (_importing) return;
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final current = await _webView.currentUrl();
      final login = MoodleBrowserLogin.universityLoginUrl(
        widget.moodleServer,
      )!;
      final page = Uri.tryParse(current ?? '');
      if (page == null ||
          page.scheme != 'https' ||
          page.host != login.host ||
          page.port != login.port) {
        throw const FormatException('Open the Moodle dashboard first.');
      }
      // Runs entirely inside the authenticated first-party Moodle origin.
      // The sesskey is used solely by Moodle AJAX; never returned to Flutter.
      final response = Completer<String>();
      _pendingImport = response;
      const javascript = r"""
        (async () => {
          const sesskey = window.M?.cfg?.sesskey;
          if (!sesskey) throw Error('No authenticated Moodle sesskey');
          const now = new Date();
          const events = [];
          const visited = new Set();
          for (let offset = 0; offset < 3; offset++) {
            const month = new Date(now.getFullYear(), now.getMonth() + offset, 1);
            const payload = [{
              index: 0,
              methodname: 'core_calendar_get_calendar_monthly_view',
              args: {
                year: month.getFullYear(),
                month: month.getMonth() + 1,
                courseid: 1,
                categoryid: 0,
                includenavigation: false,
                mini: true
              }
            }];
            const response = await fetch(
              new URL('lib/ajax/service.php?sesskey=' +
                encodeURIComponent(sesskey), window.M.cfg.wwwroot + '/'),
              { method: 'POST', credentials: 'same-origin',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify(payload) }
            );
            if (!response.ok) throw Error('Moodle calendar unavailable');
            const result = await response.json();
            if (!Array.isArray(result) || result[0]?.error)
              throw Error('Moodle did not allow calendar access');
            for (const week of (result[0]?.data?.weeks ?? [])) {
              for (const day of (week.days ?? [])) {
                for (const ev of (day.events ?? [])) {
                  const stamp = Number(ev.timestart);
                  if (!stamp || stamp * 1000 < Date.now()) continue;
                  const key = String(ev.id ?? ev.name + stamp);
                  if (visited.has(key)) continue;
                  visited.add(key);
                  events.push({
                    id: Number(ev.id) || 0,
                    name: String(ev.name || ''),
                    timestart: stamp,
                    course: String(ev.course?.fullname || ''),
                    url: String(ev.url || ev.viewurl || '')
                  });
                }
              }
            }
          }
          MoodleSessionBridge.postMessage(JSON.stringify(events));
        })().catch(() => MoodleSessionBridge.postMessage('null'))
      """;
      await _webView.runJavaScript(javascript);
      final raw = await response.future.timeout(const Duration(seconds: 40));
      final deadlines = MoodleSessionEvents.parse(raw, login.resolve('../'));
      await widget.onImport(deadlines);
      if (!mounted) return;
      setState(() => _importedCount = deadlines.length);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = t(
          'Could not import Moodle calendar events. Please use iCalendar instead.',
          'تعذّر استيراد مواعيد Moodle. استخدم رابط iCalendar بدلًا منه.',
        ),
      );
    } finally {
      _pendingImport = null;
      if (mounted) setState(() => _importing = false);
    }
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
          leading: IconButton(icon: const Icon(Icons.close), onPressed: _exit),
          title: Text(
            t('Experimental Moodle session', 'جلسة Moodle التجريبية'),
          ),
        ),
        body: Column(
          children: [
            if (_busy) const LinearProgressIndicator(),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _dashboardReached
                    ? t(
                        'Dashboard reached. Import deadlines below. This is a one-time import, not automatic sync.',
                        'تم الوصول للوحة الطالب. استورد المواعيد أدناه. الاستيراد يدوي وليس مزامنة تلقائية.',
                      )
                    : t(
                        'Sign in on your university website. This browser session stays separate from the app. No password is saved.',
                        'سجّل الدخول في موقع الجامعة. هذه الجلسة منفصلة عن التطبيق ولا تُحفظ كلمة المرور.',
                      ),
              ),
            ),
            if (_error != null)
              Padding(padding: const EdgeInsets.all(8), child: Text(_error!)),
            if (_importedCount != null)
              Text(
                t(
                  'Imported $_importedCount events.',
                  'تم استيراد $_importedCount موعدًا.',
                ),
              ),
            Expanded(child: WebViewWidget(controller: _webView)),
            FilledButton.icon(
              onPressed: _importing ? null : _importEvents,
              icon: const Icon(Icons.download_rounded),
              label: Text(
                t('Import upcoming deadlines', 'استيراد المواعيد القادمة'),
              ),
            ),
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
