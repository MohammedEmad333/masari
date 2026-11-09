import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models/deadline.dart';
import '../services/oracle_account_client.dart';
import '../services/oracle_automatic_sync.dart';
import '../services/oracle_personal_backup_codec.dart';
import '../services/task_plan_repository.dart';

/// Manual account-bound Oracle backup, independent of Firestore.
class OracleCloudBackupScreen extends StatefulWidget {
  const OracleCloudBackupScreen({
    super.key,
    required this.controller,
    required this.arabic,
    required this.autoSync,
  });

  final AppController controller;
  final bool arabic;
  final OracleAutomaticSync autoSync;

  @override
  State<OracleCloudBackupScreen> createState() => _OracleCloudBackupScreenState();
}

class _OracleCloudBackupScreenState extends State<OracleCloudBackupScreen> {
  final OracleAccountClient _client = OracleAccountClient();
  final TaskPlanRepository _plans = const TaskPlanRepository();
  bool _busy = false;
  String? _status;

  String t(String en, String ar) => widget.arabic ? ar : en;

  Future<void> _upload() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Replace Oracle backup?', 'استبدال نسخة Oracle؟')),
        content: Text(
          t(
            'This saves your manual tasks and plans on Oracle. Moodle passwords and calendar links are not included.',
            'ستُحفظ المهام والخطط اليدوية على Oracle. كلمات مرور Moodle وروابط التقويم غير مشمولة.',
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
    if (!mounted || confirmed != true) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await _client.upload(
        'personal',
        OraclePersonalBackupCodec.prepare(
          manualTasks: widget.controller.manualDeadlines,
          plans: await _plans.loadAll(),
        ),
      );
      if (mounted) {
        setState(
          () => _status = t('Saved on Oracle.', 'تم الحفظ على Oracle.'),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _status = t(
            'Backup failed. Sign in to your Oracle account first.',
            'فشل النسخ. سجل الدخول إلى حساب Oracle أولًا.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final data = await _client.download('personal');
      final restored = OraclePersonalBackupCodec.decode(data);
      final current = widget.controller.manualDeadlines
          .map((task) => task.stableKey)
          .toSet();
      var tasks = 0;
      for (final Deadline task in restored.tasks) {
        if (current.add(task.stableKey)) {
          await widget.controller.saveManualDeadline(task);
          tasks++;
        }
      }
      final existingPlans = await _plans.loadAll();
      var plans = 0;
      for (final entry in restored.plans.entries) {
        if (!existingPlans.containsKey(entry.key)) {
          await _plans.save(entry.value);
          plans++;
        }
      }
      if (mounted) {
        setState(
          () => _status = t(
            'Restored $tasks tasks and $plans plans without overwriting local items.',
            'تم استرجاع $tasks مهمة و$plans خطة دون استبدال البيانات المحلية.',
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _status = t(
            'Restore failed. Check Oracle sign-in and connection.',
            'تعذّر الاسترجاع. تحقق من تسجيل الدخول والاتصال بـ Oracle.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Delete Oracle backup?', 'حذف نسخة Oracle؟')),
        content: Text(
          t(
            'Only the server backup will be deleted. Your local tasks and plans remain.',
            'ستُحذف النسخة الموجودة على الخادم فقط. ستبقى مهامك وخططك المحلية.',
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
    setState(() => _busy = true);
    try {
      await _client.deleteBackup('personal');
      if (mounted) {
        setState(() => _status = t('Cloud backup deleted.', 'تم حذف النسخة السحابية.'));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _status = t('Deletion failed.', 'تعذّر الحذف.'));
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
    appBar: AppBar(title: Text(t('Oracle backup', 'النسخ الاحتياطي على Oracle'))),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          t(
            'Manual backup for tasks and plans only. Moodle calendar links stay on the device. Automatic synchronization is not enabled in Oracle mode yet.',
            'نسخ يدوي للمهام والخطط فقط. روابط تقويم Moodle تبقى على الجهاز. المزامنة التلقائية غير مفعلة بعد في وضع Oracle.',
          ),
        ),
        SwitchListTile(
          title: Text(t('Automatic Oracle sync', 'المزامنة التلقائية مع Oracle')),
          subtitle: Text(
            t(
              'Merge missing tasks and plans across your devices. Existing local items win conflicts; deletions do not sync yet.',
              'دمج المهام والخطط المفقودة بين أجهزتك. العناصر المحلية لا تُستبدل؛ الحذف لا يتزامن بعد.',
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
                    await widget.autoSync.setEnabled(enabled);
                    if (mounted) {
                      setState(
                        () => _status = enabled
                            ? t('Oracle sync enabled.', 'تم تفعيل مزامنة Oracle.')
                            : t('Oracle sync disabled.', 'تم إيقاف مزامنة Oracle.'),
                      );
                    }
                  } catch (_) {
                    if (mounted) {
                      setState(
                        () => _status = t(
                          'Could not update sync. Sign in to Oracle first.',
                          'تعذّر تغيير المزامنة. سجّل الدخول إلى Oracle أولًا.',
                        ),
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _busy ? null : _upload,
          icon: const Icon(Icons.cloud_upload_outlined),
          label: Text(t('Back up to Oracle', 'نسخ إلى Oracle')),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : _restore,
          icon: const Icon(Icons.cloud_download_outlined),
          label: Text(t('Restore missing items', 'استرجاع العناصر غير الموجودة')),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : _deleteBackup,
          icon: const Icon(Icons.delete_outline),
          label: Text(t('Delete Oracle backup', 'حذف نسخة Oracle')),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(_status!, textAlign: TextAlign.center),
          ),
      ],
    ),
  );
}
