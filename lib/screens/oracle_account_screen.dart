import 'package:flutter/material.dart';

import '../services/oracle_account_client.dart';
import '../services/oracle_automatic_sync.dart';

/// Account authority is Oracle/PostgreSQL, not Firebase.
class OracleAccountScreen extends StatefulWidget {
  const OracleAccountScreen({
    super.key,
    required this.arabic,
    required this.autoSync,
  });

  final bool arabic;
  final OracleAutomaticSync autoSync;

  @override
  State<OracleAccountScreen> createState() => _OracleAccountScreenState();
}

class _OracleAccountScreenState extends State<OracleAccountScreen> {
  final OracleAccountClient _account = OracleAccountClient();
  bool _busy = true;
  bool _signedIn = false;
  String? _name;
  String? _status;

  String t(String en, String ar) => widget.arabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final session = await _account.currentSession();
      if (session != null) {
        final profile = await _account.profile();
        if (!mounted) return;
        setState(() {
          _signedIn = true;
          _name = profile['displayName'] as String?;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _status = t(
            'Account unavailable. You can sign in again.',
            'الحساب غير متاح. يمكنك تسجيل الدخول مجددًا.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await _account.signIn();
      final profile = await _account.profile();
      if (mounted) {
        setState(() {
          _signedIn = true;
          _name = profile['displayName'] as String?;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _status = t(
            'Oracle sign-in failed. Check Google sign-in and connection.',
            'تعذّر تسجيل الدخول إلى Oracle. تحقق من حساب Google والاتصال.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    try {
      await _account.signOut();
      await widget.autoSync.setEnabled(false);
      if (mounted) {
        setState(() {
          _signedIn = false;
          _name = null;
          _status = t('Signed out.', 'تم تسجيل الخروج.');
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Delete Masari account?', 'حذف حساب مساري؟')),
        content: Text(
          t(
            'Your Oracle account and cloud backups will be deleted. Tasks and calendars stored only on this device will remain. This cannot be undone.',
            'سيُحذف حساب Oracle والنسخ السحابية. المهام والتقاويم المخزنة على هذا الجهاز ستبقى. لا يمكن التراجع عن الحذف.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('Cancel', 'إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('Delete account', 'حذف الحساب')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _account.deleteAccount();
      await widget.autoSync.setEnabled(false);
      if (mounted) {
        setState(() {
          _signedIn = false;
          _name = null;
          _status = t('Oracle account deleted.', 'تم حذف حساب Oracle.');
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _status = t(
            'Account deletion failed. No local data was removed.',
            'تعذّر حذف الحساب. لم يتم حذف أي بيانات محلية.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _account.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(t('Masari account', 'حساب مساري'))),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_circle_outlined, size: 64),
            const SizedBox(height: 16),
            Text(
              _signedIn
                  ? (_name ?? t('Oracle account connected', 'حساب Oracle متصل'))
                  : t('Sign in to Masari', 'تسجيل الدخول إلى مساري'),
            ),
            const SizedBox(height: 12),
            Text(
              t(
                'Your account is stored on the Masari Oracle server. Local Moodle links remain on this device.',
                'يُحفظ حسابك على خادم مساري في Oracle. روابط Moodle المحلية تبقى على هذا الجهاز.',
              ),
              textAlign: TextAlign.center,
            ),
            if (_status != null) ...[
              const SizedBox(height: 16),
              Text(_status!, textAlign: TextAlign.center),
            ],
            const SizedBox(height: 20),
            if (_busy)
              const CircularProgressIndicator()
            else if (!_signedIn)
              FilledButton.icon(
                onPressed: _signIn,
                icon: const Icon(Icons.login),
                label: Text(
                  t('Continue with Google', 'المتابعة باستخدام Google'),
                ),
              )
            else ...[
              OutlinedButton(
                onPressed: _signOut,
                child: Text(t('Sign out', 'تسجيل الخروج')),
              ),
              TextButton(
                onPressed: _deleteAccount,
                child: Text(t('Delete Masari account', 'حذف حساب مساري')),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
