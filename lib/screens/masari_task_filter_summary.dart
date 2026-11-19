import 'package:flutter/material.dart';

import '../theme/masari_theme.dart';

/// Read-only filter feedback with a single safe reset action.
/// The parent owns search and course state, so tab changes keep filters intact.
class MasariTaskFilterSummary extends StatelessWidget {
  const MasariTaskFilterSummary({
    super.key,
    required this.arabic,
    required this.results,
    required this.onReset,
  });

  final bool arabic;
  final int results;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MasariSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              arabic ? '$results نتائج مطابقة' : '$results matching tasks',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          TextButton.icon(
            onPressed: onReset,
            icon: const Icon(Icons.filter_alt_off_outlined),
            label: Text(arabic ? 'مسح التصفية' : 'Clear filters'),
          ),
        ],
      ),
    );
  }
}
