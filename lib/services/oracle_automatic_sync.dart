import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../app_controller.dart';
import '../models/deadline.dart';
import 'oracle_account_client.dart';
import 'oracle_personal_backup_codec.dart';
import 'task_plan_repository.dart';

/// Opt-in Oracle sync of personal tasks and plans. Existing local items win
/// conflicts. Deletions do not propagate automatically in this first version.
class OracleAutomaticSync {
  OracleAutomaticSync(this.controller);

  final AppController controller;
  final OracleAccountClient _account = OracleAccountClient();
  final TaskPlanRepository _plans = const TaskPlanRepository();

  static const preferenceKey = 'oracle_auto_sync_enabled_v1';
  static const accountKey = 'oracle_auto_sync_account_id_v1';

  bool enabled = false;
  bool _running = false;
  bool _queued = false;
  String? _lastLocalState;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    enabled = prefs.getBool(preferenceKey) ?? false;
    if (enabled && controller.initialized) await sync();
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    if (!value) {
      enabled = false;
      await prefs.setBool(preferenceKey, false);
      return;
    }
    final session = await _account.currentSession();
    if (session == null) throw StateError('Oracle account required.');
    final profile = await _account.profile();
    final accountId = profile['accountId'];
    if (accountId is! String || accountId.isEmpty) {
      throw StateError('Invalid Oracle account.');
    }
    await prefs.setString(accountKey, accountId);
    await prefs.setBool(preferenceKey, true);
    enabled = true;
    await sync();
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
      final session = await _account.currentSession();
      if (session == null) return;
      final prefs = await SharedPreferences.getInstance();
      final storedAccountId = prefs.getString(accountKey);
      if (storedAccountId == null) {
        // A previously enabled setting must not upload to a new account.
        enabled = false;
        await prefs.setBool(preferenceKey, false);
        return;
      }
      final profile = await _account.profile();
      if (profile['accountId'] != storedAccountId) return;

      // Re-read and merge after any concurrent device update (HTTP 409).
      // Never overwrite another device's newer snapshot from a stale GET.
      var saved = false;
      for (var attempt = 0; attempt < 3; attempt++) {
        final snapshot = await _account.downloadSnapshot('personal');
        final remote = OraclePersonalBackupCodec.decode(snapshot.data);
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
        // Re-check account binding immediately before the remote write.
        final currentAccount = await _account.profile();
        if (currentAccount['accountId'] != storedAccountId || !enabled) {
          return;
        }
        saved = await _account.uploadIfCurrent(
          'personal',
          OraclePersonalBackupCodec.prepare(
            manualTasks: merged.values.toList(),
            plans: combinedPlans,
          ),
          revision: snapshot.revision,
        );
        if (saved) {
          _lastLocalState = jsonEncode({
            'tasks': controller.manualDeadlines.map((e) => e.toJson()).toList(),
            'plans': combinedPlans.map(
              (key, value) => MapEntry(key, value.toJson()),
            ),
          });
          break;
        }
      }
      if (!saved) {
        // Another device keeps winning the race; preserve local edits.
        throw StateError('Oracle backup conflict');
      }
    } catch (_) {
      // Offline/expired sessions must never prevent local edits.
    } finally {
      _running = false;
      if (_queued) {
        _queued = false;
        unawaited(sync());
      }
    }
  }

  void dispose() => _account.dispose();
}
