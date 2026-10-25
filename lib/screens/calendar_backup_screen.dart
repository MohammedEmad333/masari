import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/calendar_repository.dart';
import '../services/encrypted_calendar_backup.dart';
import '../services/google_account_service.dart';

/// Optional, passphrase-encrypted backups of private Moodle calendar feeds.
class CalendarBackupScreen extends StatefulWidget {
  const CalendarBackupScreen({super.key, required this.arabic});
  final bool arabic;

  @override
  State<CalendarBackupScreen> createState() => _CalendarBackupScreenState();
}

class _CalendarBackupScreenState extends State<CalendarBackupScreen> {
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
              Text(t(
                'Use at least 12 characters. You must remember this password to recover links on another device. It cannot be reset.',
                'استخدم 12 حرفًا على الأقل. يجب تذكّر كلمة المرور لاسترجاع الروابط على جهاز آخر، ولا يمكن إعادة تعيينها.',
              )),
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

  Future<User?> _currentUser() async {
    await GoogleAccountService.instance.initialize();
    return FirebaseAuth.instance.currentUser;
  }

  Future<void> _transfer({required bool upload}) async {
    final user = await _currentUser();
    if (!mounted) return;
    if (user == null) {
      setState(() => _message = t(
        'Sign in with Google first.', 'سجّل الدخول باستخدام Google أولًا.',
      ));
      return;
    }
    final password = await _askPassword();
    if (!mounted || password == null) return;

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final repository = CalendarRepository();
      final cloud = EncryptedCalendarBackup(FirebaseFirestore.instance);
      if (upload) {
        final primary = await repository.loadCalendarUrl();
        final secondary = await repository.loadAdditionalCalendarUrls();
        final urls = <String>{if (primary != null) primary, ...secondary}.toList();
        if (urls.isEmpty) {
          if (mounted) {
            setState(() => _message = t(
              'There are no calendar URLs to save.',
              'لا توجد روابط تقويم لحفظها.',
            ));
          }
          return;
        }
        await cloud.upload(user: user, urls: urls, passphrase: password);
        if (mounted) {
          setState(() => _message = t(
            'Encrypted calendar URLs saved to your Google account.',
            'تم حفظ روابط التقويم مشفّرة في حساب Google.',
          ));
        }
      } else {
        final urls = await cloud.download(user: user, passphrase: password);
        if (urls == null || urls.isEmpty) {
          if (mounted) setState(() => _message = t('No backup found.', 'لا توجد نسخة محفوظة.'));
          return;
        }
        final primary = await repository.loadCalendarUrl();
        final secondary = (await repository.loadAdditionalCalendarUrls()).toSet();
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
          setState(() => _message = t(
            'Restored $restored links. Restart Masari to load the restored calendars.',
            'تم استرجاع $restored رابط. أعد تشغيل مساري لتحميل التقاويم المسترجعة.',
          ));
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = t(
          'Operation failed. Check your password, URL validity and Firestore connection.',
          'فشلت العملية. تحقق من كلمة المرور وصلاحية الروابط واتصال Firestore.',
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(t('Calendar link backup', 'نسخ روابط التقويم'))),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(t(
          'Moodle calendar links contain access tokens. Masari encrypts them on your device before uploading. The encryption password is not saved. Never reuse your Google or Moodle password.',
          'تحتوي روابط تقويم Moodle على رموز دخول خاصة. يشفّرها مساري على جهازك قبل رفعها. لا تُحفظ كلمة مرور التشفير. لا تستخدم كلمة مرور Google أو Moodle.',
        )),
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
        if (_busy) const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
        if (_message != null) Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(_message!, textAlign: TextAlign.center),
        ),
      ],
    ),
  );
}
