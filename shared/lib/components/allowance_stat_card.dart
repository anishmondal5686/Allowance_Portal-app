import 'package:flutter/material.dart';

/// A reusable Material 3 stat card for displaying an allowance label,
/// amount, and optional icon using [Theme.of(context).colorScheme] tokens.
class AllowanceStatCard extends StatelessWidget {
  const AllowanceStatCard({
    super.key,
    required this.label,
    required this.amount,
    this.icon,
    this.semanticLabel,
  });

  final String label;
  final String amount;
  final IconData? icon;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        label: semanticLabel ?? '$label $amount',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 22, color: scheme.primary),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  label,
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                amount,
                style: textTheme.titleMedium?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
