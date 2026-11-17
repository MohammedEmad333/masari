import 'package:flutter/material.dart';

import '../theme/masari_theme.dart';

/// Read-only study summary. Counts are calculated by the caller's existing
/// StudyInsights service so the dashboard never changes stored task data.
class MasariStudyOverview extends StatelessWidget {
  const MasariStudyOverview({
    super.key,
    required this.arabic,
    required this.completionPercent,
    required this.dueSoonCount,
    required this.overdueCount,
    required this.conflictCount,
  });

  final bool arabic;
  final int completionPercent;
  final int dueSoonCount;
  final int overdueCount;
  final int conflictCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final metrics = [
      (
        icon: Icons.donut_large_rounded,
        value: '$completionPercent%',
        title: arabic ? 'الإنجاز' : 'Completed',
        color: scheme.primary,
      ),
      (
        icon: Icons.event_available_outlined,
        value: '$dueSoonCount',
        title: arabic ? 'خلال 7 أيام' : 'Next 7 days',
        color: scheme.primary,
      ),
      (
        icon: Icons.schedule_outlined,
        value: '$overdueCount',
        title: arabic ? 'مواعيد فائتة' : 'Overdue',
        color: overdueCount > 0 ? scheme.error : scheme.primary,
      ),
      (
        icon: Icons.compare_arrows_rounded,
        value: '$conflictCount',
        title: arabic ? 'تعارضات' : 'Conflicts',
        color: conflictCount > 0 ? scheme.error : scheme.primary,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // One column at narrow widths, two otherwise. Do not squeeze cards
        // under large text scales or small-screen layouts.
        final spacing = MasariSpacing.sm;
        final columns = constraints.maxWidth >= 330 ? 2 : 1;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: width,
                child: Semantics(
                  label: '${metric.title}: ${metric.value}',
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(MasariSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(metric.icon, color: metric.color, size: 23),
                          const SizedBox(height: MasariSpacing.sm),
                          Text(
                            metric.value,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: MasariSpacing.xs),
                          Text(
                            metric.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
