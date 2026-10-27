import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_controller.dart';
import '../models/deadline.dart';
import 'google_account_service.dart';
import 'optional_cloud_backup.dart';
import 'task_plan_repository.dart';

/// Conservative, opt-in cloud sync for personal tasks and plans only.
///
/// Adds missing items on either side. It never uploads Moodle calendar URLs,
/// removes remote items, or replaces a local item with a remote conflict.
/// The manual backup/restore controls remain available for recovery.
class AutomaticGoogleSync {
  AutomaticGoogleSync(this.controller);

  final AppController controller;
  static const preferenceKey = 'google_auto_sync_enabled_v1';
  static const accountKey = 'google_auto_sync_account_uid_v1';
  final _plans = const TaskPlanRepository();
  bool _running = false;
  bool _queued = false;
  String? _lastLocalState;
  bool enabled = false;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    enabled = prefs.getBool(preferenceKey) ?? false;
    if (enabled && controller.initialized) await sync();
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(preferenceKey, value);
    enabled = value;
    if (value) {
      await GoogleAccountService.instance.initialize();
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        await prefs.setBool(preferenceKey, false);
        enabled = false;
        throw StateError('Google sign-in is required.');
      }
      await prefs.setString(accountKey, user.uid);
      await sync();
    }
  }

  Future<void> checkForChanges() async {
    if (!enabled || _running || !controller.initialized) return;
    final plans = await _plans.loadAll();
    final fingerprint = jsonEncode({
      'tasks': controller.manualDeadlines.map((e) => e.toJson()).toList(),
      'plans': plans.map((key, value) => MapEntry(key, value.toJson())),
    });
    if (fingerprint == _lastLocalState) return;
    await sync();
  }

  Future<void> sync() async {
    if (!enabled || !controller.initialized) return;
    if (_running) {
      _queued = true;
      return;
    }
    _running = true;
    try {
      await GoogleAccountService.instance.initialize();
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final prefs = await SharedPreferences.getInstance();
      final accountUid = prefs.getString(accountKey);
      if (accountUid == null) {
        // Older settings did not bind automatic sync to an account.
        // Require a fresh opt-in rather than risking cross-account upload.
        enabled = false;
        await prefs.setBool(preferenceKey, false);
        return;
      }
      if (accountUid != user.uid) return;
      final backup = OptionalCloudBackup(FirebaseFirestore.instance);
      final remote = await backup.download(user);
      final localPlans = await _plans.loadAll();
      final localTasks = controller.manualDeadlines;
      final existing = {for (final task in localTasks) task.stableKey: task};
      final merged = <String, Deadline>{
        for (final task in remote.tasks) task.stableKey: task,
        ...existing,
      };
      for (final task in remote.tasks) {
        if (!existing.containsKey(task.stableKey)) {
          await controller.saveManualDeadline(task);
        }
      }
      final combinedPlans = {...remote.plans, ...localPlans};
      for (final entry in remote.plans.entries) {
        if (!localPlans.containsKey(entry.key)) {
          await _plans.save(entry.value);
        }
      }
      await backup.upload(
        user: user,
        manualTasks: merged.values.toList(),
        plans: combinedPlans,
      );
      _lastLocalState = jsonEncode({
        'tasks': controller.manualDeadlines.map((e) => e.toJson()).toList(),
        'plans': combinedPlans.map((key, value) => MapEntry(key, value.toJson())),
      });
    } catch (_) {
      // Offline and permission failures must never disrupt local task editing.
    } finally {
      _running = false;
      if (_queued) {
        _queued = false;
        unawaited(sync());
      }
    }
  }
}
