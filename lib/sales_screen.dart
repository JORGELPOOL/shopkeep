import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'data.dart';
import 'momo.dart';
import 'receipt.dart';
import 'ui.dart';

Pill _status(String s) => switch (s) {
      'paid' => const Pill('Paid', bg: Color(0xFFDDF1E8), fg: good),
      'pending' => const Pill('Waiting'),
      'credit' => const Pill('On credit', bg: Color(0xFFDCE4F5)),
      'failed' => const Pill('Failed', bg: badTint, fg: bad),
      'cancelled' => const Pill('Cancelled', bg: canvas, fg: muted),
      'refunded' => const Pill('Refunded', bg: canvas, fg: muted),
      _ => Pill(s),
    };

class _Day { final String label; final double total; _Day(this.label, this.total); }

/// Every sale, newest first, grouped by day. Admin sees all; staff see only their own.
class SalesHistoryScreen extends StatefulWidget { const SalesHistoryScreen({super.key}); @override State<SalesHistoryScreen> createState() => _SalesState(); }

class _SalesState extends State<SalesHistoryScreen> {
  int filter = 0; // 0 all, 1 cash, 2 mobile money, 3 on credit, 4 not paid
  String q = '';
  static const _filters = ['All', 'Cash', 'Mobile money', 'On credit', 'Not paid'];

  bool _match(Map s) {
    if (!Db.i.isAdmin && s['staff'] != Db.i.session?['name']) return false;
    final ok = switch (filter) {
      1 => s['method'] == 'cash',
      2 => s['method'] == 'momo',
      3 => s['method'] == 'credit',
      4 => const ['pending', 'failed', 'cancelled'].contains(s['status']),
      _ => true,
    };
    if (!ok) return false;
    if (q.isEmpty) return true;
    final k = q.toLowerCase();
    return (s['phone'] ?? '').toString().contains(k) || (s['items'] as List).any((it) => it['name'].toString().toLowerCase().contains(k));
  }

  String _dayLabel(DateTime d) {
    final n = DateTime.now(), t = DateTime(n.year, n.month, n.day), x = DateTime(d.year, d.month, d.day);
    if (x == t) return 'Today';
    if (x == t.subtract(const Duration(days: 1))) return 'Yesterday';
    return DateFormat('EEE d MMM').format(d);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: Db.i, builder: (_, __) {
    final list = Db.i.all(Db.i.sales).where(_match).toList()..sort((a, b) => b['ts'].compareTo(a['ts']));
    final rows = <Object>[]; // _Day headers and sale maps
    final totals = <String, double>{};
    for (final s in list) {
      final l = _dayLabel(DateTime.parse(s['ts']));
      if (s['status'] == 'paid') totals[l] = (totals[l] ?? 0) + (s['total'] as num);
    }
    String? last;
    for (final s in list) {
      final l = _dayLabel(DateTime.parse(s['ts']));
      if (l != last) { rows.add(_Day(l, totals[l] ?? 0)); last = l; }
      rows.add(s);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Sales')),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: TextField(onChanged: (v) => setState(() => q = v.trim()),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search item or phone number', hintStyle: TextStyle(color: muted)))),
        SizedBox(height: 44, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
          for (var i = 0; i < _filters.length; i++) Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: ChoiceChip(
              label: Text(_filters[i]), selected: filter == i, selectedColor: marigoldTint, onSelected: (_) => setState(() => filter = i))),
        ])),
        Expanded(child: rows.isEmpty
            ? Empty(Icons.receipt_long, q.isEmpty && filter == 0 ? 'No sales yet' : 'No matching sales', q.isEmpty && filter == 0 ? 'Sales you make will be listed here.' : 'Try a different filter or search.')
            : ListView.builder(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), itemCount: rows.length, itemBuilder: (_, i) {
                final r = rows[i];
                if (r is _Day) {
                  return SectionHeader(r.label, small: true, trailing: Text(money.format(r.total), style: figs(14, c: muted)));
                }
                return _row(r as Map);
              })),
      ]));
  });

  Widget _row(Map s) {
    final items = s['items'] as List, cash = s['method'] == 'cash', voided = s['status'] != 'paid' && s['status'] != 'pending' && s['status'] != 'credit';
    final title = items.isEmpty ? 'Sale' : '${items.first['name']}${items.length > 1 ? ' + ${items.length - 1} more' : ''}';
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Panel(padding: EdgeInsets.zero, child: ListTile(
      onTap: () => _detail(s),
      leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: cash ? const Color(0xFFDDF1E8) : marigoldTint, borderRadius: BorderRadius.circular(12)),
          child: Icon(cash ? Icons.payments_outlined : Icons.phone_android, color: ink, size: 20)),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text('${DateFormat('h:mm a').format(DateTime.parse(s['ts']))} · ${s['staff'] ?? ''}', style: const TextStyle(color: muted, fontSize: 13)),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(money.format(s['total']), style: figs(15, c: voided ? muted : null).copyWith(decoration: voided ? TextDecoration.lineThrough : null)),
        const SizedBox(height: 4), _status(s['status']),
      ]))));
  }

  void _detail(Map s) {
    final method = s['method'] == 'cash' ? 'Cash' : s['method'] == 'credit' ? 'Credit (pay later)' : (networkLabel[Network.values.byName(s['network'] ?? 'mtn')] ?? 'Mobile money');
    Widget kv(String k, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [
      Text(k, style: const TextStyle(color: muted)), const Spacer(), Text(v, style: const TextStyle(fontWeight: FontWeight.w600))]));
    showModalBottomSheet(context: context, isScrollControlled: true, showDragHandle: true, builder: (ctx) => SafeArea(child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text(money.format(s['total']), style: figs(28, w: FontWeight.w800))), _status(s['status'])]),
        Text(DateFormat('EEE d MMM y, h:mm a').format(DateTime.parse(s['ts'])), style: const TextStyle(color: muted)),
        const SizedBox(height: 16),
        Panel(child: Column(children: [
          for (final it in s['items']) Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
            Expanded(child: Text('${it['qty']} x ${it['name']}')), Text(money.format(it['price'] * it['qty']), style: figs(14, w: FontWeight.w600))])),
        ])),
        const SizedBox(height: 12),
        kv('Paid with', method),
        if (s['phone'] != null && s['phone'].toString().isNotEmpty) kv('Customer', s['phone']),
        kv('Served by', '${s['staff'] ?? '-'}'),
        if (s['status'] == 'refunded') kv('Refunded by', '${s['refundedBy'] ?? '-'}'),
        const SizedBox(height: 16),
        FilledButton.icon(icon: const Icon(Icons.receipt), label: const Text('Receipt: print or send'),
            onPressed: () { Navigator.pop(ctx); showReceipt(context, s, title: 'Receipt'); }),
        if (Db.i.isAdmin && s['status'] == 'paid') TextButton(style: TextButton.styleFrom(foregroundColor: bad),
            onPressed: () => showDialog(context: ctx, builder: (c) => AlertDialog(
              title: const Text('Refund this sale?'),
              content: Text('${money.format(s['total'])} will be removed from your sales and the items put back in stock. Give the customer their money separately.'),
              actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Go back')),
                FilledButton(style: FilledButton.styleFrom(backgroundColor: bad), onPressed: () async {
                  await Db.i.refundSale(s['id']);
                  if (c.mounted) Navigator.pop(c);
                  if (ctx.mounted) Navigator.pop(ctx);
                }, child: const Text('Refund'))])),
            child: const Text('Refund sale')),
      ]))));
  }
}
