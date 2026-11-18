import 'package:flutter/material.dart';

import '../app/lang.dart';
import '../knowledge/knowledge_package.dart' show PackageInfo;
import 'package_icons.dart';

/// "What it knows": the knowledge packages answers come from, and a way to
/// add more. Shows the app is not only for disasters.
class PackageRow extends StatelessWidget {
  const PackageRow({super.key, required this.packages, this.onAdd});

  final List<PackageInfo> packages;
  final VoidCallback? onAdd;

  /// The package's icon and its name in [lang], from its manifest.
  static (IconData, String) label(PackageInfo p, String lang) =>
      (packageIcon(p.icon), p.nameIn(lang));

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.packagesTitle,
          style: theme.textTheme.labelLarge?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in packages)
              Builder(
                builder: (context) {
                  final (icon, name) = label(p, context.lang);
                  return Tooltip(
                    message: '${p.title} ${p.version}',
                    child: Chip(
                      avatar: Icon(icon, size: 18, color: scheme.primary),
                      label: Text(name),
                    ),
                  );
                },
              ),
            if (onAdd != null)
              ActionChip(
                avatar: Icon(
                  Icons.add_rounded,
                  size: 18,
                  color: scheme.primary,
                ),
                label: Text(l.packagesAdd),
                tooltip: l.packagesAddTooltip,
                onPressed: onAdd,
              ),
          ],
        ),
      ],
    );
  }
}
