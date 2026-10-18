import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'data.dart';
import 'momo.dart';
import 'receipt.dart';
import 'ui.dart';
import 'customer_screen.dart';
import 'export_screen.dart';
import 'sales_screen.dart';
import 'scan_screen.dart';
import 'reports_screen.dart';
import 'staff_screen.dart';
import 'pending_screen.dart';

// ---------- Setup (first run = administrator) & Login ----------
class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final shop = TextEditingController(),
        name = TextEditingController(),
        phone = TextEditingController(),
        pin = TextEditingController();
    return AuthShell(
        title: 'Set up your shop',
        subtitle: 'You will be the administrator. Add staff later.',
        children: [
          field(shop, 'Shop name'),
          field(name, 'Your name'),
          field(phone, 'Phone number', num: true),
          field(pin, 'Choose a PIN (6 digits or more)',
              num: true, secret: true),
          FilledButton(
              onPressed: () {
                if ([shop, name, phone, pin]
                        .any((c) => c.text.trim().isEmpty) ||
                    pin.text.length < 6) {
                  return snack(context,
                      'Fill every field. PIN needs at least 6 digits.');
                }
                Db.i.createAdmin(shop.text.trim(), name.text.trim(),
                    phone.text.trim(), pin.text);
              },
              child: const Text('Create shop')),
          TextButton(
              onPressed: () => Db.i.join(true),
              child: const Text('Already have a shop? Log in')),
        ]);
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginState();
}

class _LoginState extends State<LoginScreen> {
  final phone = TextEditingController(), pin = TextEditingController();
  bool busy = false;
  Future<void> _go() async {
    setState(() => busy = true);
    final err = await Db.i.signIn(phone.text.trim(), pin.text);
    if (mounted) {
      setState(() => busy = false);
      if (err != null) snack(context, err);
    }
  }

  @override
  Widget build(BuildContext context) => AuthShell(
          title: Db.i.meta.get('shop', defaultValue: 'Welcome back'),
          subtitle: Db.i.needsSetup
              ? 'New phone? Log in once with a signal to load your shop.'
              : 'Log in to start selling.',
          children: [
            field(phone, 'Phone number', num: true),
            field(pin, 'PIN', num: true, secret: true),
            FilledButton(
                onPressed: busy ? null : _go,
                child: Text(busy ? 'Logging in...' : 'Log in')),
            if (Db.i.needsSetup)
              TextButton(
                  onPressed: () => Db.i.join(false),
                  child: const Text('Set up a new shop instead')),
          ]);
}

// ---------- Shell ----------
class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final admin = Db.i.isAdmin;
    final pages = <(String, IconData, Widget)>[
      ('Today', Icons.insights, const Dashboard()),
      ('Sell', Icons.point_of_sale, const PosScreen()),
      ('Stock', Icons.inventory_2, const InventoryScreen()),
      ('Customers', Icons.people, const CustomersScreen()),
      if (admin) ('Manage', Icons.settings, const ManageScreen()),
    ];
    return ListenableBuilder(
        listenable: Db.i,
        builder: (_, __) => Scaffold(
              appBar: AppBar(
                  toolbarHeight: 68,
                  titleSpacing: 16,
                  title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(Db.i.meta.get('shop', defaultValue: 'ShopKeep'),
                            style: const TextStyle(
                                fontSize: 13,
                                color: muted,
                                fontWeight: FontWeight.w600)),
                        Text(pages[tab].$1)
                      ]),
                  actions: [
                    if (Db.i.queue.isNotEmpty)
                      Pill('${Db.i.queue.length} to sync'),
                    IconButton(
                        icon: const Icon(Icons.history),
                        tooltip: 'Sales history',
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const SalesHistoryScreen()))),
                    IconButton(
                        icon: const Icon(Icons.logout),
                        tooltip: 'Log out',
                        onPressed: Db.i.logout),
                    const SizedBox(width: 4)
                  ]),
              body: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child:
                      KeyedSubtree(key: ValueKey(tab), child: pages[tab].$3)),
              bottomNavigationBar: NavigationBar(
                  selectedIndex: tab,
                  onDestinationSelected: (i) => setState(() => tab = i),
                  destinations: [
                    for (final p in pages)
                      NavigationDestination(icon: Icon(p.$2), label: p.$1)
                  ]),
            ));
  }
}

// ---------- Dashboard ----------
class Dashboard extends StatelessWidget {
  const Dashboard({super.key});
  @override
  Widget build(BuildContext context) {
    final admin = Db.i.isAdmin, t = Db.i.today(), low = Db.i.lowStock();
    final n = DateTime.now(), d0 = DateTime(n.year, n.month, n.day);
    final trend = <double>[
      for (var i = 6; i >= 0; i--)
        () {
          final d = d0.subtract(Duration(days: i)),
              s = Db.i.summary(d, d.add(const Duration(days: 1)));
          return admin ? s['profit']! : s['revenue']!;
        }()
    ];
    final hero = admin ? t['profit']! : t['revenue']!;
    Widget stat(String l, double v) => Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l,
              style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 13)),
          CountUp(v, style: figs(17, c: Colors.white))
        ]));
    return ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: ink, borderRadius: BorderRadius.circular(24)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(admin ? "Today's profit" : "Today's sales",
                        style: const TextStyle(
                            color: Color(0xB3FFFFFF),
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    CountUp(hero,
                        style: figs(40,
                            w: FontWeight.w800,
                            c: hero < 0
                                ? const Color(0xFFFFB4A8)
                                : Colors.white)),
                    const SizedBox(height: 12),
                    SizedBox(height: 48, child: Spark(trend, color: sun)),
                    const Text('Last 7 days',
                        style:
                            TextStyle(color: Color(0x80FFFFFF), fontSize: 12)),
                    if (admin) ...[
                      const SizedBox(height: 16),
                      Row(children: [
                        stat('Sales', t['revenue']!),
                        stat('Costs', t['cogs']! + t['expenses']!)
                      ])
                    ],
                  ])),
          if (Db.i.meta.get('syncProblem') != null)
            Notice(Icons.error_outline, badTint, Db.i.meta.get('syncProblem'),
                trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: Db.i.clearProblem)),
          if (Db.i.pending().isNotEmpty)
            Notice(Icons.hourglass_top, marigoldTint,
                'Waiting for payment (${Db.i.pending().length})',
                sub: money.format(Db.i.pendingTotal()),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const PendingScreen()))),
          if (Db.i.totalOwed() > 0.005)
            Notice(Icons.account_balance_wallet_outlined, marigoldTint,
                'Customers owe you ${money.format(Db.i.totalOwed())}',
                sub:
                    '${Db.i.debts().values.where((v) => v > 0.005).length} customers',
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ListenableBuilder(
                            listenable: Db.i,
                            builder: (_, __) => Scaffold(
                                appBar: AppBar(title: const Text('Customers')),
                                body: const CustomersScreen()))))),
          const SectionHeader('Running low'),
          Panel(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: low.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Everything is well stocked.',
                          style: TextStyle(color: muted)))
                  : Column(children: [
                      for (final p in low)
                        ListTile(
                            dense: true,
                            leading: Avatar(p['name'], size: 36),
                            title: Text(p['name'],
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            trailing: Pill(
                                Db.i.stock(p['id']) <= 0
                                    ? 'Out of stock'
                                    : '${Db.i.stock(p['id'])} left',
                                bg: badTint,
                                fg: bad))
                    ])),
        ]);
  }
}

// ---------- POS ----------
class PosScreen extends StatefulWidget {
  const PosScreen({super.key});
  @override
  State<PosScreen> createState() => _PosState();
}

class _PosState extends State<PosScreen> {
  final cart = <String, int>{};
  String q = '';
  final qc = TextEditingController();
  double get total => cart.entries
      .fold(0, (s, e) => s + Db.i.products.get(e.key)['price'] * e.value);
  List<Map> _items() => cart.entries.map((e) {
        final p = Db.i.products.get(e.key);
        return {
          'pid': e.key,
          'name': p['name'],
          'qty': e.value,
          'price': p['price'],
          'cost': p['cost']
        };
      }).toList();

  Future<void> _pay() async {
    String method = 'cash';
    String? custId;
    Network net = Network.mtn;
    final phone = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (c) => StatefulBuilder(
            builder: (c, set) => Padding(
                padding: EdgeInsets.fromLTRB(
                    16, 16, 16, MediaQuery.of(c).viewInsets.bottom + 16),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(money.format(total),
                      style: Theme.of(c).textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(segments: const [
                    ButtonSegment(value: 'cash', label: Text('Cash')),
                    ButtonSegment(value: 'momo', label: Text('Mobile money')),
                    ButtonSegment(value: 'credit', label: Text('Pay later'))
                  ], selected: {
                    method
                  }, onSelectionChanged: (s) => set(() => method = s.first)),
                  if (method == 'momo') ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<Network>(
                        initialValue: net,
                        items: [
                          for (final n in Network.values)
                            DropdownMenuItem(
                                value: n, child: Text(networkLabel[n]!))
                        ],
                        onChanged: (v) => set(() => net = v!)),
                    const SizedBox(height: 8),
                    field(phone, 'Customer wallet number', num: true),
                  ],
                  if (method == 'credit') ...[
                    const SizedBox(height: 12),
                    if (Db.i.customers.isEmpty)
                      const Text('Add the customer in Customers first.',
                          style: TextStyle(color: muted))
                    else
                      DropdownButtonFormField<String>(
                          initialValue: custId,
                          hint: const Text('Who is buying on credit?'),
                          items: [
                            for (final cu in Db.i.all(Db.i.customers))
                              DropdownMenuItem(
                                  value: cu['id'] as String,
                                  child: Text(cu['name']))
                          ],
                          onChanged: (v) => set(() => custId = v)),
                    const SizedBox(height: 8),
                  ],
                  FilledButton(
                      onPressed: method == 'credit' && custId == null
                          ? null
                          : () => Navigator.pop(c, true),
                      child: Text(method == 'cash'
                          ? 'Record cash sale'
                          : method == 'credit'
                              ? 'Record credit sale'
                              : 'Send payment request')),
                ]))));
    if (ok != true || !mounted) return;
    if (method == 'cash') {
      final sale = await Db.i.recordSale(_items(), 'cash');
      setState(cart.clear);
      if (mounted) await showReceipt(context, sale);
      return;
    }
    if (method == 'credit') {
      final cu = Map.from(Db.i.customers.get(custId));
      final sale = await Db.i.recordSale(_items(), 'credit',
          phone: cu['phone'], status: 'credit', customerId: custId);
      setState(cart.clear);
      if (!mounted) return;
      await showReceipt(context, sale, phone: cu['phone']);
      return;
    }
    final ref = await Momo.request(net, phone.text.trim(), total);

    if (!mounted) return;

    if (ref == null) {
      // Offline or gateway down: keep the sale and mark it unpaid.
      await Db.i.recordSale(
        _items(),
        'momo',
        phone: phone.text.trim(),
        status: 'pending',
        network: net.name,
      );

      if (!mounted) return;
      snack(
        context,
        'No connection. Saved as unpaid. Resend it from Today when you are online.',
      );
    } else {
      await Db.i.recordSale(
        _items(),
        'momo',
        phone: phone.text.trim(),
        status: 'pending',
        ref: ref,
        network: net.name,
      );

      if (!mounted) return;
      Db.i.checkPending();
      snack(context, 'Ask the customer to approve the prompt on their phone.');

      Momo.notify(
        phone.text.trim(),
        'Payment request of ${money.format(total)} from ${Db.i.meta.get('shop')}. Approve on your phone.',
      );
    }

    if (!mounted) return;
    setState(cart.clear);
  }

  /// Works for the camera, and for USB / Bluetooth scanners (they type the code and press Enter).
  void _addByCode(String code, {bool warn = false}) {
    code = code.trim();
    if (code.isEmpty) return;
    final hit =
        Db.i.all(Db.i.products).where((p) => p['barcode'] == code).toList();
    if (hit.isEmpty) {
      if (warn) snack(context, 'No item with that barcode. Add it in Stock.');
      return;
    }
    final id = hit.first['id'];
    if (Db.i.stock(id) <= (cart[id] ?? 0)) {
      return snack(context, '${hit.first['name']} is out of stock.');
    }
    setState(() {
      cart[id] = (cart[id] ?? 0) + 1;
      qc.clear();
      q = '';
    });
  }

  Future<void> _scan() async {
    final code = await Navigator.push<String>(
        context, MaterialPageRoute(builder: (_) => const ScanScreen()));
    if (code != null) _addByCode(code, warn: true);
  }

  Widget _tile(Map p) {
    final id = p['id'],
        inCart = cart[id] ?? 0,
        stock = Db.i.stock(id),
        on = inCart > 0;
    return InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: stock <= inCart
            ? null
            : () => setState(() => cart[id] = inCart + 1),
        onLongPress: () => setState(() => cart.remove(id)),
        child: Ink(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: on ? marigoldTint : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: on ? sun : line, width: on ? 2 : 1)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Avatar(p['name'], size: 34),
                const Spacer(),
                AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (w, a) =>
                        ScaleTransition(scale: a, child: w),
                    child: on
                        ? CircleAvatar(
                            key: ValueKey(inCart),
                            radius: 13,
                            backgroundColor: ink,
                            child: Text('$inCart',
                                style: figs(12, c: Colors.white)))
                        : const SizedBox(
                            key: ValueKey(0), width: 26, height: 26))
              ]),
              const Spacer(),
              Text(p['name'],
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 2),
              Row(children: [
                Text(money.format(p['price']),
                    style: figs(13, w: FontWeight.w500, c: muted)),
                const Spacer(),
                Text(stock <= 0 ? 'Out' : '$stock left',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: stock <= (p['reorder'] ?? 5) ? bad : muted))
              ]),
            ])));
  }

  @override
  Widget build(BuildContext context) {
    final items = Db.i
        .all(Db.i.products)
        .where((p) =>
            p['name'].toString().toLowerCase().contains(q.toLowerCase()) ||
            (p['barcode'] ?? '').toString().contains(q))
        .toList();
    final count = cart.values.fold<int>(0, (a, b) => a + b);
    return Column(children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
              controller: qc,
              onChanged: (v) => setState(() => q = v),
              onSubmitted: (v) => _addByCode(v),
              decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Find or scan an item',
                  hintStyle: const TextStyle(color: muted),
                  suffixIcon: IconButton(
                      icon: const Icon(Icons.qr_code_scanner),
                      tooltip: 'Scan barcode',
                      onPressed: _scan)))),
      const Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Tap to add. Hold to remove.',
                  style: TextStyle(fontSize: 12, color: muted)))),
      Expanded(
          child: items.isEmpty
              ? const Empty(Icons.inventory_2_outlined, 'No items yet',
                  'Add your first item in Stock to start selling.')
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  itemCount: items.length,
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 190,
                      mainAxisExtent: 124,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10),
                  itemBuilder: (_, i) => _tile(items[i]))),
      if (cart.isNotEmpty)
        SafeArea(
            top: false,
            child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Material(
                    color: ink,
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: _pay,
                        child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 16),
                            child: Row(children: [
                              Text('$count ${count == 1 ? 'item' : 'items'}',
                                  style: const TextStyle(
                                      color: Color(0xB3FFFFFF),
                                      fontWeight: FontWeight.w600)),
                              const Spacer(),
                              TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0, end: total),
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOut,
                                  builder: (_, v, __) => Text(
                                      'Charge ${money.format(v)}',
                                      style: figs(18,
                                          w: FontWeight.w800, c: sun))),
                              const SizedBox(width: 6),
                              const Icon(Icons.arrow_forward,
                                  color: sun, size: 20),
                            ])))))),
    ]);
  }
}

// ---------- Inventory ----------
class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final items = Db.i.all(Db.i.products);
    return Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: Db.i.isAdmin
            ? FloatingActionButton.extended(
                onPressed: () => _edit(context),
                backgroundColor: sun,
                foregroundColor: ink,
                icon: const Icon(Icons.add),
                label: const Text('Add item'))
            : null,
        body: items.isEmpty
            ? const Empty(Icons.inventory_2_outlined, 'No items yet',
                'Add your first item to start selling.')
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                children: [
                    for (final p in items)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Panel(
                              padding: EdgeInsets.zero,
                              child: ListTile(
                                  leading: Avatar(p['name']),
                                  title: Text(p['name'],
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700)),
                                  subtitle: Text(
                                      'Cost ${money.format(p['cost'])} · Price ${money.format(p['price'])}',
                                      style: figs(12,
                                          w: FontWeight.w500, c: muted)),
                                  trailing: Db.i.stock(p['id']) <=
                                          (p['reorder'] ?? 5)
                                      ? Pill('${Db.i.stock(p['id'])} left',
                                          bg: badTint, fg: bad)
                                      : Pill('${Db.i.stock(p['id'])} in stock',
                                          bg: const Color(0xFFDDF1E8),
                                          fg: good),
                                  onTap: Db.i.isAdmin
                                      ? () => _edit(context, p)
                                      : null))),
                  ]));
  }

  void _edit(BuildContext context, [Map? p]) {
    final bc = TextEditingController(text: p?['barcode']),
        n = TextEditingController(text: p?['name']),
        c = TextEditingController(text: '${p?['cost'] ?? ''}'),
        pr = TextEditingController(text: '${p?['price'] ?? ''}'),
        s = TextEditingController(
            text: '${p == null ? '' : Db.i.stock(p['id'])}');
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => Padding(
            padding: EdgeInsets.fromLTRB(
                16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              field(n, 'Item name'),
              Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                      controller: bc,
                      decoration: InputDecoration(
                          labelText: 'Barcode (optional)',
                          suffixIcon: IconButton(
                              icon: const Icon(Icons.qr_code_scanner),
                              onPressed: () async {
                                final r = await Navigator.push<String>(
                                    ctx,
                                    MaterialPageRoute(
                                        builder: (_) => const ScanScreen()));
                                if (r != null) bc.text = r;
                              })))),
              field(c, 'Cost price', num: true),
              field(pr, 'Selling price', num: true),
              field(s, 'Quantity in stock', num: true),
              FilledButton(
                  onPressed: () async {
                    final id = p?['id'] ?? newId();
                    await Db.i.put(Db.i.products, {
                      ...?p,
                      'id': id,
                      'barcode': bc.text.trim(),
                      'name': n.text.trim(),
                      'cost': double.tryParse(c.text) ?? 0,
                      'price': double.tryParse(pr.text) ?? 0
                    });
                    await Db.i.move(
                        id,
                        (int.tryParse(s.text) ?? 0) - Db.i.stock(id),
                        p == null ? 'opening stock' : 'stock count');
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                  },
                  child: const Text('Save item')),
            ])));
  }
}

// ---------- Customers ----------
class CustomersScreen extends StatelessWidget {
  const CustomersScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final debts = Db.i.debts();
    final list = Db.i.all(Db.i.customers)
      ..sort((a, b) => (debts[b['id']] ?? 0).compareTo(debts[a['id']] ?? 0));
    return Scaffold(
        floatingActionButton: FloatingActionButton.extended(
            icon: const Icon(Icons.person_add),
            label: const Text('Add customer'),
            onPressed: () {
              final n = TextEditingController(), ph = TextEditingController();
              showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (ctx) => Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16,
                          MediaQuery.of(ctx).viewInsets.bottom + 16),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        field(n, 'Name'),
                        field(ph, 'Phone number', num: true),
                        FilledButton(
                            onPressed: () {
                              Db.i.put(Db.i.customers, {
                                'name': n.text.trim(),
                                'phone': ph.text.trim()
                              });
                              Navigator.pop(ctx);
                            },
                            child: const Text('Save customer'))
                      ])));
            }),
        body: list.isEmpty
            ? const Empty(Icons.people_outline, 'No customers yet',
                'Save numbers to send receipts and reminders.')
            : ListView(children: [
                for (final c in list)
                  ListTile(
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => CustomerScreen(c['id']))),
                      leading: Avatar(c['name']),
                      title: Text(c['name'],
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(c['phone']),
                      trailing: (debts[c['id']] ?? 0) > 0.005
                          ? Pill('Owes ${money.format(debts[c['id']])}',
                              bg: badTint, fg: bad)
                          : const Icon(Icons.chevron_right)),
              ]));
  }
}

// ---------- Expenses (admin only) ----------
class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final list = Db.i.all(Db.i.expenses)
      ..sort((a, b) => b['ts'].compareTo(a['ts']));
    return Scaffold(
        floatingActionButton: FloatingActionButton.extended(
            icon: const Icon(Icons.add),
            label: const Text('Add expense'),
            onPressed: () {
              final d = TextEditingController(), a = TextEditingController();
              showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (ctx) => Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16,
                          MediaQuery.of(ctx).viewInsets.bottom + 16),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        field(d, 'What was it for?'),
                        field(a, 'Amount', num: true),
                        FilledButton(
                            onPressed: () {
                              Db.i.put(Db.i.expenses, {
                                'desc': d.text.trim(),
                                'amount': double.tryParse(a.text) ?? 0,
                                'ts': DateTime.now().toIso8601String()
                              });
                              Navigator.pop(ctx);
                            },
                            child: const Text('Save expense'))
                      ])));
            }),
        body: list.isEmpty
            ? const Empty(Icons.receipt_long, 'No expenses yet',
                'Record rent, transport and other costs to see true profit.')
            : ListView(children: [
                for (final e in list)
                  ListTile(
                      title: Text(e['desc']),
                      subtitle: Text(DateFormat.MMMd()
                          .add_jm()
                          .format(DateTime.parse(e['ts']))),
                      trailing: Text(money.format(e['amount']))),
              ]));
  }
}

// ---------- Manage (admin) ----------
class ManageScreen extends StatelessWidget {
  const ManageScreen({super.key});
  @override
  Widget build(BuildContext context) {
    Widget row(IconData i, String t, Widget page) => ListTile(
        leading: Icon(i),
        title: Text(t),
        trailing: const Icon(Icons.chevron_right),
        onTap: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => page)));
    return ListView(children: [
      row(Icons.bar_chart, 'Reports', const ReportsScreen()),
      row(
          Icons.receipt_long,
          'Expenses',
          ListenableBuilder(
              listenable: Db.i,
              builder: (_, __) => Scaffold(
                  appBar: AppBar(title: const Text('Expenses')),
                  body: const ExpensesScreen()))),
      row(Icons.badge, 'Staff', const StaffScreen()),
      row(Icons.file_download_outlined, 'Export for accountant',
          const ExportScreen()),
    ]);
  }
}
