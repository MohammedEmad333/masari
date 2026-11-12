import 'package:flutter/material.dart';

import '../services/calendar_repository.dart';
import '../services/oracle_encrypted_calendar_codec.dart';
import '../services/oracle_account_client.dart';

/// Client-encrypted Moodle calendar backup on Oracle; no Firestore.
class OracleCalendarBackupScreen extends StatefulWidget {
  const OracleCalendarBackupScreen({super.key, required this.arabic});
  final bool arabic;

  @override
  State<OracleCalendarBackupScreen> createState() =>
      _OracleCalendarBackupScreenState();
}

class _OracleCalendarBackupScreenState
    extends State<OracleCalendarBackupScreen> {
  final OracleAccountClient _client = OracleAccountClient();
  bool _busy = false;
  String? _message;

  String t(String english, String arabic) => widget.arabic ? arabic : english;

  Future<String?> _askPassword() async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t('Encryption password', 'كلمة مرور التشفير')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t(
                  'Use at least 12 characters. You must remember this password to recover links on another device. It cannot be reset.',
                  'استخدم 12 حرفًا على الأقل. يجب تذكّر كلمة المرور لاسترجاع الروابط على جهاز آخر، ولا يمكن إعادة تعيينها.',
                ),
              ),
              TextField(
                controller: controller,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: t('Encryption password', 'كلمة مرور التشفير'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('Cancel', 'إلغاء')),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.length < 12) return;
                Navigator.pop(context, controller.text);
              },
              child: Text(t('Continue', 'متابعة')),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _transfer({required bool upload}) async {
    final password = await _askPassword();
    if (!mounted || password == null) return;

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final repository = CalendarRepository();
      if (upload) {
        final primary = await repository.loadCalendarUrl();
        final secondary = await repository.loadAdditionalCalendarUrls();
        final urls = <String>{?primary, ...secondary}.toList();
        if (urls.isEmpty) {
          if (mounted) {
            setState(
              () => _message = t(
                'There are no calendar URLs to save.',
                'لا توجد روابط تقويم لحفظها.',
              ),
            );
          }
          return;
        }
        final archive = await OracleEncryptedCalendarCodec.encrypt(
          urls: urls,
          passphrase: password,
        );
        await _client.upload('calendar', archive);
        if (mounted) {
          setState(
            () => _message = t(
              'Encrypted calendar URLs saved to your Oracle account.',
              'تم حفظ روابط التقويم مشفّرة في حساب Oracle.',
            ),
          );
        }
      } else {
        final archive = await _client.download('calendar');
        final urls = archive == null
            ? null
            : await OracleEncryptedCalendarCodec.decrypt(
                archive: archive,
                passphrase: password,
              );
        if (urls == null || urls.isEmpty) {
          if (mounted) {
            setState(
              () => _message = t('No backup found.', 'لا توجد نسخة محفوظة.'),
            );
          }
          return;
        }
        final primary = await repository.loadCalendarUrl();
        final secondary = (await repository.loadAdditionalCalendarUrls())
            .toSet();
        var restored = 0;
        for (final url in urls) {
          if (url == primary || secondary.contains(url)) continue;
          if (primary == null && restored == 0) {
            await repository.saveCalendarUrl(url);
          } else {
            await repository.addAdditionalCalendarUrl(url);
          }
          secondary.add(url);
          restored++;
        }
        if (mounted) {
          setState(
            () => _message = t(
              'Restored $restored links. Restart Masari to load the restored calendars.',
              'تم استرجاع $restored رابط. أعد تشغيل مساري لتحميل التقاويم المسترجعة.',
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = t(
            'Operation failed. Check your password, URL validity and Oracle connection.',
            'فشلت العملية. تحقق من كلمة المرور وصلاحية الروابط واتصال Oracle.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteCloudBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          t('Delete encrypted Oracle backup?', 'حذف نسخة Oracle المشفّرة؟'),
        ),
        content: Text(
          t(
            'This removes only the encrypted server backup. Calendar links on your device remain unchanged.',
            'سيُحذف الملف المشفّر من الخادم فقط. روابط التقويم على جهازك لن تتغير.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('Cancel', 'إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('Delete backup', 'حذف النسخة')),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _client.deleteBackup('calendar');
      if (mounted) {
        setState(
          () => _message = t('Oracle backup deleted.', 'تم حذف نسخة Oracle.'),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = t('Deletion failed.', 'تعذّر الحذف.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _client.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(t('Calendar link backup', 'نسخ روابط التقويم'))),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          t(
            'Moodle calendar links contain access tokens. Masari encrypts them on your device before uploading. The encryption password is not saved. Never reuse your Google or Moodle password.',
            'تحتوي روابط تقويم Moodle على رموز دخول خاصة. يشفّرها مساري على جهازك قبل رفعها. لا تُحفظ كلمة مرور التشفير. لا تستخدم كلمة مرور Google أو Moodle.',
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _busy ? null : () => _transfer(upload: true),
          icon: const Icon(Icons.lock_outline),
          label: Text(t('Back up encrypted links', 'نسخ الروابط المشفّرة')),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _transfer(upload: false),
          icon: const Icon(Icons.restore),
          label: Text(t('Restore encrypted links', 'استرجاع الروابط المشفّرة')),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : _deleteCloudBackup,
          icon: const Icon(Icons.delete_outline),
          label: Text(
            t('Delete encrypted Oracle backup', 'حذف نسخة Oracle المشفّرة'),
          ),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(_message!, textAlign: TextAlign.center),
          ),
      ],
    ),
  );
}
