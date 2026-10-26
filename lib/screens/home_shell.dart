import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_controller.dart';
import '../models/deadline.dart';
import '../services/notification_service.dart';
import '../services/ics_parser.dart';
import '../services/sync_feedback.dart';
import '../services/deadline_filters.dart';
import '../services/manual_task_form.dart';
import '../services/study_insights.dart';
import 'pomodoro_dialog.dart';
import 'moodle_calendar_browser.dart';
import '../services/moodle_browser_login.dart';
import 'local_courses_screen.dart';
import 'task_plans_screen.dart';
import 'google_account_screen.dart';
import 'cloud_backup_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  String _searchQuery = '';
  String? _selectedCourse;
  String _courseCalendarFilter = 'all';
  DateTime _selectedDate = DateTime.now();

  bool get _ar => widget.controller.locale.languageCode == 'ar';
  String t(String en, String ar) => _ar ? ar : en;
  String get _localeName => _ar ? 'ar' : 'en';
  bool get _canSync =>
      widget.controller.calendarConnected || widget.controller.apiConnected;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (!controller.initialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final titles = [
      t('Home', 'الرئيسية'),
      t('Tasks', 'المهام'),
      t('Study plan', 'خطة الدراسة'),
      t('Calendar', 'التقويم'),
      t('Courses', 'المساقات'),
      t('Settings', 'الإعدادات'),
    ];

    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_index]),
        actions: [
          IconButton(
            tooltip: t('Cloud backup', 'النسخ الاحتياطي السحابي'),
            icon: const Icon(Icons.cloud_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    CloudBackupScreen(controller: controller, arabic: _ar),
              ),
            ),
          ),
          IconButton(
            tooltip: t('Google account', 'حساب Google'),
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => GoogleAccountScreen(arabic: _ar),
              ),
            ),
          ),
          IconButton(
            tooltip: t('Task plans', 'خطط المهام'),
            icon: const Icon(Icons.account_tree_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => TaskPlansScreen(
                  deadlines: controller.allDeadlines,
                  arabic: _ar,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: t('Sync now', 'مزامنة الآن'),
            onPressed: controller.busy || !_canSync ? null : _sync,
            icon: controller.busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded),
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          _home(),
          _tasks(),
          _plan(),
          _calendar(),
          _courses(),
          _settings(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        indicatorColor: scheme.primary.withValues(alpha: .22),
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home_rounded),
            label: t('Home', 'الرئيسية'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.task_alt_outlined),
            selectedIcon: const Icon(Icons.task_alt_rounded),
            label: t('Tasks', 'المهام'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.menu_book_outlined),
            selectedIcon: const Icon(Icons.menu_book_rounded),
            label: t('Plan', 'الخطة'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.calendar_month_outlined),
            selectedIcon: const Icon(Icons.calendar_month_rounded),
            label: t('Calendar', 'التقويم'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.school_outlined),
            selectedIcon: const Icon(Icons.school_rounded),
            label: t('Courses', 'المساقات'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings_rounded),
            label: t('Settings', 'الإعدادات'),
          ),
        ],
      ),
    );
  }

  Future<void> _openCalendarSetup() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _Setup(controller: widget.controller),
      ),
    );
  }

  Future<void> _sync() async {
    final ok = await widget.controller.sync();
    if (!mounted) return;
    String message;
    if (!ok) {
      message = SyncFeedback.errorMessage(
        widget.controller.error ?? t('Sync failed.', 'فشلت المزامنة.'),
        arabic: _ar,
      );
    } else if (widget.controller.reminderSchedulingFailed) {
      message = t(
        'Calendar updated, but reminders could not be scheduled. Use Repair reminders in Settings.',
        'تم تحديث التقويم، لكن تعذّرت جدولة التنبيهات. استخدم إصلاح التنبيهات من الإعدادات.',
      );
    } else if (widget.controller.syncWarning != null) {
      message = t(
        'Some calendars could not sync; saved events were kept.',
        'تعذّرت مزامنة بعض التقويمات، واحتفظنا بالمواعيد المحفوظة.',
      );
    } else {
      message = t('Moodle calendar synced.', 'تمت مزامنة تقويم Moodle.');
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _addManualTask({Deadline? existing}) async {
    final titleController = TextEditingController(text: existing?.title ?? '');
    final notesController = TextEditingController(
      text: existing?.description ?? '',
    );
    DateTime due = existing?.due ?? defaultManualTaskDue(DateTime.now());
    int priority = existing?.priority ?? 1;
    // -2 uses the normal global schedule; -1 disables all alerts.
    int reminderChoice = existing?.reminderMinutesBefore ?? -2;
    bool saving = false;
    String? validationMessage;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            scrollable: true,
            title: Text(
              existing == null
                  ? t('New task', 'مهمة جديدة')
                  : t('Edit task', 'تعديل المهمة'),
            ),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: titleController,
                    enabled: !saving,
                    maxLength: 150,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: t('Task title *', 'عنوان المهمة *'),
                      hintText: t(
                        'e.g. Review chapter 3',
                        'مثلاً: مراجعة الفصل الثالث',
                      ),
                    ),
                  ),
                  TextField(
                    controller: notesController,
                    enabled: !saving,
                    maxLines: 2,
                    maxLength: 500,
                    decoration: InputDecoration(
                      labelText: t('Notes (optional)', 'ملاحظات (اختياري)'),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    enabled: !saving,
                    leading: const Icon(Icons.event_outlined),
                    title: Text(t('Due date', 'تاريخ الاستحقاق')),
                    subtitle: Text(
                      MaterialLocalizations.of(context).formatMediumDate(due),
                    ),
                    trailing: const Icon(Icons.edit_calendar_outlined),
                    onTap: () async {
                      final selected = await showDatePicker(
                        context: context,
                        initialDate: due,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (selected == null || !context.mounted) return;
                      update(() {
                        due = manualTaskDue(
                          selected,
                          TimeOfDay.fromDateTime(due),
                        );
                        validationMessage = null;
                      });
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    enabled: !saving,
                    leading: const Icon(Icons.access_time_outlined),
                    title: Text(t('Due time', 'وقت الاستحقاق')),
                    subtitle: Text(
                      MaterialLocalizations.of(
                        context,
                      ).formatTimeOfDay(TimeOfDay.fromDateTime(due)),
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () async {
                      final selected = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(due),
                      );
                      if (selected == null || !context.mounted) return;
                      update(() {
                        due = manualTaskDue(due, selected);
                        validationMessage = null;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: priority,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: t('Priority', 'الأولوية'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 1,
                        child: Text(t('Normal', 'عادية')),
                      ),
                      DropdownMenuItem(
                        value: 2,
                        child: Text(t('High', 'عالية')),
                      ),
                      DropdownMenuItem(
                        value: 3,
                        child: Text(t('Urgent', 'عاجلة')),
                      ),
                    ],
                    onChanged: saving
                        ? null
                        : (value) => update(() => priority = value ?? 1),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: reminderChoice,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: t('Remind me', 'ذكّرني'),
                      helperText: t(
                        'A reminder can fire before the task is due.',
                        'يمكن إرسال تذكير قبل موعد المهمة.',
                      ),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: -2,
                        child: Text(
                          t('Use default reminders', 'التذكيرات الافتراضية'),
                        ),
                      ),
                      DropdownMenuItem(
                        value: -1,
                        child: Text(t('No notifications', 'بدون إشعارات')),
                      ),
                      DropdownMenuItem(
                        value: 5,
                        child: Text(t('5 minutes before', 'قبل 5 دقائق')),
                      ),
                      DropdownMenuItem(
                        value: 15,
                        child: Text(t('15 minutes before', 'قبل 15 دقيقة')),
                      ),
                      DropdownMenuItem(
                        value: 30,
                        child: Text(t('30 minutes before', 'قبل 30 دقيقة')),
                      ),
                      DropdownMenuItem(
                        value: 60,
                        child: Text(t('1 hour before', 'قبل ساعة')),
                      ),
                      DropdownMenuItem(
                        value: 360,
                        child: Text(t('6 hours before', 'قبل 6 ساعات')),
                      ),
                      DropdownMenuItem(
                        value: 1440,
                        child: Text(t('1 day before', 'قبل يوم')),
                      ),
                    ],
                    onChanged: saving
                        ? null
                        : (value) => update(() => reminderChoice = value ?? -2),
                  ),
                  if (validationMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      validationMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
                child: Text(t('Cancel', 'إلغاء')),
              ),
              FilledButton.icon(
                onPressed: saving
                    ? null
                    : () async {
                        final title = titleController.text.trim();
                        final validation = validateManualTask(
                          title,
                          due,
                          now: DateTime.now(),
                        );
                        if (validation != null) {
                          update(() {
                            validationMessage =
                                validation ==
                                    ManualTaskValidationError.titleRequired
                                ? t('Enter a task title.', 'اكتب عنوان المهمة.')
                                : t(
                                    'Choose a future date and time.',
                                    'اختر تاريخاً ووقتاً في المستقبل.',
                                  );
                          });
                          return;
                        }
                        update(() {
                          saving = true;
                          validationMessage = null;
                        });
                        try {
                          final uid =
                              existing?.uid ??
                              'manual-${DateTime.now().microsecondsSinceEpoch}';
                          await widget.controller.saveManualDeadline(
                            Deadline(
                              uid: uid,
                              title: title,
                              due: due,
                              description: notesController.text.trim(),
                              priority: priority,
                              reminderMinutesBefore: reminderChoice == -2
                                  ? null
                                  : reminderChoice,
                            ),
                          );
                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext);
                          if (!mounted) return;
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(
                              content: Text(
                                widget.controller.reminderSchedulingFailed
                                    ? t(
                                        'Task saved. Reminders need repair in Settings.',
                                        'حُفظت المهمة، لكن التنبيهات بحاجة لإصلاح من الإعدادات.',
                                      )
                                    : t('Task saved.', 'تم حفظ المهمة.'),
                              ),
                            ),
                          );
                        } catch (_) {
                          if (!dialogContext.mounted) return;
                          update(() {
                            saving = false;
                            validationMessage = t(
                              'Could not save the task. Try again.',
                              'تعذّر حفظ المهمة. حاول مجدداً.',
                            );
                          });
                        }
                      },
                icon: saving
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(t('Save task', 'حفظ المهمة')),
              ),
            ],
          ),
        ),
      );
    } finally {
      titleController.dispose();
      notesController.dispose();
    }
  }

  Widget _home() {
    final controller = widget.controller;
    final active = controller.activeDeadlines;
    final upcoming = active.where((d) => !d.isPast).toList();
    upcoming.sort((a, b) => a.due.compareTo(b.due));
    final next = upcoming.isEmpty ? null : upcoming.first;
    final weekEnd = DateTime.now().add(const Duration(days: 7));
    final weekCount = upcoming.where((d) => d.due.isBefore(weekEnd)).length;
    final conflicts = StudyInsights.conflicts(active);
    final totalCount = controller.allDeadlines.length;
    final doneCount = controller.completedDeadlines.length;
    final now = DateTime.now();
    final overdueCount = StudyInsights.overdueCount(active, now);
    final dueSoonCount = StudyInsights.dueSoonCount(active, now);
    final completionPercent =
        (StudyInsights.completionRate(doneCount, totalCount) * 100).round();

    return RefreshIndicator(
      onRefresh: () => controller.sync(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (!controller.calendarConnected && !controller.apiConnected) ...[
            Card(
              child: ListTile(
                leading: const Icon(Icons.calendar_month_outlined),
                title: Text(
                  t('Connect your university calendar', 'اربط تقويم جامعتك'),
                ),
                subtitle: Text(
                  t(
                    'Optional. You can manage tasks and study plans without Moodle.',
                    'اختياري؛ يمكنك إدارة المهام والخطط دون ربط Moodle.',
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openCalendarSetup,
              ),
            ),
            const SizedBox(height: 12),
          ],
          _HeroCard(
            title: t(
              '$weekCount deadlines this week',
              '$weekCount مواعيد هذا الأسبوع',
            ),
            next: next,
            nextDueText: next == null ? null : _formatDue(next.due),
            nextRemainingText: next == null ? null : _remainingText(next),
            lastSyncText: controller.lastSync == null
                ? null
                : t(
                    'Last synced ${DateFormat.jm('en').format(controller.lastSync!)}',
                    'آخر مزامنة ${DateFormat.jm('ar').format(controller.lastSync!)}',
                  ),
            isArabic: _ar,
          ),
          if (controller.reminderSchedulingFailed) ...[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.notifications_off_outlined),
                title: Text(
                  t(
                    'Calendar updated; reminders need repair.',
                    'التقويم محدّث؛ التنبيهات بحاجة إلى إصلاح.',
                  ),
                ),
                subtitle: Text(
                  t(
                    'Open Settings and select Repair reminders.',
                    'افتح الإعدادات واختر إصلاح التنبيهات.',
                  ),
                ),
              ),
            ),
          ],
          if (controller.error != null) ...[
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.error_outline_rounded),
                title: Text(
                  SyncFeedback.errorMessage(controller.error!, arabic: _ar),
                ),
                subtitle: Text(
                  SyncFeedback.offlineHint(
                    hasSavedDeadlines: controller.allDeadlines.isNotEmpty,
                    arabic: _ar,
                  ),
                ),
                trailing: IconButton(
                  tooltip: t('Retry synchronization', 'إعادة محاولة المزامنة'),
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: controller.busy ? null : _sync,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.insights_rounded),
            title: Text(t('Study insights', 'إحصائيات الدراسة')),
            subtitle: Text(
              t(
                '$completionPercent% completed • $overdueCount overdue • $dueSoonCount due within 7 days • ${conflicts.length} conflicts',
                'الإنجاز $completionPercent% • المتأخرة $overdueCount • خلال 7 أيام $dueSoonCount • التعارضات ${conflicts.length}',
              ),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.task_alt_rounded),
            title: Text(t('My tasks', 'المهام')),
            subtitle: Text(
              t(
                'View and manage all deadlines',
                'عرض المواعيد والمهام وإدارتها',
              ),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => setState(() => _index = 1),
          ),
          ListTile(
            leading: const Icon(Icons.menu_book_rounded),
            title: Text(t('Weekly study plan', 'خطة المذاكرة الأسبوعية')),
            subtitle: Text(
              t('Review your weekly schedule', 'راجع جدول المذاكرة الأسبوعي'),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => setState(() => _index = 2),
          ),
        ],
      ),
    );
  }

  Widget _plan() {
    final active = widget.controller.activeDeadlines;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _section(t('Weekly study plan', 'خطة المذاكرة الأسبوعية'), ''),
        const SizedBox(height: 8),
        ...StudyInsights.week(active, DateTime.now()).entries.map((entry) {
          final day = entry.key;
          final tasks = entry.value;
          return ListTile(
            leading: const Icon(Icons.calendar_view_week_rounded),
            title: Text(DateFormat.EEEE(_localeName).format(day)),
            subtitle: Text(
              tasks.isEmpty
                  ? t('No tasks', 'لا توجد مهام')
                  : tasks.map((task) => task.title).join(' • '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text('${tasks.length}'),
          );
        }),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => PomodoroDialog(arabic: _ar),
          ),
          icon: const Icon(Icons.timer_outlined),
          label: Text(t('Pomodoro focus timer', 'مؤقت بومودورو')),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _addManualTask,
          icon: const Icon(Icons.add_task_rounded),
          label: Text(t('Add task', 'إضافة مهمة')),
        ),
      ],
    );
  }

  Widget _tasks() {
    final controller = widget.controller;
    final active = controller.activeDeadlines;
    final courses = active
        .map((d) => d.course)
        .where((c) => c.isNotEmpty)
        .toSet();
    final selectedCourse = validCourseSelection(active, _selectedCourse);
    final deadlines = filterDeadlines(
      active,
      query: _searchQuery,
      course: selectedCourse,
    );
    final archiveCutoff = DateTime.now().subtract(const Duration(days: 7));
    final overdue = deadlines
        .where((d) => d.isPast && !d.due.isBefore(archiveCutoff))
        .toList();
    final historical =
        deadlines.where((d) => d.due.isBefore(archiveCutoff)).toList()
          ..sort((a, b) => b.due.compareTo(a.due));
    final upcoming = deadlines.where((d) => !d.isPast).toList();
    upcoming.sort((a, b) => a.due.compareTo(b.due));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        FilledButton.icon(
          onPressed: _addManualTask,
          icon: const Icon(Icons.add_task_rounded),
          label: Text(t('Add task', 'إضافة مهمة')),
        ),
        const SizedBox(height: 12),
        _section(
          t('My tasks today', 'مهامي اليوم'),
          '${active.where((d) => _sameDay(d.due, DateTime.now())).length}',
        ),
        const SizedBox(height: 8),
        ...active
            .where((d) => _sameDay(d.due, DateTime.now()))
            .map(_deadlineCard),
        const SizedBox(height: 16),
        TextField(
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            labelText: t('Search deadlines', 'ابحث عن المهام'),
          ),
          onChanged: (value) => setState(() => _searchQuery = value),
        ),
        const SizedBox(height: 10),
        Text(
          t('Filter by course', 'تصفية حسب المساق'),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey(selectedCourse),
          initialValue: selectedCourse ?? '',
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
          items: [
            DropdownMenuItem(
              value: '',
              child: Text(t('All courses', 'كل المساقات')),
            ),
            ...(courses.toList()..sort()).map(
              (course) => DropdownMenuItem(value: course, child: Text(course)),
            ),
          ],
          onChanged: (value) => setState(() {
            _selectedCourse = value == null || value.isEmpty ? null : value;
          }),
        ),
        if (overdue.isNotEmpty) ...[
          const SizedBox(height: 18),
          _section(t('Overdue', 'مهام متأخرة'), '${overdue.length}'),
          const SizedBox(height: 8),
          ...overdue.take(15).map(_deadlineCard),
        ],
        if (historical.isNotEmpty) ...[
          const SizedBox(height: 18),
          _section(
            t('Previous tasks (saved)', 'المهام السابقة المحفوظة'),
            '${historical.length}',
          ),
          const SizedBox(height: 4),
          Text(
            t(
              'Past dates do not confirm whether Moodle accepted a submission.',
              'مرور موعد المهمة لا يؤكد تسليمها أو إغلاق التسليم في Moodle.',
            ),
          ),
          const SizedBox(height: 8),
          ...historical.map(_deadlineCard),
        ],
        const SizedBox(height: 18),
        _section(
          t('Upcoming deadlines', 'المواعيد القادمة'),
          '${upcoming.length}',
        ),
        const SizedBox(height: 8),
        if (upcoming.isEmpty)
          _empty(
            Icons.task_alt_rounded,
            t('You are all caught up', 'لا توجد مواعيد قادمة'),
            t(
              'Pull down to sync your Moodle calendar.',
              'اسحب للأسفل لمزامنة تقويم Moodle.',
            ),
          )
        else
          ...upcoming.take(15).map(_deadlineCard),
        if (controller.completedDeadlines.isNotEmpty) ...[
          const SizedBox(height: 18),
          _section(
            t('Completed', 'المكتملة'),
            '${controller.completedDeadlines.length}',
          ),
          const SizedBox(height: 8),
          ...controller.completedDeadlines.take(5).map(_deadlineCard),
        ],
      ],
    );
  }

  Widget _calendar() {
    final active = widget.controller.activeDeadlines
        .where((d) => !d.isPast)
        .toList();
    final items = active.where((deadline) {
      final d = deadline.due;
      return d.year == _selectedDate.year &&
          d.month == _selectedDate.month &&
          d.day == _selectedDate.day;
    }).toList();

    final futureAfterSelected = active.where((deadline) {
      final selectedDay = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      );
      final dueDay = DateTime(
        deadline.due.year,
        deadline.due.month,
        deadline.due.day,
      );
      return dueDay.isAfter(selectedDay);
    }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
            child: _DeadlineCalendar(
              selectedDate: _selectedDate,
              deadlines: active,
              localeName: _localeName,
              onDateChanged: (value) => setState(() => _selectedDate = value),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _section(
          DateFormat.yMMMMd(_localeName).format(_selectedDate),
          '${items.length}',
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          _empty(
            Icons.event_available_outlined,
            t('Nothing due on this day', 'لا يوجد تسليم في هذا اليوم'),
            futureAfterSelected.isEmpty
                ? t(
                    'Choose another date to inspect your agenda.',
                    'اختر تاريخًا آخر لعرض المواعيد.',
                  )
                : t(
                    'Next deadline: ${DateFormat.MMMd('en').format(futureAfterSelected.first.due)}',
                    'الموعد القادم: ${DateFormat.MMMMd('ar').format(futureAfterSelected.first.due)}',
                  ),
          )
        else
          ...items.map(_deadlineCard),
      ],
    );
  }

  Widget _courses() {
    final extras = widget.controller.additionalCalendarUrls;
    String sourceKey(String url) {
      final hash = url.codeUnits.fold<int>(
        0,
        (value, code) => ((value * 31) + code) & 0x7fffffff,
      );
      return 'feed-${hash.toRadixString(16)}:';
    }

    final sourceKeys = [for (final url in extras) sourceKey(url)];
    String calendarOf(Deadline deadline) {
      for (var index = 0; index < sourceKeys.length; index++) {
        if (deadline.uid.startsWith(sourceKeys[index])) {
          return 'extra-$index';
        }
      }
      return 'primary';
    }

    final selected = _courseCalendarFilter;
    final grouped = <String, List<Deadline>>{};
    for (final deadline in widget.controller.activeDeadlines) {
      if (selected != 'all' && calendarOf(deadline) != selected) continue;
      final course = deadline.course.isEmpty
          ? t('Other', 'أخرى')
          : deadline.course;
      grouped.putIfAbsent(course, () => []).add(deadline);
    }
    final entries = grouped.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.folder_copy_outlined),
            title: Text(t('My study library', 'مكتبتي الدراسية')),
            subtitle: Text(
              t(
                'Organize your own courses, chapters, files and links',
                'نظّم مساقاتك وفصولك وملفاتك وروابطك',
              ),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => LocalCoursesScreen(arabic: _ar),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (extras.isNotEmpty) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: Text(t('All calendars', 'كل التقاويم')),
                  selected: _courseCalendarFilter == 'all',
                  onSelected: (_) =>
                      setState(() => _courseCalendarFilter = 'all'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(t('Main calendar', 'التقويم الأساسي')),
                  selected: _courseCalendarFilter == 'primary',
                  onSelected: (_) =>
                      setState(() => _courseCalendarFilter = 'primary'),
                ),
                for (var i = 0; i < extras.length; i++) ...[
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(t('Calendar ${i + 2}', 'تقويم ${i + 2}')),
                    selected: _courseCalendarFilter == 'extra-$i',
                    onSelected: (_) =>
                        setState(() => _courseCalendarFilter = 'extra-$i'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        _section(t('My courses', 'مساقاتي'), '${entries.length}'),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          _empty(
            Icons.school_outlined,
            t('No courses yet', 'لا توجد مساقات بعد'),
            t(
              'Courses appear after the first successful sync.',
              'ستظهر المساقات بعد أول مزامنة ناجحة.',
            ),
          )
        else
          ...entries.map((entry) {
            final next = entry.value.first;
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Text(
                    entry.key.isEmpty
                        ? '?'
                        : entry.key.substring(0, 1).toUpperCase(),
                  ),
                ),
                title: Text(
                  _displayCourse(entry.key),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  t(
                    '${entry.value.length} upcoming • next ${_remainingText(next)}',
                    '${entry.value.length} قادمة • التالي ${_remainingText(next)}',
                  ),
                ),
                trailing: Icon(
                  _ar
                      ? Icons.chevron_left_rounded
                      : Icons.chevron_right_rounded,
                ),
                onTap: () => _showCourse(entry.key, entry.value),
              ),
            );
          }),
      ],
    );
  }

  Future<void> _addCalendarSource() async {
    final field = TextEditingController();
    try {
      final url = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(t('Add Moodle calendar', 'إضافة تقويم Moodle')),
          content: TextField(
            controller: field,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: t('Private iCalendar URL', 'رابط التقويم الخاص'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(t('Cancel', 'إلغاء')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, field.text.trim()),
              child: Text(t('Add', 'إضافة')),
            ),
          ],
        ),
      );
      if (url == null || url.isEmpty || !mounted) return;
      try {
        await widget.controller.addCalendarSource(url);
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('Invalid calendar URL', 'رابط التقويم غير صالح')),
          ),
        );
      }
    } finally {
      field.dispose();
    }
  }

  Future<void> _repairReminders() async {
    final restored = await widget.controller.repairReminders();
    if (!mounted) return;
    final message = restored
        ? t(
            'Reminders rescheduled. Check Android battery restrictions if alerts remain delayed.',
            'أُعيدت جدولة التنبيهات. افحص قيود البطارية إذا بقيت متأخرة.',
          )
        : switch (widget.controller.reminderRepairFailure) {
            ReminderRepairFailure.permissionDenied => t(
              'Android notification permission is disabled.',
              'صلاحية إشعارات مساري غير مفعّلة في Android.',
            ),
            ReminderRepairFailure.initializationFailed => t(
              'Could not initialize reminders. Check your device timezone and notification settings.',
              'تعذّرت تهيئة التنبيهات. تحقق من المنطقة الزمنية وإعدادات الإشعارات.',
            ),
            ReminderRepairFailure.permissionCheckFailed => t(
              'Could not verify Android notification permission.',
              'تعذّر التحقق من صلاحية إشعارات Android.',
            ),
            ReminderRepairFailure.schedulingFailed => t(
              'Notifications are allowed, but Android could not schedule the reminders. Check alarm and battery restrictions.',
              'الإشعارات مسموحة، لكن Android لم يتمكن من جدولة التنبيهات. تحقق من قيود المنبّهات والبطارية.',
            ),
            null => t('Could not repair reminders.', 'تعذّر إصلاح التنبيهات.'),
          };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _testNotification() async {
    try {
      await NotificationService.showTest(arabic: _ar);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              'Test notification sent. Check your notification shade.',
              'تم إرسال إشعار تجريبي. تحقق من لوحة الإشعارات.',
            ),
          ),
        ),
      );
    } catch (error) {
      debugPrint('Test notification failed: ${error.runtimeType}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              'Could not send the test notification. Check alarm and notification setup.',
              'تعذّر إرسال الإشعار التجريبي. تحقق من إعدادات الإشعارات والمنبّهات.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _editCalendarUrl() async {
    final current = await widget.controller.calendarUrlForEditing();
    if (!mounted) return;
    final field = TextEditingController(text: current ?? '');
    try {
      final next = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(t('Edit calendar URL', 'تعديل رابط التقويم')),
          content: TextField(
            controller: field,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: t('Private iCalendar URL', 'رابط التقويم الخاص'),
              helperText: t(
                'The old link stays active until the new one is verified.',
                'يبقى الرابط السابق فعّالًا حتى التحقق من الجديد.',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(t('Cancel', 'إلغاء')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, field.text.trim()),
              child: Text(t('Verify and save', 'تحقق واحفظ')),
            ),
          ],
        ),
      );
      if (next == null || next == current) return;
      final ok = await widget.controller.updateCalendarUrl(next);
      if (!mounted) return;
      final message = ok
          ? t('Calendar URL updated.', 'تم تحديث رابط التقويم.')
          : SyncFeedback.errorMessage(
              widget.controller.error ?? t('Invalid URL', 'رابط غير صالح'),
              arabic: _ar,
            );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      field.dispose();
    }
  }

  Widget _settings() {
    final controller = widget.controller;
    const choices = [72, 48, 24, 6, 1];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _settingsCard(
          t('Moodle calendar', 'تقويم Moodle'),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t(
                  'Your private calendar link is stored securely on this device.',
                  'رابط التقويم الخاص محفوظ بشكل آمن على جهازك.',
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: controller.busy ? null : _openCalendarSetup,
                icon: const Icon(Icons.add_link),
                label: Text(
                  t('Connect or import a calendar', 'ربط تقويم أو استيراده'),
                ),
              ),
              if (controller.calendarConnected) const SizedBox(height: 12),
              if (controller.calendarConnected)
                OutlinedButton.icon(
                  onPressed: controller.busy ? null : _editCalendarUrl,
                  icon: const Icon(Icons.edit_calendar_outlined),
                  label: Text(t('Edit calendar URL', 'تعديل رابط التقويم')),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _settingsCard(
          t('Additional calendars', 'التقويمات الإضافية'),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t(
                  'Add other Moodle calendar feeds. The links are stored securely.',
                  'أضف تقويمات Moodle أخرى. تُحفظ الروابط بشكل آمن.',
                ),
              ),
              for (final url in controller.additionalCalendarUrls)
                ListTile(
                  leading: const Icon(Icons.event_note_outlined),
                  title: Text(t('Moodle calendar', 'تقويم Moodle')),
                  subtitle: Text(t('Private link saved', 'رابط خاص محفوظ')),
                  trailing: IconButton(
                    tooltip: t('Remove calendar', 'حذف التقويم'),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => controller.removeCalendarSource(url),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: _addCalendarSource,
                icon: const Icon(Icons.add),
                label: Text(t('Add calendar', 'إضافة تقويم')),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _settingsCard(
          t('Reminder schedule', 'جدول التنبيهات'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: choices.map((hours) {
              final selected = controller.reminderOffsets.contains(hours);
              return FilterChip(
                selected: selected,
                label: Text(_offsetLabel(hours)),
                onSelected: (_) {
                  final values = [...controller.reminderOffsets];
                  selected ? values.remove(hours) : values.add(hours);
                  controller.setReminderOffsets(values);
                },
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        _settingsCard(
          t('Appearance', 'المظهر'),
          DropdownButtonFormField<ThemeMode>(
            initialValue: controller.themeMode,
            decoration: InputDecoration(labelText: t('Theme', 'السمة')),
            items: ThemeMode.values
                .map(
                  (mode) => DropdownMenuItem(
                    value: mode,
                    child: Text(switch (mode) {
                      ThemeMode.system => t('System', 'النظام'),
                      ThemeMode.light => t('Light', 'فاتح'),
                      ThemeMode.dark => t('Dark', 'داكن'),
                    }),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) controller.setThemeMode(value);
            },
          ),
        ),
        const SizedBox(height: 12),
        _settingsCard(
          t('Language', 'اللغة'),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'en', label: Text('English')),
              ButtonSegment(value: 'ar', label: Text('العربية')),
            ],
            selected: {controller.locale.languageCode},
            onSelectionChanged: (value) =>
                controller.setLocale(Locale(value.first)),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.notifications_active_outlined),
                title: Text(t('Test notification', 'اختبار الإشعار')),
                onTap: _testNotification,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: Text(t('Repair reminders', 'إصلاح التنبيهات')),
                subtitle: Text(
                  t(
                    'Check permissions and reschedule upcoming alerts',
                    'فحص الصلاحيات وإعادة جدولة المواعيد القادمة',
                  ),
                ),
                onTap: _repairReminders,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.sync_rounded),
                title: Text(t('Sync now', 'مزامنة الآن')),
                subtitle: Text(_lastSyncText()),
                onTap: controller.busy || !_canSync ? null : _sync,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.lock_outline_rounded),
                title: Text(t('Private calendar URL', 'رابط التقويم الخاص')),
                subtitle: Text(
                  t(
                    'Stored in secure device storage',
                    'محفوظ في التخزين الآمن للجهاز',
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (controller.calendarConnected)
          OutlinedButton.icon(
            onPressed: _disconnect,
            icon: const Icon(Icons.link_off_rounded),
            label: Text(t('Disconnect Moodle', 'فصل Moodle')),
          ),
      ],
    );
  }

  Widget _deadlineCard(Deadline deadline) {
    final completed = widget.controller.completedIds.contains(
      deadline.stableKey,
    );
    final color = _urgency(deadline);
    final course = _displayCourse(deadline.course);
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Icon(
          completed ? Icons.check_circle_rounded : Icons.schedule_rounded,
          color: completed ? Colors.green : color,
        ),
        title: Text(
          deadline.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            decoration: completed ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (course.isNotEmpty)
                Text(course, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(_formatDue(deadline.due)),
            ],
          ),
        ),
        trailing: Text(
          _remainingText(deadline),
          textAlign: TextAlign.center,
          style: TextStyle(color: color, fontWeight: FontWeight.w800),
        ),
        onTap: () => _showDeadline(deadline),
      ),
    );
  }

  Widget _section(String title, String count) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      Badge(label: Text(count)),
    ],
  );

  Widget _empty(IconData icon, String title, String subtitle) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(icon, size: 42, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(subtitle, textAlign: TextAlign.center),
        ],
      ),
    ),
  );

  Widget _settingsCard(String title, Widget child) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    ),
  );

  String _offsetLabel(int hours) {
    if (hours % 24 == 0) {
      final days = hours ~/ 24;
      return t('$days day${days == 1 ? '' : 's'}', '$days يوم');
    }
    return t('$hours hour${hours == 1 ? '' : 's'}', '$hours ساعة');
  }

  String _lastSyncText() {
    final value = widget.controller.lastSync;
    if (value == null) return t('Not synced yet', 'لم تتم المزامنة بعد');
    return t(
      'Last sync: ${DateFormat.jm('en').format(value)}',
      'آخر مزامنة: ${DateFormat.jm('ar').format(value)}',
    );
  }

  String _formatDue(DateTime value) {
    if (_ar) {
      return DateFormat('EEEE، d MMMM • h:mm a', 'ar').format(value);
    }
    return DateFormat('EEE, MMM d • h:mm a', 'en').format(value);
  }

  String _remainingText(Deadline deadline) {
    final difference = deadline.due.difference(DateTime.now());
    if (difference.isNegative) return t('Overdue', 'متأخر');

    final minutes = difference.inMinutes;
    final days = minutes ~/ 1440;
    final hours = (minutes % 1440) ~/ 60;
    final mins = minutes % 60;

    if (_ar) {
      if (days > 0) {
        return hours > 0 ? 'متبقي $days يوم و$hours ساعة' : 'متبقي $days يوم';
      }
      if (hours > 0) {
        return mins > 0
            ? 'متبقي $hours ساعة و$mins دقيقة'
            : 'متبقي $hours ساعة';
      }
      return 'متبقي $mins دقيقة';
    }

    if (days > 0) return '${days}d${hours > 0 ? ' ${hours}h' : ''} left';
    if (hours > 0) return '${hours}h${mins > 0 ? ' ${mins}m' : ''} left';
    return '${mins}m left';
  }

  String _displayCourse(String value) => value.replaceAll('_', ' — ').trim();

  Color _urgency(Deadline deadline) {
    final hours = deadline.hoursRemaining;
    if (hours < 24) return Colors.red;
    if (hours < 72) return Colors.orange;
    if (hours < 168) return Colors.amber.shade800;
    return Theme.of(context).colorScheme.primary;
  }

  Future<void> _showDeadline(Deadline deadline) async {
    final isManual = widget.controller.manualDeadlines.any(
      (task) => task.stableKey == deadline.stableKey,
    );
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                deadline.title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              if (deadline.course.isNotEmpty)
                Text(_displayCourse(deadline.course)),
              Text(_formatDue(deadline.due)),
              if (deadline.description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(deadline.description),
              ],
              const SizedBox(height: 12),
              if (isManual) ...[
                Text(
                  t('Reminder', 'التذكير'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  deadline.reminderMinutesBefore == null
                      ? t('Default reminders', 'التذكيرات الافتراضية')
                      : deadline.reminderMinutesBefore == -1
                      ? t('No notifications', 'بدون إشعارات')
                      : deadline.reminderMinutesBefore! < 60
                      ? t(
                          '${deadline.reminderMinutesBefore} minutes before',
                          'قبل ${deadline.reminderMinutesBefore} دقيقة',
                        )
                      : t(
                          '${deadline.reminderMinutesBefore! ~/ 60} hours before',
                          'قبل ${deadline.reminderMinutesBefore! ~/ 60} ساعة',
                        ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    if (mounted) _addManualTask(existing: deadline);
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(t('Edit task', 'تعديل المهمة')),
                ),
                TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    if (!mounted) return;
                    final confirmed = await showDialog<bool>(
                      context: this.context,
                      builder: (dialogContext) => AlertDialog(
                        title: Text(t('Delete task?', 'حذف المهمة؟')),
                        content: Text(
                          t(
                            'This task will be removed from this device.',
                            'سيتم حذف هذه المهمة من الجهاز.',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(dialogContext, false),
                            child: Text(t('Cancel', 'إلغاء')),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext, true),
                            child: Text(t('Delete', 'حذف')),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await widget.controller.deleteManualDeadline(deadline);
                    }
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: Text(t('Delete task', 'حذف المهمة')),
                ),
              ] else ...[
                Text(t('Task reminders', 'تذكيرات المهمة')),
                Wrap(
                  spacing: 8,
                  children: [1, 6, 24, 48, 72].map((hours) {
                    final specific = widget
                        .controller
                        .taskReminderOffsets[deadline.stableKey];
                    final selected =
                        (specific ?? widget.controller.reminderOffsets)
                            .contains(hours);
                    return FilterChip(
                      label: Text(_offsetLabel(hours)),
                      selected: selected,
                      onSelected: (checked) async {
                        final values = [
                          ...(specific ?? widget.controller.reminderOffsets),
                        ];
                        if (checked) {
                          values.add(hours);
                        } else {
                          values.remove(hours);
                        }
                        await widget.controller.setTaskReminderOffsets(
                          deadline,
                          values,
                        );
                        if (context.mounted) Navigator.pop(context);
                        if (mounted) _showDeadline(deadline);
                      },
                    );
                  }).toList(),
                ),
                TextButton(
                  onPressed: () async {
                    await widget.controller.setTaskReminderOffsets(
                      deadline,
                      null,
                    );
                    if (context.mounted) Navigator.pop(context);
                    if (mounted) _showDeadline(deadline);
                  },
                  child: Text(
                    t('Use global reminders', 'استخدام التذكيرات العامة'),
                  ),
                ),
              ],
              if (deadline.url.isNotEmpty) ...[
                OutlinedButton.icon(
                  onPressed: () async {
                    final uri = Uri.tryParse(deadline.url);
                    if (uri == null ||
                        (uri.scheme != 'https' && uri.scheme != 'http') ||
                        !uri.hasAuthority) {
                      return;
                    }
                    final opened = await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    );
                    if (!opened && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            t(
                              'Could not open Moodle link',
                              'تعذر فتح رابط Moodle',
                            ),
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: Text(t('Open in Moodle', 'افتح في Moodle')),
                ),
                const SizedBox(height: 10),
                Directionality(
                  textDirection: ui.TextDirection.ltr,
                  child: SelectableText(deadline.url),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    await widget.controller.toggleCompleted(deadline);
                    if (context.mounted) Navigator.pop(context);
                  },
                  icon: Icon(
                    widget.controller.completedIds.contains(deadline.stableKey)
                        ? Icons.undo_rounded
                        : Icons.check_rounded,
                  ),
                  label: Text(
                    widget.controller.completedIds.contains(deadline.stableKey)
                        ? t('Mark active', 'إرجاعه نشطًا')
                        : t('Mark completed', 'تحديد كمكتمل'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCourse(String course, List<Deadline> deadlines) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _displayCourse(course),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              ...deadlines.take(8).map(_deadlineCard),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Disconnect Moodle?', 'فصل Moodle؟')),
        content: Text(
          t(
            'This removes the private calendar URL and cached deadline data from this app.',
            'سيؤدي هذا إلى حذف رابط التقويم الخاص والبيانات المخزنة من التطبيق.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('Cancel', 'إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('Disconnect', 'فصل')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.controller.disconnect();
      if (mounted) setState(() => _index = 0);
    }
  }
}

class _Setup extends StatefulWidget {
  const _Setup({required this.controller});
  final AppController controller;

  @override
  State<_Setup> createState() => _SetupState();
}

class _SetupState extends State<_Setup> {
  final _url = TextEditingController();
  final _server = TextEditingController();

  bool get _ar => widget.controller.locale.languageCode == 'ar';
  String t(String en, String ar) => _ar ? ar : en;

  @override
  void dispose() {
    _url.dispose();
    _server.dispose();
    super.dispose();
  }

  Future<void> _getCalendarFromLogin() async {
    if (MoodleBrowserLogin.universityLoginUrl(_server.text) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              'Enter the Moodle site HTTPS address (not the calendar token).',
              'أدخل رابط موقع Moodle الآمن، وليس رابط التقويم.',
            ),
          ),
        ),
      );
      return;
    }
    final url = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) =>
            MoodleCalendarBrowser(server: _server.text.trim(), arabic: _ar),
      ),
    );
    if (!mounted || url == null) return;
    _url.text = url;
    final saved = await widget.controller.connect(url);
    if (saved && mounted) {
      Navigator.of(context).pop();
    } else if (mounted) {
      setState(() {});
    }
  }

  Future<void> _importDownloadedIcs() async {
    try {
      final selected = await FilePicker.pickFiles();
      if (selected.isEmpty) return;
      final picked = selected.first;
      if (picked.path == null || !picked.name.toLowerCase().endsWith('.ics')) {
        throw const FormatException('Choose an .ics calendar file.');
      }
      final file = File(picked.path!);
      if (await file.length() > 2 * 1024 * 1024) {
        throw const FormatException('Calendar file is too large.');
      }
      final contents = utf8
          .decode(await file.readAsBytes(), allowMalformed: true)
          .replaceFirst('\uFEFF', '')
          .trim();
      if (!contents.startsWith('BEGIN:VCALENDAR') ||
          !contents.endsWith('END:VCALENDAR')) {
        throw const FormatException('Not a complete iCalendar file.');
      }
      final deadlines = IcsParser.parse(contents);
      if (deadlines.isEmpty) {
        throw const FormatException('No importable deadlines found.');
      }
      await widget.controller.importSessionDeadlines(deadlines);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              'Invalid ICS file or no deadlines found.',
              'ملف ICS غير صالح أو لا يحتوي على مواعيد.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t('Masari', 'مساري')),
        actions: [
          TextButton(
            onPressed: () =>
                widget.controller.setLocale(Locale(_ar ? 'en' : 'ar')),
            child: Text(_ar ? 'EN' : 'العربية'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Icon(
            Icons.event_available_rounded,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            t('Connect your Moodle calendar', 'اربط تقويم Moodle'),
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          Text(
            t(
              'Open Moodle Calendar, choose Export calendar, then Get calendar URL. Paste the subscription link below.',
              'افتح تقويم Moodle، اختر تصدير التقويم ثم الحصول على رابط التقويم، والصقه أدناه.',
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: t('Moodle calendar URL', 'رابط تقويم Moodle'),
              prefixIcon: const Icon(Icons.link_rounded),
              suffixIcon: IconButton(
                tooltip: t('Paste', 'لصق'),
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data?.text != null) _url.text = data!.text!.trim();
                },
                icon: const Icon(Icons.content_paste_rounded),
              ),
            ),
          ),
          if (widget.controller.error != null) ...[
            const SizedBox(height: 10),
            Text(
              SyncFeedback.errorMessage(widget.controller.error!, arabic: _ar),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            t(
              'Or connect using university sign-in',
              'أو اربط عبر دخول الجامعة',
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _server,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: t(
                'University Moodle HTTPS site',
                'موقع Moodle الجامعي HTTPS',
              ),
              hintText: 'https://moodle.university.edu',
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: widget.controller.busy ? null : _getCalendarFromLogin,
            icon: const Icon(Icons.login_rounded),
            label: Text(
              t(
                'Sign in and fetch calendar link',
                'تسجيل الدخول وجلب رابط التقويم',
              ),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: widget.controller.busy
                ? null
                : () async {
                    final ok = await widget.controller.connect(_url.text);
                    if (!context.mounted) return;
                    if (ok) {
                      Navigator.of(context).pop();
                    } else {
                      setState(() {});
                    }
                  },
            icon: widget.controller.busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.lock_open_rounded),
            label: Text(t('Connect securely', 'اتصال آمن')),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: widget.controller.busy ? null : _importDownloadedIcs,
            icon: const Icon(Icons.upload_file_outlined),
            label: Text(
              t('Import a downloaded .ics file', 'استيراد ملف ICS تم تنزيله'),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            t(
              'Imported deadlines are stored locally and do not auto-refresh.',
              'الاستيراد يحفظ المواعيد على جهازك، ولا يحدّثها تلقائيًا.',
            ),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.title,
    required this.next,
    required this.nextDueText,
    required this.nextRemainingText,
    required this.lastSyncText,
    required this.isArabic,
  });

  final String title;
  final Deadline? next;
  final String? nextDueText;
  final String? nextRemainingText;
  final String? lastSyncText;
  final bool isArabic;

  String t(String en, String ar) => isArabic ? ar : en;

  @override
  Widget build(BuildContext context) {
    const start = Color(0xFF1379D6);
    const end = Color(0xFF0A316F);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [start, end]),
        borderRadius: BorderRadius.circular(24),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            if (next == null)
              Text(t('Nothing urgent right now.', 'لا يوجد شيء عاجل الآن.'))
            else ...[
              Text(
                t('NEXT DEADLINE', 'الموعد التالي'),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .82),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                next!.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              if (nextRemainingText != null) ...[
                const SizedBox(height: 7),
                Text(
                  nextRemainingText!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              if (nextDueText != null) ...[
                const SizedBox(height: 3),
                Text(
                  nextDueText!,
                  style: TextStyle(color: Colors.white.withValues(alpha: .9)),
                ),
              ],
            ],
            if (lastSyncText != null) ...[
              const SizedBox(height: 12),
              Text(
                lastSyncText!,
                style: TextStyle(color: Colors.white.withValues(alpha: .78)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DeadlineCalendar extends StatelessWidget {
  const _DeadlineCalendar({
    required this.selectedDate,
    required this.deadlines,
    required this.localeName,
    required this.onDateChanged,
  });

  final DateTime selectedDate;
  final List<Deadline> deadlines;
  final String localeName;
  final ValueChanged<DateTime> onDateChanged;

  bool get isArabic => localeName == 'ar';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final monthStart = DateTime(selectedDate.year, selectedDate.month, 1);
    final daysInMonth = DateTime(
      selectedDate.year,
      selectedDate.month + 1,
      0,
    ).day;
    final offset = isArabic
        ? (monthStart.weekday + 1) % 7
        : monthStart.weekday % 7;
    final cellCount = ((offset + daysInMonth + 6) ~/ 7) * 7;
    final weekdays = isArabic
        ? const ['سبت', 'أحد', 'اثن', 'ثلا', 'أرب', 'خمي', 'جمع']
        : const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: isArabic ? 'الشهر السابق' : 'Previous month',
              onPressed: () => _moveMonth(-1),
              icon: Icon(
                isArabic
                    ? Icons.chevron_right_rounded
                    : Icons.chevron_left_rounded,
              ),
            ),
            Expanded(
              child: Text(
                DateFormat.yMMMM(localeName).format(selectedDate),
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              tooltip: isArabic ? 'الشهر التالي' : 'Next month',
              onPressed: () => _moveMonth(1),
              icon: Icon(
                isArabic
                    ? Icons.chevron_left_rounded
                    : Icons.chevron_right_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: weekdays
              .map(
                (label) => Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: 0.82,
          ),
          itemCount: cellCount,
          itemBuilder: (context, index) {
            final day = index - offset + 1;
            if (day < 1 || day > daysInMonth) return const SizedBox.shrink();

            final date = DateTime(selectedDate.year, selectedDate.month, day);
            final selected = _sameDay(date, selectedDate);
            final today = _sameDay(date, DateTime.now());
            final eventCount = deadlines
                .where((deadline) => _sameDay(deadline.due, date))
                .length;
            final markerCount = eventCount > 3 ? 3 : eventCount;

            return Semantics(
              button: true,
              selected: selected,
              label: eventCount == 0
                  ? DateFormat.yMMMMd(localeName).format(date)
                  : '${DateFormat.yMMMMd(localeName).format(date)}, $eventCount ${isArabic ? 'أحداث' : 'events'}',
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => onDateChanged(date),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected ? scheme.primary : Colors.transparent,
                          border: today && !selected
                              ? Border.all(color: scheme.primary, width: 1.4)
                              : null,
                        ),
                        child: Text(
                          '$day',
                          style: TextStyle(
                            color: selected
                                ? scheme.onPrimary
                                : scheme.onSurface,
                            fontWeight: selected || today
                                ? FontWeight.w800
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 8,
                        child: markerCount == 0
                            ? null
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(
                                  markerCount,
                                  (_) => Container(
                                    width: 5,
                                    height: 5,
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: selected
                                          ? scheme.primary
                                          : scheme.secondary,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  void _moveMonth(int delta) {
    final target = DateTime(selectedDate.year, selectedDate.month + delta, 1);
    final lastDay = DateTime(target.year, target.month + 1, 0).day;
    final day = selectedDate.day > lastDay ? lastDay : selectedDate.day;
    onDateChanged(DateTime(target.year, target.month, day));
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
