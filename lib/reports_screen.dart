import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'data.dart';
import 'ui.dart';

/// Charts appear as soon as there is a sale or expense. Tap any day, week or month to see its exact figures.
class ReportsScreen extends StatefulWidget { const ReportsScreen({super.key}); @override State<ReportsScreen> createState() => _ReportsState(); }

class _ReportsState extends State<ReportsScreen> {
  int mode = 0; // 0 daily, 1 weekly, 2 monthly
  int? sel;     // tapped bar group; null = the latest period

  List<MapEntry<String, int>> _topItems(DateTime from, DateTime to) {
    final m = <String, int>{};
    for (final s in Db.i.sales.values) {
      if (s['status'] != 'paid' && s['status'] != 'credit') continue;
      final t = DateTime.parse(s['ts']);
      if (t.isBefore(from) || !t.isBefore(to)) continue;
      for (final it in s['items']) { m[it['name']] = (m[it['name']] ?? 0) + (it['qty'] as int); }
    }
    return (m.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(5).toList();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: Db.i, builder: (_, __) {
    final n = DateTime.now(), today = DateTime(n.year, n.month, n.day), tomorrow = today.add(const Duration(days: 1));
    final periods = <(String, String, DateTime, DateTime)>[]; // short label, long label, from, to (oldest first)
    if (mode == 0) {
      for (var i = 6; i >= 0; i--) {
        final d = today.subtract(Duration(days: i));
        periods.add((DateFormat('E').format(d), DateFormat('EEE d MMM').format(d), d, d.add(const Duration(days: 1))));
      }
    } else if (mode == 1) {
      for (var i = 3; i >= 0; i--) {
        final end = tomorrow.subtract(Duration(days: 7 * i)), start = end.subtract(const Duration(days: 7));
        periods.add((DateFormat('d MMM').format(start), '${DateFormat('d MMM').format(start)} to ${DateFormat('d MMM').format(end.subtract(const Duration(days: 1)))}', start, end));
      }
    } else {
      for (var i = 5; i >= 0; i--) {
        final start = DateTime(n.year, n.month - i), end = DateTime(n.year, n.month - i + 1); // Dart rolls months over years
        periods.add((DateFormat('MMM').format(start), DateFormat('MMMM y').format(start), start, end));
      }
    }
    final sums = [for (final p in periods) Db.i.summary(p.$3, p.$4)];
    final sales = [for (final s in sums) s['revenue']!], profit = [for (final s in sums) s['profit']!];
    final totalSales = sales.fold<double>(0, (a, b) => a + b), totalProfit = profit.fold<double>(0, (a, b) => a + b);
    final hasData = sums.any((s) => s['revenue']! != 0 || s['expenses']! != 0);
    final top = _topItems(periods.first.$3, periods.last.$4), maxQty = top.isEmpty ? 1 : top.first.value;
    final si = (sel ?? periods.length - 1).clamp(0, periods.length - 1).toInt();

    Widget stat(String l, double v, {Color? c, double size = 18}) => Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(l, style: const TextStyle(color: muted, fontSize: 13, fontWeight: FontWeight.w600)), const SizedBox(height: 2), CountUp(v, style: figs(size, c: c))]));
    Widget dot(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))), const SizedBox(width: 6),
      Text(t, style: const TextStyle(fontSize: 12, color: muted, fontWeight: FontWeight.w600)), const SizedBox(width: 14)]);

    return Scaffold(appBar: AppBar(title: const Text('Reports')), body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
      SegmentedButton<int>(segments: const [ButtonSegment(value: 0, label: Text('Daily')), ButtonSegment(value: 1, label: Text('Weekly')), ButtonSegment(value: 2, label: Text('Monthly'))],
          selected: {mode}, onSelectionChanged: (s) => setState(() { mode = s.first; sel = null; })),
      if (!hasData) const SizedBox(height: 380, child: Empty(Icons.bar_chart, 'No data yet', 'Charts appear after your first sale or expense.')) else ...[
        SectionHeader(const ['Last 7 days', 'Last 4 weeks', 'Last 6 months'][mode]),
        FadeSlide(child: Panel(child: Row(children: [stat('Sales', totalSales), stat('Costs', totalSales - totalProfit), stat('Profit', totalProfit, c: totalProfit < 0 ? bad : good)]))),
        const SectionHeader('Sales and profit'),
        FadeSlide(index: 1, child: Panel(padding: const EdgeInsets.fromLTRB(12, 14, 12, 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AnimatedSwitcher(duration: const Duration(milliseconds: 200), child: Container(key: ValueKey('$mode-$si'), width: double.infinity, padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: marigoldTint, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(periods[si].$2, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)), const SizedBox(height: 6),
              Row(children: [stat('Sales', sales[si], size: 16), stat('Costs', sales[si] - profit[si], size: 16), stat('Profit', profit[si], c: profit[si] < 0 ? bad : good, size: 16)]),
            ]))),
          const SizedBox(height: 12),
          Row(children: [dot(ink, 'Sales'), dot(sun, 'Profit'), dot(bad, 'Loss'), const Spacer(), const Text('Tap a bar', style: TextStyle(fontSize: 12, color: muted))]),
          const SizedBox(height: 4),
          LayoutBuilder(builder: (ctx, box) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) {
              final gw = (box.maxWidth - _Bars.left) / periods.length, i = ((d.localPosition.dx - _Bars.left) / gw).floor();
              if (i >= 0 && i < periods.length) setState(() => sel = i);
            },
            child: SizedBox(height: 270, width: double.infinity, child: TweenAnimationBuilder<double>(key: ValueKey(mode), tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 800), curve: Curves.easeOutCubic,
              builder: (_, t, __) => CustomPaint(painter: _Bars([for (final p in periods) p.$1], sales, profit, t, si)))))),
        ]))),
        if (top.isNotEmpty) ...[
          const SectionHeader('Best sellers'),
          FadeSlide(index: 2, child: Panel(child: Column(children: [for (final e in top) Padding(padding: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Expanded(child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w700))), Text('x${e.value}', style: figs(14, c: muted))]),
            const SizedBox(height: 6),
            ClipRRect(borderRadius: BorderRadius.circular(6), child: TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: e.value / maxQty), duration: const Duration(milliseconds: 700), curve: Curves.easeOutCubic,
                builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: 10, color: sun, backgroundColor: canvas))),
          ]))]))),
        ],
        const SectionHeader('Period by period'),
        Panel(padding: const EdgeInsets.symmetric(vertical: 8), child: Column(children: [
          for (var k = 0; k < periods.length; k++) FadeSlide(index: k, child: ListTile(dense: true, onTap: () => setState(() => sel = periods.length - 1 - k),
            title: Text(periods[periods.length - 1 - k].$2, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('Sales ${money.format(sales[periods.length - 1 - k])}', style: figs(12, w: FontWeight.w500, c: muted)),
            trailing: Text(money.format(profit[periods.length - 1 - k]), style: figs(15, c: profit[periods.length - 1 - k] < 0 ? bad : good)))),
        ])),
      ],
    ]));
  });
}

/// Grouped bars that grow from the baseline. Every bar carries its value; the tapped group is highlighted.
class _Bars extends CustomPainter {
  static const left = 40.0;
  final List<String> labels; final List<double> sales, profit; final double t; final int sel;
  _Bars(this.labels, this.sales, this.profit, this.t, this.sel);

  static String compact(double v) => v.abs() >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : v.toStringAsFixed(0);

  void _text(Canvas c, String s, Offset mid, {Color color = muted, bool bold = false, double size = 10}) {
    final tp = TextPainter(text: TextSpan(text: s, style: TextStyle(fontSize: size, color: color, fontWeight: bold ? FontWeight.w900 : FontWeight.w600)), textDirection: TextDirection.ltr)..layout();
    tp.paint(c, Offset(mid.dx - tp.width / 2, mid.dy - tp.height / 2));
  }

  @override
  void paint(Canvas c, Size s) {
    const top = 24.0, bottom = 28.0;
    final h = s.height - top - bottom, hi = max(1.0, [...sales, ...profit].reduce(max)), lo = min(0.0, profit.reduce(min)), span = hi - lo;
    double y(double v) => top + h * (hi - v) / span;
    double yy(double v) => y(0) + (y(v) - y(0)) * t; // bars rise from the baseline as t goes 0 -> 1
    final n = labels.length, gw = (s.width - left) / n, bw = min(gw * .3, 24.0), fade = ((t - .6) / .4).clamp(0.0, 1.0);

    // selected group sits on a soft highlight
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(left + sel * gw + 3, top - 8, gw - 6, h + 16), const Radius.circular(14)), Paint()..color = marigoldTint);

    // gridlines and the scale
    for (final v in {hi, hi / 2, 0.0, if (lo < 0) lo}) {
      c.drawLine(Offset(left, y(v)), Offset(s.width, y(v)), Paint()..color = (v == 0 ? const Color(0xFFB9C7C2) : line)..strokeWidth = v == 0 ? 1.5 : 1);
      _text(c, compact(v), Offset(left - 20, y(v)));
    }

    for (var i = 0; i < n; i++) {
      final isSel = i == sel, x = left + i * gw + (gw - (bw * 2 + 4)) / 2;
      void bar(double x0, double v, Color col) {
        final a = yy(v), b = y(0), r = Rect.fromLTRB(x0, min(a, b), x0 + bw, max(a, b));
        if (v != 0) c.drawRRect(RRect.fromRectAndRadius(r.height < 2 ? Rect.fromLTRB(x0, b - 2, x0 + bw, b) : r, const Radius.circular(6)), Paint()..color = isSel ? col : Color.lerp(col, Colors.white, .35)!);
      }
      bar(x, sales[i], ink);
      bar(x + bw + 4, profit[i], profit[i] < 0 ? bad : sun);
      if (fade > 0) {
        // the sales figure sits on every bar; the selected group also shows its profit figure
        _text(c, compact(sales[i]), Offset(x + bw / 2, min(yy(sales[i]), y(0)) - 10), color: Color.fromRGBO(14, 59, 56, fade), bold: isSel);
        if (isSel) {
          final py = profit[i] >= 0 ? yy(profit[i]) - 10 : yy(profit[i]) + 10;
          _text(c, compact(profit[i]), Offset(x + bw + 4 + bw / 2, py), color: profit[i] < 0 ? bad : const Color(0xFF8A5D00), bold: true);
        }
      }
      _text(c, labels[i], Offset(left + i * gw + gw / 2, s.height - 10), color: isSel ? inkText : muted, bold: isSel, size: 11);
    }
  }

  @override
  bool shouldRepaint(_Bars o) => true;
}
