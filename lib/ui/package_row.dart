import 'package:flutter/material.dart';

import '../knowledge/knowledge_package.dart' show PackageInfo;

/// Icon and names for the packages we know; others show their own title.
const _known = <String, (IconData, String, String)>{
  'jp.bousai.core': (Icons.health_and_safety_rounded, '防災', 'Disasters'),
  'jp.outdoor.hiking': (Icons.hiking_rounded, '登山', 'Hiking'),
  'jp.outdoor.backcountry': (
    Icons.downhill_skiing_rounded,
    'バックカントリー',
    'Backcountry',
  ),
  'intl.firstaid.basics': (
    Icons.medical_services_outlined,
    '応急手当',
    'First aid',
  ),
  'jp.outdoor.sailing': (Icons.sailing_rounded, 'セーリング', 'Sailing'),
};

/// "What it knows": the knowledge packages answers come from, and a way to
/// add more. Shows the app is not only for disasters.
class PackageRow extends StatelessWidget {
  const PackageRow({
    super.key,
    required this.packages,
    required this.en,
    this.onAdd,
  });

  final List<PackageInfo> packages;
  final bool en;
  final VoidCallback? onAdd;

  static (IconData, String) label(PackageInfo p, bool en) {
    final k = _known[p.id];
    if (k == null) return (Icons.menu_book_rounded, p.title);
    return (k.$1, en ? k.$3 : k.$2);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          en ? 'Answers from' : '答えられる分野',
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
                  final (icon, name) = label(p, en);
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
                label: Text(en ? 'Add' : '追加'),
                tooltip: en ? 'Get more packages' : '分野を追加',
                onPressed: onAdd,
              ),
          ],
        ),
      ],
    );
  }
}
