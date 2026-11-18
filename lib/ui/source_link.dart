import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../knowledge/knowledge_package.dart' show Source;

/// "出典：首相官邸ホームページ ↗": the attribution without its raw URL; tapping
/// opens the page in the browser (needs internet).
class SourceLink extends StatelessWidget {
  const SourceLink({
    super.key,
    required this.source,
    required this.style,
    this.suffix = '',
  });

  final Source source;
  final TextStyle? style;

  /// Added after the name, e.g. the licence.
  final String suffix;

  /// The attribution text with any "（https://…）" removed.
  static String label(Source s) => s.attribution
      .replaceAll(RegExp(r'\s*[（(]\s*https?://[^）)]*[）)]'), '')
      .replaceAll(RegExp(r'\s*https?://\S+'), '')
      .trim();

  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(source.url);
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) return;
    final ok = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    ).catchError((_) => false);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(source.url),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasUrl = source.url.startsWith('http');
    final text = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: label(source),
            style: hasUrl
                ? style?.copyWith(
                    decoration: TextDecoration.underline,
                    decorationColor: style?.color,
                  )
                : style,
          ),
          if (hasUrl)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Icon(
                  Icons.open_in_new_rounded,
                  size: (style?.fontSize ?? 13) + 1,
                  color: style?.color,
                ),
              ),
            ),
          if (suffix.isNotEmpty) TextSpan(text: suffix, style: style),
        ],
      ),
    );
    if (!hasUrl) return text;
    // A link for screen readers, and a full-height tap target.
    return Semantics(
      link: true,
      child: InkWell(
        onTap: () => _open(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: text,
          ),
        ),
      ),
    );
  }
}
