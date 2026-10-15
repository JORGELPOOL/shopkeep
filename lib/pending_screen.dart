import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'data.dart';
import 'momo.dart';
import 'ui.dart';

class PendingScreen extends StatelessWidget {
  const PendingScreen({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: Db.i, builder: (_, __) {
    final list = Db.i.pending();
    return Scaffold(
      appBar: AppBar(title: const Text('Waiting for payment'), actions: [
        IconButton(icon: const Icon(Icons.refresh), tooltip: 'Check now', onPressed: () async { await Db.i.checkPending(); if (context.mounted) snack(context, 'Checked.'); })]),
      body: list.isEmpty ? const Empty(Icons.check_circle_outline, 'All settled', 'No payments are waiting. New mobile money sales show up here until paid.')
        : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
            const Padding(padding: EdgeInsets.fromLTRB(4, 0, 4, 12), child: Text('We check automatically every few seconds. You can also tap refresh.', style: TextStyle(color: muted))),
            for (final s in list) Padding(padding: const EdgeInsets.only(bottom: 12), child: _card(context, s)),
          ]));
  });

  Widget _card(BuildContext context, Map s) {
    final unsent = s['ref'] == null;
    final items = (s['items'] as List).fold<int>(0, (a, it) => a + (it['qty'] as int));
    final net = networkLabel[Network.values.byName(s['network'] ?? 'mtn')];
    return Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(money.format(s['total']), style: figs(24, w: FontWeight.w800))),
        unsent ? const Pill('Request not sent', bg: badTint, fg: bad) : const Pill('Waiting for customer'),
      ]),
      const SizedBox(height: 6),
      Text('$net · ${s['phone']}', style: figs(14, w: FontWeight.w500, c: muted)),
      Text('$items ${items == 1 ? 'item' : 'items'} · ${DateFormat('d MMM, h:mm a').format(DateTime.parse(s['ts']))}', style: const TextStyle(color: muted, fontSize: 13)),
      const SizedBox(height: 14),
      if (unsent) ...[FilledButton(onPressed: () async {
        final ok = await Db.i.resend(s);
        if (context.mounted) snack(context, ok ? 'Request sent. Ask the customer to approve.' : 'Still offline. Try again with signal.');
      }, child: const Text('Send request')), const SizedBox(height: 8)],
      if (Db.i.isAdmin) OutlinedButton(onPressed: () => _confirmCash(context, s), child: const Text('Customer paid cash')), // the server only lets the admin override
      Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: () async {
            if (s['ref'] != null && await Momo.status(s['ref']) == 'paid') { // never cancel money that has arrived
              await Db.i.settle(s['id']);
              if (context.mounted) snack(context, 'The customer already paid. Marked as paid instead.');
              return;
            }
            await Db.i.cancelSale(s['id'], 'cancelled');
          },
          style: TextButton.styleFrom(foregroundColor: bad), child: const Text('Cancel sale'))),
    ]));
  }

  // Manual override: the only way to settle without a gateway reply, so it asks first.
  void _confirmCash(BuildContext context, Map s) => showDialog(context: context, builder: (c) => AlertDialog(
    title: const Text('Customer paid in cash?'),
    content: Text('Mark ${money.format(s['total'])} as paid. If a mobile money prompt is still open, it could be paid twice.'),
    actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Go back')),
      FilledButton(onPressed: () { Db.i.settle(s['id']); Navigator.pop(c); }, child: const Text('Mark as paid'))]));
}
