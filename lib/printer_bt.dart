import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'data.dart';
import 'ui.dart';

const _w = 32; // characters per line on a 58mm thermal printer

List<int> _ascii(String s) => s.runes.map((r) => r < 128 ? r : 63).toList(); // printers choke on symbols like ₵

/// Plain ESC/POS bytes: init, centred bold shop name, item rows, total, feed.
List<int> escpos(Map sale) {
  final b = <int>[0x1B, 0x40];
  void line(String s) { b..addAll(_ascii(s))..add(0x0A); }
  void row(String l, String r) { final gap = _w - r.length; line((l.length > gap - 1 ? l.substring(0, gap - 1) : l.padRight(gap)) + r); }
  void align(int a) => b.addAll([0x1B, 0x61, a]);
  void bold(bool on) => b.addAll([0x1B, 0x45, on ? 1 : 0]);
  final id = sale['id'].toString();
  align(1); bold(true); line(Db.i.meta.get('shop', defaultValue: 'Shop')); bold(false);
  line('Receipt #${id.substring(id.length - 5).toUpperCase()}');
  line(sale['ts'].toString().substring(0, 16).replaceAll('T', ' '));
  align(0); line('-' * _w);
  for (final it in sale['items']) { row('${it['qty']} x ${it['name']}', ((it['price'] as num) * (it['qty'] as num)).toStringAsFixed(2)); }
  line('-' * _w);
  bold(true); row('TOTAL GHS', (sale['total'] as num).toStringAsFixed(2)); bold(false);
  line(sale['method'] == 'credit' ? 'ON CREDIT - to pay later' : 'Paid by ${sale['method'] == 'cash' ? 'cash' : 'mobile money'}');
  align(1); line('Thank you!'); b.addAll([0x0A, 0x0A, 0x0A]);
  return b;
}

Future<String?> _choose(BuildContext context) async {
  final list = await PrintBluetoothThermal.pairedBluetooths;
  if (!context.mounted) return null;
  return showDialog<String>(context: context, builder: (c) => SimpleDialog(title: const Text('Choose your printer'), children: [
    if (list.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text("No paired printers. Pair it in your phone's Bluetooth settings first.")),
    for (final p in list) SimpleDialogOption(onPressed: () => Navigator.pop(c, p.macAdress), child: Text(p.name, style: const TextStyle(fontSize: 16))),
  ]));
}

Future<void> printReceipt(BuildContext context, Map sale) async {
  try {
    if (!await PrintBluetoothThermal.bluetoothEnabled) { if (context.mounted) snack(context, 'Turn Bluetooth on first.'); return; }
    var mac = Db.i.meta.get('printerMac') as String?;
    if (mac == null) {
      if (!context.mounted) return;
      mac = await _choose(context);
      if (mac == null) return;
      await Db.i.meta.put('printerMac', mac);
    }
    if (!await PrintBluetoothThermal.connectionStatus && !await PrintBluetoothThermal.connect(macPrinterAddress: mac)) {
      await Db.i.meta.delete('printerMac'); // forget it so the next tap offers the list again
      if (context.mounted) snack(context, 'Could not connect. Is the printer on and paired?');
      return;
    }
    await PrintBluetoothThermal.writeBytes(escpos(sale));
  } catch (_) {
    if (context.mounted) snack(context, 'Could not print. Check the printer and try again.');
  }
}
