import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' show DateFormat;
import 'package:url_launcher/url_launcher.dart';
import 'data.dart';
import 'ui.dart';

/// Creates a 15-minute download link for a CSV the accountant can open in Excel or Google Sheets.
class ExportScreen extends StatefulWidget { const ExportScreen({super.key}); @override State<ExportScreen> createState() => _ExportState(); }

class _ExportState extends State<ExportScreen> {
  int range = 0; // 0 this month, 1 last month, 2 last 7 days, 3 custom
  DateTimeRange? custom;
  String kind = 'sales';
  bool busy = false;
  String? link;
  static const _ranges = ['This month', 'Last month', 'Last 7 days', 'Last 6 months', 'Pick dates'];

  (DateTime, DateTime) _span() {
    final n = DateTime.now(), t = DateTime(n.year, n.month, n.day);
    switch (range) {
      case 0: return (DateTime(n.year, n.month), t);
      case 1: return (DateTime(n.year, n.month - 1), DateTime(n.year, n.month, 0)); // day 0 = last day of previous month
      case 2: return (t.subtract(const Duration(days: 6)), t);
      case 3: return (DateTime(n.year, n.month - 5), t);
      default: final c = custom ?? DateTimeRange(start: t, end: t); return (c.start, c.end);
    }
  }

  Future<void> _pick() async {
    final n = DateTime.now();
    final r = await showDateRangePicker(context: context, firstDate: DateTime(n.year - 3), lastDate: n, initialDateRange: custom);
    if (r != null) setState(() { custom = r; range = 4; link = null; });
  }

  Future<void> _make() async {
    setState(() { busy = true; link = null; });
    if (apiBase.contains('example.com')) { // still the placeholder address
      if (mounted) { setState(() => busy = false); snack(context, 'The app is not connected to a server yet. Set apiBase in lib/data.dart.'); }
      return;
    }
    await Db.i.sync(); // the file is built from what the server has, so send everything first
    final waiting = Db.i.queue.values.where((e) => e['box'] != 'notify').length;
    if (waiting > 0) {
      if (mounted) { setState(() => busy = false); snack(context, '${waiting == 1 ? '1 change has' : '$waiting changes have'} not reached the server yet. Check the connection and try again.'); }
      return;
    }
    final (a, b) = _span();
    final f = DateFormat('yyyy-MM-dd');
    try {
      final r = await http.post(Uri.parse('$apiBase/export/link'), headers: apiHeaders,
          body: jsonEncode({'type': kind, 'from': f.format(a), 'to': f.format(b)})).timeout(const Duration(seconds: 12));
      if (r.statusCode == 200) { link = jsonDecode(r.body)['url']; }
      else if (mounted) { snack(context, r.statusCode == 403 ? 'Only the administrator can export.' : 'Could not create the file. Try again.'); }
    } catch (_) { if (mounted) snack(context, "Can't reach the server. Check your signal."); }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final (a, b) = _span();
    final d = DateFormat('d MMM y');
    return Scaffold(appBar: AppBar(title: const Text('Export for accountant')), body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
      const Padding(padding: EdgeInsets.fromLTRB(4, 0, 4, 16), child: Text('Make a spreadsheet file (CSV) your accountant can open in Excel or Google Sheets.', style: TextStyle(color: muted))),
      const Text('What to export', style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      SegmentedButton<String>(segments: const [ButtonSegment(value: 'sales', label: Text('Sales')), ButtonSegment(value: 'expenses', label: Text('Expenses')), ButtonSegment(value: 'pnl', label: Text('Profit & loss'))],
          selected: {kind}, onSelectionChanged: (s) => setState(() { kind = s.first; link = null; })),
      const SizedBox(height: 20),
      const Text('Period', style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [for (var i = 0; i < _ranges.length; i++) ChoiceChip(label: Text(_ranges[i]), selected: range == i, selectedColor: marigoldTint,
          onSelected: (_) { if (i == 4) { _pick(); } else { setState(() { range = i; link = null; }); } })]),
      Padding(padding: const EdgeInsets.only(top: 8), child: Text('${d.format(a)} to ${d.format(b)}', style: figs(14, w: FontWeight.w500, c: muted))),
      const SizedBox(height: 20),
      Panel(child: Text(const {
        'sales': 'One row per item sold, with date, payment method, who served, price, cost and profit. Paid, credit and refunded sales. Refunded lines show 0.00, so the revenue column adds up correctly.',
        'expenses': 'One row per expense with date, description and amount.',
        'pnl': 'A month-by-month statement: sales (cash, mobile money, credit), cost of goods, gross profit, each expense, and net profit. Also shows refunds, debt payments received and what customers still owe. Whole months are used.',
      }[kind]!, style: const TextStyle(color: muted))),
      const SizedBox(height: 16),
      FilledButton(onPressed: busy ? null : _make, child: Text(busy ? 'Preparing...' : 'Create download link')),
      if (link != null) ...[
        const SizedBox(height: 16),
        Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [Icon(Icons.check_circle, color: good), SizedBox(width: 8), Text('Your file is ready', style: TextStyle(fontWeight: FontWeight.w800))]),
          const SizedBox(height: 4),
          const Text('The link works for 15 minutes. Anyone with it can download this file, so share it only with your accountant.', style: TextStyle(color: muted, fontSize: 13)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: FilledButton.icon(onPressed: () => launchUrl(Uri.parse(link!), mode: LaunchMode.externalApplication), icon: const Icon(Icons.download), label: const Text('Download'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: () { Clipboard.setData(ClipboardData(text: link!)); snack(context, 'Link copied. Paste it into WhatsApp or email.'); },
                icon: const Icon(Icons.copy), label: const Text('Copy link'))),
          ]),
        ])),
      ],
    ]));
  }
}
