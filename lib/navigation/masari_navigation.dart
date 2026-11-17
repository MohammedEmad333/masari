import 'package:flutter/material.dart';

/// Primary Masari 2.3 destinations. All former flows remain available.
enum MasariTab { home, tasks, schedule, courses, more }

/// Calendar and study plan share one destination without losing their state.
enum MasariScheduleView { calendar, week }

class MasariPrimaryNavigation extends StatelessWidget {
  const MasariPrimaryNavigation({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.arabic,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final bool arabic;

  String tr(String en, String ar) => arabic ? ar : en;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      destinations: [
        NavigationDestination(
          icon: const Icon(Icons.home_outlined),
          selectedIcon: const Icon(Icons.home_rounded),
          label: tr('Home', 'الرئيسية'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.task_alt_outlined),
          selectedIcon: const Icon(Icons.task_alt_rounded),
          label: tr('Tasks', 'المهام'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.calendar_month_outlined),
          selectedIcon: const Icon(Icons.calendar_month_rounded),
          label: tr('Schedule', 'جدولي'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.school_outlined),
          selectedIcon: const Icon(Icons.school_rounded),
          label: tr('Courses', 'المساقات'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.more_horiz_rounded),
          selectedIcon: const Icon(Icons.more_rounded),
          label: tr('More', 'المزيد'),
        ),
      ],
    );
  }
}

class MasariSchedulePicker extends StatelessWidget {
  const MasariSchedulePicker({
    super.key,
    required this.value,
    required this.onChanged,
    required this.arabic,
  });

  final MasariScheduleView value;
  final ValueChanged<MasariScheduleView> onChanged;
  final bool arabic;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<MasariScheduleView>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(
          value: MasariScheduleView.calendar,
          icon: const Icon(Icons.calendar_month_outlined),
          label: Text(arabic ? 'التقويم' : 'Calendar'),
        ),
        ButtonSegment(
          value: MasariScheduleView.week,
          icon: const Icon(Icons.view_week_outlined),
          label: Text(arabic ? 'الأسبوع' : 'Week'),
        ),
      ],
      selected: {value},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}
