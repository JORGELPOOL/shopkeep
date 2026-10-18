import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;

// Palette: deep teal ink, market-sun yellow, cool pale canvas. Strong contrast for bright outdoor screens.
const ink = Color(0xFF0E3B38), sun = Color(0xFFF2B01E), canvas = Color(0xFFF1F5F3), line = Color(0xFFDCE5E1);
const inkText = Color(0xFF13201E), muted = Color(0xFF5B6E69), good = Color(0xFF1E8E5F), bad = Color(0xFFC8402F);
const marigold = sun, marigoldTint = Color(0xFFFCF0CE), badTint = Color(0xFFF8E1DC);

/// Money and counts line up in columns when digits are the same width.
TextStyle figs(double size, {FontWeight w = FontWeight.w700, Color? c}) =>
    TextStyle(fontSize: size, fontWeight: w, color: c, fontFeatures: const [FontFeature.tabularFigures()]);

ThemeData buildTheme() {
  OutlineInputBorder b(Color c, [double w = 1]) => OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c, width: w));
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: ink, primary: ink, secondary: sun, surface: Colors.white),
    scaffoldBackgroundColor: canvas,
    appBarTheme: const AppBarTheme(backgroundColor: canvas, elevation: 0, scrolledUnderElevation: 0, foregroundColor: inkText,
        titleTextStyle: TextStyle(color: inkText, fontSize: 22, fontWeight: FontWeight.w800)),
    inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: Colors.white, border: b(line), enabledBorder: b(line), focusedBorder: b(ink, 2)),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(64, 52), foregroundColor: ink,
        side: const BorderSide(color: line, width: 1.5), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
    navigationBarTheme: NavigationBarThemeData(backgroundColor: Colors.white, elevation: 0, indicatorColor: marigoldTint,
        labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
  );
}

class Panel extends StatelessWidget {
  final Widget child; final EdgeInsets padding;
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16)});
  @override
  Widget build(BuildContext context) => Container(width: double.infinity, padding: padding,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: line)), child: child);
}

class Pill extends StatelessWidget {
  final String text; final Color bg, fg;
  const Pill(this.text, {super.key, this.bg = marigoldTint, this.fg = inkText});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700)));
}

/// Letter tile in a soft tint, picked from the name so the same item always looks the same.
class Avatar extends StatelessWidget {
  final String name; final double size;
  const Avatar(this.name, {super.key, this.size = 44});
  static const _tints = [Color(0xFFD6EBE4), Color(0xFFF9E6B3), Color(0xFFDCE4F5), Color(0xFFF3D9D2), Color(0xFFE5DDF2)];
  @override
  Widget build(BuildContext context) => Container(width: size, height: size, alignment: Alignment.center,
      decoration: BoxDecoration(color: _tints[name.codeUnits.fold(0, (a, b) => a + b) % _tints.length], borderRadius: BorderRadius.circular(size * .32)),
      child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: TextStyle(fontSize: size * .42, fontWeight: FontWeight.w800, color: ink)));
}

/// An empty screen is an invitation to act.
class Empty extends StatelessWidget {
  final IconData icon; final String title, hint;
  const Empty(this.icon, this.title, this.hint, {super.key});
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 72, height: 72, decoration: const BoxDecoration(color: marigoldTint, shape: BoxShape.circle), child: Icon(icon, color: ink, size: 32)),
        const SizedBox(height: 16),
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(hint, textAlign: TextAlign.center, style: const TextStyle(color: muted)),
      ])));
}

class Notice extends StatelessWidget {
  final IconData icon; final Color bg; final String title, sub; final VoidCallback? onTap; final Widget? trailing;
  const Notice(this.icon, this.bg, this.title, {super.key, this.sub = '', this.onTap, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(top: 12), child: Material(color: bg, borderRadius: BorderRadius.circular(18),
      child: InkWell(borderRadius: BorderRadius.circular(18), onTap: onTap, child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
        Icon(icon, color: inkText), const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)), if (sub.isNotEmpty) Text(sub, style: figs(13, w: FontWeight.w500))])),
        trailing ?? (onTap != null ? const Icon(Icons.chevron_right) : const SizedBox()),
      ])))));
}

/// The line draws itself left to right, with a dot riding the tip.
class Spark extends StatelessWidget {
  final List<double> v; final Color color;
  const Spark(this.v, {super.key, required this.color});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: 1), duration: const Duration(milliseconds: 900), curve: Curves.easeOutCubic,
      builder: (_, t, __) => CustomPaint(size: Size.infinite, painter: _SparkPainter(v, color, t)));
}

class _SparkPainter extends CustomPainter {
  final List<double> v; final Color color; final double t;
  _SparkPainter(this.v, this.color, this.t);
  @override
  void paint(Canvas c, Size s) {
    if (v.length < 2) return;
    final lo = v.reduce((a, b) => a < b ? a : b), hi = v.reduce((a, b) => a > b ? a : b), span = (hi - lo) == 0 ? 1 : hi - lo;
    Offset pt(int i) => Offset(s.width * i / (v.length - 1), s.height - 6 - (s.height - 12) * (v[i] - lo) / span);
    final path = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < v.length; i++) { path.lineTo(pt(i).dx, pt(i).dy); }
    final m = path.computeMetrics().first;
    c.drawPath(m.extractPath(0, m.length * t), Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 3..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
    c.drawCircle(m.getTangentForOffset(m.length * t)?.position ?? pt(v.length - 1), 5, Paint()..color = color);
  }
  @override
  bool shouldRepaint(_SparkPainter o) => o.t != t || o.v != v;
}

/// Bold section title with a sun-yellow marker. `small` is for lists inside a screen (e.g. day groups).
class SectionHeader extends StatelessWidget {
  final String title; final bool small; final Widget? trailing;
  const SectionHeader(this.title, {super.key, this.small = false, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(padding: EdgeInsets.fromLTRB(4, small ? 14 : 26, 4, 10), child: Row(children: [
        Container(width: 5, height: small ? 16 : 24, decoration: BoxDecoration(color: sun, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 10),
        Expanded(child: Text(title, style: TextStyle(fontSize: small ? 16 : 22, fontWeight: FontWeight.w900, letterSpacing: -.3, color: inkText))),
        if (trailing != null) trailing!,
      ]));
}

/// Fades and lifts into place. `index` staggers a list so rows arrive one after another.
class FadeSlide extends StatelessWidget {
  final Widget child; final int index;
  const FadeSlide({super.key, required this.child, this.index = 0});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: 1), curve: Curves.easeOutCubic,
      duration: Duration(milliseconds: 280 + (index > 8 ? 8 : index) * 60),
      builder: (_, v, c) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 14 * (1 - v)), child: c)), child: child);
}

/// A money amount that rolls up to its value, and rolls again whenever the value changes.
class CountUp extends StatelessWidget {
  final double value; final TextStyle style;
  const CountUp(this.value, {super.key, required this.style});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: value), duration: const Duration(milliseconds: 700), curve: Curves.easeOutCubic,
      builder: (_, v, __) => Text(money.format(v), style: style));
}

/// Sign-in frame: ink header, rounded sheet for the form.
class AuthShell extends StatelessWidget {
  final String title, subtitle; final List<Widget> children;
  const AuthShell({super.key, required this.title, required this.subtitle, required this.children});
  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: ink, body: SafeArea(bottom: false, child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(24, 24, 24, 24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: sun, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.storefront, color: ink)),
            const SizedBox(width: 12), const Text('ShopKeep', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 28),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, height: 1.1)),
          const SizedBox(height: 6), Text(subtitle, style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 15)),
        ])),
        Expanded(child: Container(width: double.infinity, decoration: const BoxDecoration(color: canvas, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
            child: ListView(padding: const EdgeInsets.all(24), children: children))),
      ])));
}

final money = NumberFormat.currency(symbol: 'GH₵', decimalDigits: 2);
void snack(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

Widget field(TextEditingController c, String label, {bool num = false, bool secret = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(controller: c, obscureText: secret, keyboardType: num ? TextInputType.number : null, decoration: InputDecoration(labelText: label)));
