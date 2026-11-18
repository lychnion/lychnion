import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../knowledge/language.dart';

/// Lychnion brand colours (brand canvas, board 4). No red: red and orange
/// stay reserved for official warnings the app relays.
abstract final class Brand {
  /// Where the source code is (AGPL: offered to every user).
  static const sourceUrl = 'https://github.com/lychnion/lychnion';

  static const name = 'Lychnion';
  static const nameJa = 'リクニオン';

  // The name in running text is the app text `appName` (リクニオン in
  // Japanese, Lychnion in English).

  static const night = Color(0xFF16233F);
  static const night2 = Color(0xFF22314F);
  static const glow = Color(0xFFF2B544);
  static const glowDeep = Color(0xFF8A5A00);
  static const harborBlue = Color(0xFF1D4F7A);
  static const sky = Color(0xFF9CC3EE);
  static const paper = Color(0xFFFAF7F0);
  static const mist = Color(0xFFE6E2D8);
  static const line = Color(0xFFC9C4B8);
  static const stone = Color(0xFF5F5E5A);
  static const ink = Color(0xFF1A1C22);
  static const moonlight = Color(0xFFEDEBE4);
  static const haze = Color(0xFFA9B0BF);

  /// App text, Japanese and English (a universal-design font).
  static const textFont = 'BIZUDPGothic';

  /// The wordmark and English headings.
  static const wordmarkFont = 'Lexend';

  /// リクニオン in the logo (only these letters are bundled).
  static const wordmarkFontJa = 'ZenMaruGothic';

  /// The name as a wordmark: "Lychnion" in Lexend for languages written in
  /// Latin letters, 「リクニオン」 in Zen Maru Gothic for Japanese.
  static TextStyle wordmarkStyle({required String lang, Color? color}) =>
      usesLatinScript(lang)
      ? TextStyle(
          fontFamily: wordmarkFont,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.3,
          color: color,
        )
      : TextStyle(
          fontFamily: wordmarkFontJa,
          fontFamilyFallback: const [textFont],
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: color,
        );
}

/// Shows the fonts' licences on the app's licence page.
/// Registers the app's own licence and the brand fonts' licences for the
/// licence page (showLicensePage).
void addLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      [Brand.name],
      'Copyright the Lychnion authors.\n\n'
      'Free software under the GNU Affero General Public License, '
      'version 3, with an app store exception. You may share and change '
      'it; anyone who passes it on must give its users the source code.\n\n'
      'Source code: ${Brand.sourceUrl}',
    );
  });
  for (final (family, file) in const [
    ('BIZ UDPGothic', 'assets/fonts/OFL-BIZUDPGothic.txt'),
    ('Lexend', 'assets/fonts/OFL-Lexend.txt'),
    ('Zen Maru Gothic', 'assets/fonts/OFL-ZenMaruGothic.txt'),
  ]) {
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks([
        family,
      ], await rootBundle.loadString(file));
    });
  }
}

/// The Lychnion mark: an open roof (shelter), the amber light (you on the
/// map) and a small pointer (here). Drawn from the 64-unit master; below
/// 24 px it uses the small drawing (heavier roof, larger light).
class LychnionMark extends StatelessWidget {
  const LychnionMark({super.key, this.size = 32, this.onDark});

  final double size;

  /// Light roof and pointer for dark grounds. Default: from the theme.
  final bool? onDark;

  @override
  Widget build(BuildContext context) {
    final dark = onDark ?? Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      label: Brand.name,
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _MarkPainter(dark: dark, small: size <= 24),
        ),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter({required this.dark, required this.small});

  final bool dark, small;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 64, size.height / 64);
    final ink = dark ? Brand.moonlight : Brand.night;
    final roof = Path();
    final pointer = Path();
    if (small) {
      roof
        ..moveTo(10, 25)
        ..lineTo(32, 9)
        ..lineTo(54, 25);
      pointer
        ..moveTo(25, 52)
        ..lineTo(39, 52)
        ..lineTo(32, 61)
        ..close();
    } else {
      roof
        ..moveTo(12, 25)
        ..lineTo(32, 10)
        ..lineTo(52, 25);
      pointer
        ..moveTo(26.5, 51)
        ..lineTo(37.5, 51)
        ..lineTo(32, 59)
        ..close();
    }
    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(roof, stroke..strokeWidth = small ? 8 : 5);
    canvas.drawPath(pointer, Paint()..color = ink);
    canvas.drawPath(pointer, stroke..strokeWidth = small ? 3 : 2);
    final c = Offset(32, small ? 37 : 36);
    final r = small ? 12.5 : 11.0;
    canvas.drawCircle(c, r, Paint()..color = Brand.glow);
    // On light grounds the light gets a Night outline.
    if (!dark) canvas.drawCircle(c, r, stroke..strokeWidth = small ? 4 : 2.6);
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.dark != dark || old.small != small;
}
