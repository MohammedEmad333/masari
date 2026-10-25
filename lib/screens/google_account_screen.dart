import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../services/google_account_service.dart';

class GoogleAccountScreen extends StatefulWidget {
  const GoogleAccountScreen({super.key, required this.arabic});

  final bool arabic;

  @override
  State<GoogleAccountScreen> createState() => _GoogleAccountScreenState();
}

class _GoogleAccountScreenState extends State<GoogleAccountScreen> {
  final _account = GoogleAccountService.instance;
  User? _user;
  bool _busy = true;
  String? _error;

  String tr(String en, String ar) => widget.arabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await _account.initialize();
      if (!mounted) return;
      setState(() {
        _user = _account.currentUser;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = tr('Google sign-in is unavailable on this build.',
            'تسجيل الدخول باستخدام Google غير متاح في هذه النسخة.');
        _busy = false;
      });
    }
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await _account.signIn();
      if (!mounted) return;
      setState(() => _user = user);
    } on GoogleSignInException catch (error) {
      if (error.code != GoogleSignInExceptionCode.canceled && mounted) {
        setState(() => _error = tr('Google sign-in failed. Check app signing settings.',
            'فشل تسجيل الدخول. تحقق من إعدادات توقيع التطبيق.'));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = tr('Could not connect to Google.',
            'تعذّر الاتصال بحساب Google.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    try {
      await _account.signOut();
      if (mounted) setState(() => _user = null);
    } catch (_) {
      if (mounted) {
        setState(() => _error = tr('Sign-out failed.', 'تعذّر تسجيل الخروج.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('Google account', 'حساب Google'))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.account_circle_outlined, size: 64),
                const SizedBox(height: 16),
                Text(_user?.displayName ??
                    tr('Sign in to Masari', 'تسجيل الدخول إلى مساري')),
                if (_user?.email != null) Text(_user!.email!),
                const SizedBox(height: 12),
                Text(tr(
                  'Google sign-in is optional. Tasks and Moodle calendar remain local; cloud backup is not enabled yet.',
                  'ربط Google اختياري. تظل المهام والتقويم محليين؛ النسخ الاحتياطي السحابي غير مفعل بعد.',
                ), textAlign: TextAlign.center),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 24),
                if (_busy)
                  const CircularProgressIndicator()
                else if (_user == null)
                  FilledButton.icon(
                    onPressed: _signIn,
                    icon: const Icon(Icons.login),
                    label: Text(tr('Continue with Google', 'المتابعة باستخدام Google')),
                  )
                else
                  OutlinedButton(
                    onPressed: _signOut,
                    child: Text(tr('Sign out', 'تسجيل الخروج')),
                  ),
              ],
            ),
          ),
        ),
      );
}
