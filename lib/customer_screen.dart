import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'data.dart';
import 'momo.dart';
import 'ui.dart';

/// One customer's account: what they owe, every credit sale and payment, and quick actions.
class CustomerScreen extends StatelessWidget {
  final String id;
  const CustomerScreen(this.id, {super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: Db.i, builder: (_, __) {
    final c = Map.from(Db.i.customers.get(id));
    final owed = Db.i.debts()[id] ?? 0, owes = owed > 0.005;
    final entries = <Map>[
      for (final s in Db.i.sales.values) if (s['status'] == 'credit' && s['customerId'] == id)
        {'ts': s['ts'], 'amount': (s['total'] as num).toDouble(), 'label': 'Credit sale', 'sub': (s['items'] as List).map((it) => '${it['qty']} x ${it['name']}').join(', ')},
      for (final p in Db.i.collections.values) if (p['customerId'] == id)
        {'ts': p['ts'], 'amount': -(p['amount'] as num).toDouble(), 'label': 'Payment received', 'sub': p['method'] == 'cash' ? 'Cash' : 'Mobile money'},
    ]..sort((a, b) => b['ts'].compareTo(a['ts']));
    return Scaffold(appBar: AppBar(title: Text(c['name'])), body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
      Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(24)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(owes ? 'Owes you' : 'All settled', style: const TextStyle(color: Color(0xB3FFFFFF), fontWeight: FontWeight.w600)),
        Text(money.format(owes ? owed : 0), style: figs(38, w: FontWeight.w800, c: owes ? sun : Colors.white)),
        const SizedBox(height: 4), Text(c['phone'] ?? '', style: const TextStyle(color: Color(0xB3FFFFFF))),
      ])),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: FilledButton.icon(onPressed: owes ? () => _pay(context, c, owed) : null, icon: const Icon(Icons.payments_outlined), label: const Text('Record payment'))),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(onPressed: owes ? () {
          Momo.notify(c['phone'], 'Hello ${c['name']}, you owe ${money.format(owed)} at ${Db.i.meta.get('shop')}. Please pay when you can. Thank you.');
          snack(context, 'Reminder will be sent by SMS and WhatsApp.');
        } : null, icon: const Icon(Icons.notifications_none), label: const Text('Remind'))),
      ]),
      const SectionHeader('History'),
      if (entries.isEmpty) const Panel(child: Text('No credit sales or payments yet.', style: TextStyle(color: muted)))
      else Panel(padding: const EdgeInsets.symmetric(vertical: 6), child: Column(children: [for (final e in entries) ListTile(dense: true,
        title: Text(e['label'], style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${DateFormat('d MMM, h:mm a').format(DateTime.parse(e['ts']))} · ${e['sub']}', maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: Text('${e['amount'] < 0 ? '-' : '+'}${money.format((e['amount'] as double).abs())}', style: figs(15, c: e['amount'] < 0 ? good : bad)))])),
    ]));
  });

  void _pay(BuildContext context, Map c, double owed) {
    final amt = TextEditingController(text: owed.toStringAsFixed(2));
    String method = 'cash';
    showModalBottomSheet(context: context, isScrollControlled: true, showDragHandle: true, builder: (ctx) => StatefulBuilder(builder: (ctx, set) => Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Payment from ${c['name']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        Text('Owes ${money.format(owed)}', style: const TextStyle(color: muted)),
        const SizedBox(height: 16),
        field(amt, 'Amount received'),
        SegmentedButton<String>(segments: const [ButtonSegment(value: 'cash', label: Text('Cash')), ButtonSegment(value: 'momo', label: Text('Mobile money'))],
            selected: {method}, onSelectionChanged: (s) => set(() => method = s.first)),
        const SizedBox(height: 4),
        const Text('Mobile money here means you already received it in your wallet.', style: TextStyle(color: muted, fontSize: 12)),
        const SizedBox(height: 12),
        FilledButton(onPressed: () async {
          final v = double.tryParse(amt.text.trim()) ?? 0;
          if (v <= 0) return snack(ctx, 'Enter the amount received.');
          if (v > owed + 0.005) return snack(ctx, 'That is more than they owe (${money.format(owed)}).');
          await Db.i.collect(id, v, method);
          final left = owed - v;
          Momo.notify(c['phone'], 'Received ${money.format(v)} at ${Db.i.meta.get('shop')}. ${left > 0.005 ? 'You still owe ${money.format(left)}.' : 'Your account is settled. Thank you!'}');
          if (ctx.mounted) Navigator.pop(ctx);
        }, child: const Text('Save payment')),
      ]))));
  }
}
