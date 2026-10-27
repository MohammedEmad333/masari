import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../services/automatic_google_sync.dart';
import 'calendar_backup_screen.dart';
import '../services/google_account_service.dart';
import '../services/optional_cloud_backup.dart';
import '../services/task_plan_repository.dart';

/// Cloud backup is opt-in; it does not run when the calendar refreshes.
class CloudBackupScreen extends StatefulWidget {
  const CloudBackupScreen({
    super.key,
    required this.controller,
    required this.arabic,
    required this.autoSync,
  });
  final AppController controller;
  final bool arabic;
  final AutomaticGoogleSync autoSync;

  @override
  State<CloudBackupScreen> createState() => _CloudBackupScreenState();
}

class _CloudBackupScreenState extends State<CloudBackupScreen> {
  bool _busy = false;
  String? _status;
  String t(String en, String ar) => widget.arabic ? ar : en;

  Future<User?> _user() async {
    await GoogleAccountService.instance.initialize();
    return FirebaseAuth.instance.currentUser;
  }

  Future<void> _upload() async {
    final user = await _user();
    if (!mounted) return;
    if (user == null) {
      setState(
        () => _status = t(
          'Sign in with Google first.',
          'سجّل الدخول بحساب Google أولًا.',
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Replace cloud backup?', 'استبدال النسخة السحابية؟')),
        content: Text(
          t(
            'This replaces the previous cloud backup for this Google account. Moodle links and credentials are never uploaded.',
            'سيتم استبدال النسخة السابقة لهذا الحساب. لن تُرفع روابط Moodle أو بيانات تسجيل الدخول.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('Cancel', 'إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('Back up', 'نسخ احتياطي')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final plans = await const TaskPlanRepository().loadAll();
      await OptionalCloudBackup(FirebaseFirestore.instance).upload(
        user: user,
        manualTasks: widget.controller.manualDeadlines,
        plans: plans,
      );
      if (mounted) {
        setState(
          () => _status = t('Backup saved.', 'تم حفظ النسخة الاحتياطية.'),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _status = t(
            'Backup failed. Check Firestore access.',
            'فشل النسخ. تحقق من صلاحيات Firestore.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final user = await _user();
    if (!mounted) return;
    if (user == null) {
      setState(
        () => _status = t(
          'Sign in with Google first.',
          'سجّل الدخول بحساب Google أولًا.',
        ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final snapshot = await OptionalCloudBackup(
        FirebaseFirestore.instance,
      ).download(user);
      final existing = widget.controller.manualDeadlines
          .map((task) => task.stableKey)
          .toSet();
      var importedTasks = 0;
      for (final task in snapshot.tasks) {
        if (existing.add(task.stableKey)) {
          await widget.controller.saveManualDeadline(task);
          importedTasks++;
        }
      }
      final repository = const TaskPlanRepository();
      final current = await repository.loadAll();
      var importedPlans = 0;
      for (final entry in snapshot.plans.entries) {
        if (!current.containsKey(entry.key)) {
          await repository.save(entry.value);
          importedPlans++;
        }
      }
      if (mounted) {
        setState(
          () => _status = t(
            'Imported $importedTasks tasks and $importedPlans plans. Existing items were not replaced.',
            'تم استيراد $importedTasks مهمة و$importedPlans خطة، دون استبدال العناصر الموجودة.',
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _status = t(
            'Restore failed. Check Firestore access.',
            'فشل الاسترجاع. تحقق من صلاحيات Firestore.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(t('Cloud backup', 'النسخ الاحتياطي السحابي'))),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          t(
            'Tasks and plans can be backed up here. Private calendar URLs can be backed up separately with client-side encryption and a password you choose. Moodle passwords and cached Moodle events stay on this device. Backups are manual.',
            'يمكن حفظ المهام والخطط هنا. كما يمكن حفظ روابط التقويم بشكل منفصل بعد تشفيرها بكلمة مرور تختارها. كلمات مرور Moodle والمواعيد المخزنة تبقى على الجهاز. النسخ يدوي.',
          ),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: Text(
            t('Automatic Google sync', 'المزامنة التلقائية مع Google'),
          ),
          subtitle: Text(
            t(
              'Automatically merge missing personal tasks and plans on launch, when you return to the app, and after edits. Requires Google sign-in and internet. Deletions and simultaneous edits are not synchronized yet. Moodle calendar links remain encrypted and manual.',
              'دمج المهام والخطط المفقودة تلقائيًا عند فتح التطبيق والعودة إليه وبعد التعديل. تتطلب حساب Google والإنترنت. حذف العناصر وتعديل العنصر نفسه على جهازين غير مدعومين بعد. روابط Moodle تبقى مشفّرة وبنسخ يدوي.',
            ),
          ),
          value: widget.autoSync.enabled,
          onChanged: _busy
              ? null
              : (enabled) async {
                  setState(() {
                    _busy = true;
                    _status = null;
                  });
                  try {
                    if (enabled && await _user() == null) {
                      if (!mounted) return;
                      setState(
                        () => _status = t(
                          'Sign in with Google before enabling sync.',
                          'سجّل الدخول بحساب Google قبل تفعيل المزامنة.',
                        ),
                      );
                      return;
                    }
                    await widget.autoSync.setEnabled(enabled);
                    if (mounted)
                      setState(
                        () => _status = enabled
                            ? t(
                                'Automatic sync enabled.',
                                'تم تفعيل المزامنة التلقائية.',
                              )
                            : t(
                                'Automatic sync disabled.',
                                'تم إيقاف المزامنة التلقائية.',
                              ),
                      );
                  } catch (_) {
                    if (mounted)
                      setState(
                        () => _status = t(
                          'Unable to change automatic sync settings.',
                          'تعذّر تغيير إعدادات المزامنة التلقائية.',
                        ),
                      );
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _busy ? null : _upload,
          icon: const Icon(Icons.cloud_upload_outlined),
          label: Text(t('Back up to Google account', 'نسخ إلى حساب Google')),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : _restore,
          icon: const Icon(Icons.cloud_download_outlined),
          label: Text(
            t('Restore missing items', 'استرجاع العناصر غير الموجودة'),
          ),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CalendarBackupScreen(arabic: widget.arabic),
                  ),
                ),
          icon: const Icon(Icons.enhanced_encryption_outlined),
          label: Text(
            t(
              'Encrypted Moodle calendar links',
              'حفظ روابط تقويم Moodle بشكل مشفّر',
            ),
          ),
        ),
        if (_busy)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(),
            ),
          ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Text(_status!, textAlign: TextAlign.center),
          ),
      ],
    ),
  );
}
