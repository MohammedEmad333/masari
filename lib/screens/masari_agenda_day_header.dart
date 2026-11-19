import 'package:flutter/material.dart';

import '../theme/masari_theme.dart';

/// Accessible agenda heading that fits small screens and large text scales.
class MasariAgendaDayHeader extends StatelessWidget {
  const MasariAgendaDayHeader({
    super.key,
    required this.dateLabel,
    required this.eventCount,
    required this.isToday,
    required this.arabic,
    required this.onToday,
  });

  final String dateLabel;
  final int eventCount;
  final bool isToday;
  final bool arabic;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: MasariSpacing.sm,
      runSpacing: MasariSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                dateLabel,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: MasariSpacing.sm),
            Badge(label: Text('$eventCount')),
          ],
        ),
        if (!isToday)
          TextButton.icon(
            onPressed: onToday,
            icon: const Icon(Icons.today_outlined),
            label: Text(arabic ? 'اليوم' : 'Today'),
          ),
      ],
    );
  }
}
