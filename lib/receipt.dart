import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:url_launcher/url_launcher.dart';
import 'data.dart';
import 'printer_stub.dart' if (dart.library.io) 'printer_bt.dart'; // web gets a stub; Android gets Bluetooth

/// Plain-text receipt, short enough for one or two SMS parts.
String receiptText(Map sale) {
  final m = NumberFormat('#,##0.00');
  final id = sale['id'].toString();
  final b = StringBuffer('${Db.i.meta.get('shop', defaultValue: 'Shop')}\n')
    ..writeln('Receipt #${id.substring(id.length - 5).toUpperCase()}')
    ..writeln('${DateFormat('d MMM y, h:mm a').format(DateTime.parse(sale['ts']))}\n');
  for (final it in sale['items']) { b.writeln('${it['qty']} x ${it['name']}  GH₵${m.format(it['price'] * it['qty'])}'); }
  b..writeln()..writeln('Total GH₵${m.format(sale['total'])}')
   ..writeln(sale['method'] == 'credit' ? 'ON CREDIT - to pay later' : 'Paid by ${sale['method'] == 'cash' ? 'cash' : 'mobile money'}')..write('Thank you!');
  return b.toString();
}

/// Sends through the shop's OWN WhatsApp or SMS app: no backend, no templates, no data cost to the app.
/// (MoMo sales already get an automatic receipt from the backend once paid.)
Future<void> showReceipt(BuildContext context, Map sale, {String? phone, String title = 'Sale recorded'}) {
  final ph = TextEditingController(text: phone ?? sale['phone'] ?? '');
  final text = receiptText(sale);
  return showModalBottomSheet(context: context, isScrollControlled: true, builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
    Future<void> send(bool wa) async {
      final n = ph.text.trim(), p = normPhone(n), body = Uri.encodeComponent(text);
      final ok = await launchUrl(Uri.parse(wa ? 'https://wa.me/$p?text=$body' : 'sms:$n?body=$body'), mode: LaunchMode.externalApplication);
      if (!ok && ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Could not open that app on this phone.')));
    }
    final has = ph.text.trim().length >= 9;
    return Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(ctx).textTheme.titleLarge),
        const SizedBox(height: 8),
        Container(width: double.infinity, padding: const EdgeInsets.all(12), color: Colors.white, child: Text(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 13))),
        const SizedBox(height: 12),
        TextField(controller: ph, keyboardType: TextInputType.phone, onChanged: (_) => set(() {}),
            decoration: const InputDecoration(labelText: 'Customer phone number (optional)', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: FilledButton.icon(onPressed: has ? () => send(true) : null, icon: const Icon(Icons.chat), label: const Text('WhatsApp'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(onPressed: has ? () => send(false) : null, icon: const Icon(Icons.sms), label: const Text('SMS'))),
        ]),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: () => printReceipt(ctx, sale), icon: const Icon(Icons.print), label: const Text('Print')),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
          if (Db.i.meta.get('printerMac') != null) TextButton(onPressed: () async { await Db.i.meta.delete('printerMac'); set(() {}); }, child: const Text('Change printer')),
        ]),
      ]));
  }));
}
