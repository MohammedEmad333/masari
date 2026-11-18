import 'package:flutter/material.dart';

/// The four existing More-screen destinations, now with explanatory labels.
/// Navigation and consent stay in the parent screen's existing callbacks.
class MasariMoreQuickAccess extends StatelessWidget {
  const MasariMoreQuickAccess({
    super.key,
    required this.arabic,
    required this.masariAccountEnabled,
    required this.onAccount,
    required this.onBackup,
    required this.onTaskPlans,
    required this.onAssistant,
  });

  final bool arabic;
  final bool masariAccountEnabled;
  final VoidCallback onAccount;
  final VoidCallback onBackup;
  final VoidCallback onTaskPlans;
  final VoidCallback onAssistant;

  String tr(String english, String arabicText) => arabic ? arabicText : english;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: const Icon(Icons.account_circle_outlined),
          title: Text(
            masariAccountEnabled
                ? tr('Masari account', 'حساب مساري')
                : tr('Google account', 'حساب Google'),
          ),
          subtitle: Text(
            tr('Sign in and manage your account', 'تسجيل الدخول وإدارة الحساب'),
          ),
          trailing: Icon(
            arabic ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
          ),
          onTap: onAccount,
        ),
        const Divider(height: 1),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: const Icon(Icons.cloud_outlined),
          title: Text(tr('Cloud backup', 'النسخ الاحتياطي السحابي')),
          subtitle: Text(
            tr(
              'Review and restore saved backups',
              'عرض النسخ المحفوظة واستعادتها',
            ),
          ),
          trailing: Icon(
            arabic ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
          ),
          onTap: onBackup,
        ),
        const Divider(height: 1),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: const Icon(Icons.account_tree_outlined),
          title: Text(tr('Task plans', 'خطط المهام')),
          subtitle: Text(
            tr(
              'Review steps and study progress',
              'مراجعة الخطوات وتقدم الدراسة',
            ),
          ),
          trailing: Icon(
            arabic ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
          ),
          onTap: onTaskPlans,
        ),
        const Divider(height: 1),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: const Icon(Icons.auto_awesome_outlined),
          title: Text(tr('Study assistant', 'المساعد الدراسي')),
          subtitle: Text(
            tr('Ask questions with your consent', 'اطرح أسئلتك بعد الموافقة'),
          ),
          trailing: Icon(
            arabic ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
          ),
          onTap: onAssistant,
        ),
      ],
    );
  }
}
