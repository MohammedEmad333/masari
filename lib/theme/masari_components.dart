import 'package:flutter/material.dart';

import 'masari_theme.dart';

/// Reusable, direction-aware UI primitives for the Masari 2.3 redesign.
class MasariSectionHeader extends StatelessWidget {
  const MasariSectionHeader({
    super.key,
    required this.title,
    this.count,
  });

  final String title;
  final String? count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (count != null) Badge(label: Text(count!)),
      ],
    );
  }
}

class MasariEmptyState extends StatelessWidget {
  const MasariEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(MasariSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: theme.colorScheme.primary),
            const SizedBox(height: MasariSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: MasariSpacing.xs),
            Text(description, textAlign: TextAlign.center),
            if (action != null) ...[
              const SizedBox(height: MasariSpacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class MasariSettingsSection extends StatelessWidget {
  const MasariSettingsSection({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(MasariSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: MasariSpacing.md),
            child,
          ],
        ),
      ),
    );
  }
}
