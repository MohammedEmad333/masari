import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_controller.dart';
import '../models/deadline.dart';
import '../services/notification_service.dart';
import '../services/deadline_filters.dart';

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
  DateTime _selectedDate = DateTime.now();

  bool get _ar => widget.controller.locale.languageCode == 'ar';
  String t(String en, String ar) => _ar ? ar : en;
  String get _localeName => _ar ? 'ar' : 'en';

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (!controller.initialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!controller.calendarConnected) return _Setup(controller: controller);

    final titles = [
      t('Home', 'الرئيسية'),
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
            tooltip: t('Sync now', 'مزامنة الآن'),
            onPressed: controller.busy ? null : _sync,
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
        children: [_home(), _calendar(), _courses(), _settings()],
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

  Future<void> _sync() async {
    final ok = await widget.controller.sync();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? t('Moodle calendar synced.', 'تمت مزامنة تقويم Moodle.')
              : widget.controller.error ?? t('Sync failed.', 'فشلت المزامنة.'),
        ),
      ),
    );
  }

  Widget _home() {
    final controller = widget.controller;
    final active = controller.activeDeadlines;
    final deadlines = filterDeadlines(
      active,
      query: _searchQuery,
      course: _selectedCourse,
    );
    final overdue = deadlines.where((d) => d.isPast).toList();
    final upcoming = deadlines.where((d) => !d.isPast).toList();
    final next = upcoming.isEmpty ? null : upcoming.first;
    final weekEnd = DateTime.now().add(const Duration(days: 7));
    final weekCount = upcoming.where((d) => d.due.isBefore(weekEnd)).length;

    return RefreshIndicator(
      onRefresh: () => controller.sync(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
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
          if (controller.error != null) ...[
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.error_outline_rounded),
                title: Text(controller.error!),
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              labelText: t('Search deadlines', 'ابحث عن المهام'),
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _selectedCourse ?? '',
            decoration: InputDecoration(
              labelText: t('Filter by course', 'تصفية حسب المساق'),
            ),
            items: [
              DropdownMenuItem(
                value: '',
                child: Text(t('All courses', 'كل المساقات')),
              ),
              ...({
                ...active.map((d) => d.course),
              }.where((c) => c.isNotEmpty).toList()..sort()).map(
                (course) =>
                    DropdownMenuItem(value: course, child: Text(course)),
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
      ),
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
    final grouped = <String, List<Deadline>>{};
    for (final deadline in widget.controller.activeDeadlines) {
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

  Widget _settings() {
    final controller = widget.controller;
    const choices = [72, 48, 24, 6, 1];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
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
                onTap: NotificationService.showTest,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.sync_rounded),
                title: Text(t('Sync now', 'مزامنة الآن')),
                subtitle: Text(_lastSyncText()),
                onTap: controller.busy ? null : _sync,
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
              Text(t('Task reminders', 'تذكيرات المهمة')),
              Wrap(
                spacing: 8,
                children: [1, 6, 24, 48, 72].map((hours) {
                  final specific =
                      widget.controller.taskReminderOffsets[deadline.stableKey];
                  final selected =
                      (specific ?? widget.controller.reminderOffsets).contains(
                        hours,
                      );
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
  bool get _ar => widget.controller.locale.languageCode == 'ar';
  String t(String en, String ar) => _ar ? ar : en;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Moodle Reminder'),
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
            Icons.notifications_active_rounded,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            t(
              'Never miss another Moodle deadline',
              'لا تفوّت موعد Moodle بعد الآن',
            ),
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            t(
              'Connect Moodle once. Your private calendar URL stays in secure device storage.',
              'اربط Moodle مرة واحدة. يبقى رابط التقويم الخاص محفوظًا في التخزين الآمن للجهاز.',
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ...[
            t('Open Moodle Calendar', 'افتح تقويم Moodle'),
            t('Choose Export calendar', 'اختر تصدير التقويم'),
            t(
              'Copy the generated calendar URL',
              'انسخ رابط التقويم الذي تم إنشاؤه',
            ),
          ].asMap().entries.map(
            (entry) => ListTile(
              leading: CircleAvatar(child: Text('${entry.key + 1}')),
              title: Text(entry.value),
            ),
          ),
          const SizedBox(height: 12),
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
              widget.controller.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: widget.controller.busy
                ? null
                : () async {
                    final ok = await widget.controller.connect(_url.text);
                    if (!ok && mounted) setState(() {});
                  },
            icon: widget.controller.busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.lock_open_rounded),
            label: Text(t('Connect securely', 'اتصال آمن')),
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
    const start = Color(0xFFF98012);
    const end = Color(0xFF8A430D);
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
                                          : const Color(0xFFF98012),
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
