import 'package:flutter/material.dart';

import '../models/deadline.dart';
import '../models/task_step.dart';
import '../services/task_plan_repository.dart';

/// Student-owned steps are local and remain independent of Moodle sync.
class TaskPlansScreen extends StatefulWidget {
  const TaskPlansScreen({super.key, required this.deadlines, required this.arabic});
  final List<Deadline> deadlines;
  final bool arabic;

  @override
  State<TaskPlansScreen> createState() => _TaskPlansScreenState();
}

class _TaskPlansScreenState extends State<TaskPlansScreen> {
  final _repository = const TaskPlanRepository();
  Map<String, TaskPlan> _plans = {};
  bool _loading = true;
  String? _error;

  String tr(String en, String ar) => widget.arabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final plans = await _repository.loadAll();
      if (mounted) setState(() { _plans = plans; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _error = tr('Unable to load plans', 'تعذّر تحميل الخطط'); _loading = false; });
    }
  }

  Future<void> _save(TaskPlan plan) async {
    try {
      await _repository.save(plan);
      if (mounted) setState(() { _plans = {..._plans, plan.deadlineId: plan}; _error = null; });
    } catch (_) {
      if (mounted) setState(() => _error = tr('Could not save changes', 'تعذّر حفظ التغييرات'));
    }
  }

  Future<void> _newStep(Deadline deadline) async {
    final title = TextEditingController();
    var day = DateTime.now();
    try {
      final result = await showDialog<(String, DateTime)>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text(tr('Add step', 'إضافة خطوة')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: title, maxLength: 120, autofocus: true,
                  decoration: InputDecoration(labelText: tr('Step name', 'اسم الخطوة'))),
                ListTile(
                  title: Text(tr('Scheduled day', 'يوم التنفيذ')),
                  subtitle: Text(MaterialLocalizations.of(context).formatMediumDate(day)),
                  trailing: const Icon(Icons.event),
                  onTap: () async {
                    final selected = await showDatePicker(context: context, initialDate: day,
                      firstDate: DateTime(2020), lastDate: DateTime(2100));
                    if (selected != null) update(() => day = selected);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext),
                child: Text(tr('Cancel', 'إلغاء'))),
              FilledButton(onPressed: () {
                if (title.text.trim().isEmpty) return;
                Navigator.pop(dialogContext, (title.text.trim(), day));
              }, child: Text(tr('Save', 'حفظ'))),
            ],
          ),
        ),
      );
      if (result == null) return;
      final key = deadline.stableKey;
      final old = _plans[key] ?? TaskPlan(deadlineId: key, steps: const []);
      final step = TaskStep(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: result.$1,
        scheduledFor: result.$2,
      );
      await _save(old.copyWith(steps: [...old.steps, step]));
    } finally {
      title.dispose();
    }
  }

  Future<void> _status(Deadline deadline, TaskStep step, TaskStepStatus status) async {
    final old = _plans[deadline.stableKey];
    if (old == null) return;
    await _save(old.copyWith(steps: [
      for (final item in old.steps) item.id == step.id ? item.copyWith(status: status) : item,
    ]));
  }

  Future<void> _delete(Deadline deadline, TaskStep step) async {
    final old = _plans[deadline.stableKey];
    if (old == null) return;
    await _save(old.copyWith(steps: old.steps.where((item) => item.id != step.id).toList()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Task plans', 'خطط المهام'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
              if (widget.deadlines.isEmpty)
                Center(child: Text(tr('No tasks yet', 'لا توجد مهام بعد'))),
              for (final deadline in widget.deadlines) _planCard(deadline),
            ]),
    );
  }

  Widget _planCard(Deadline deadline) {
    final plan = _plans[deadline.stableKey] ?? TaskPlan(deadlineId: deadline.stableKey, steps: const []);
    final steps = [...plan.steps]..sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));
    return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(deadline.title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: plan.progress),
        const SizedBox(height: 4),
        Text('${plan.completedCount}/${plan.steps.length} • ${(plan.progress * 100).round()}%'),
        for (final step in steps) ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(step.title),
          subtitle: Text(MaterialLocalizations.of(context).formatMediumDate(step.scheduledFor)),
          trailing: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
            DropdownButton<TaskStepStatus>(
              value: step.status,
              onChanged: (value) { if (value != null) _status(deadline, step, value); },
              items: [
                DropdownMenuItem(value: TaskStepStatus.notStarted, child: Text(tr('Not started', 'لم تبدأ'))),
                DropdownMenuItem(value: TaskStepStatus.inProgress, child: Text(tr('In progress', 'قيد التنفيذ'))),
                DropdownMenuItem(value: TaskStepStatus.completed, child: Text(tr('Done', 'مكتملة'))),
              ],
            ),
            IconButton(icon: const Icon(Icons.delete_outline),
              tooltip: tr('Delete step', 'حذف الخطوة'),
              onPressed: () => _delete(deadline, step)),
          ]),
        ),
        Align(alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            onPressed: () => _newStep(deadline),
            icon: const Icon(Icons.add),
            label: Text(tr('Add step', 'إضافة خطوة')),
          )),
      ],
    )));
  }
}
