import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'momo.dart';

const apiBase = 'https://shopkeep-production-4de7.up.railway.app';
const appKey = String.fromEnvironment('APP_KEY');
Map<String, String> get apiHeaders => {'Content-Type': 'application/json', 'x-api-key': appKey,
  'x-shop-id': Db.i.meta.get('shopId', defaultValue: ''), 'x-token': Db.i.meta.get('token', defaultValue: '')};

// Salted with the phone number so two people with the same PIN get different hashes.
String hashPin(String pin, String phone) => sha256.convert(utf8.encode('shopkeep:$phone:$pin')).toString();
// One format everywhere (233XXXXXXXXX) so 024..., +23324... and 23324... are the same person.
String normPhone(String p) { final d = p.replaceAll(RegExp(r'\D'), ''); return d.startsWith('233') ? d : '233${d.replaceFirst(RegExp(r'^0'), '')}'; }
String newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

/// Offline-first store. Every write lands locally first, then joins a sync queue.
class Db extends ChangeNotifier {
  static final Db i = Db._();
  Db._();
  late Box products, customers, sales, expenses, users, moves, collections, queue, meta;
  Map? session; // logged-in user

  Future<void> init() async {
    await Hive.initFlutter();
    for (final n in ['products', 'customers', 'sales', 'expenses', 'users', 'moves', 'collections', 'queue', 'meta']) {
      await Hive.openBox(n);
    }
    products = Hive.box('products'); customers = Hive.box('customers');
    sales = Hive.box('sales'); expenses = Hive.box('expenses');
    users = Hive.box('users'); queue = Hive.box('queue'); meta = Hive.box('meta');
    moves = Hive.box('moves'); collections = Hive.box('collections'); _rebuildStock();
    if (meta.get('deviceId') == null) await meta.put('deviceId', newId());
  }

  bool get needsSetup => users.isEmpty;

  Future<void> put(Box b, Map row) async {
    row['id'] ??= newId();
    row['updated'] = DateTime.now().toIso8601String();
    await b.put(row['id'], row);
    await queue.put(newId(), {'box': b.name, 'row': row});
    notifyListeners();
    sync();
  }

  List<Map> all(Box b) => b.values.map((e) => Map.from(e)).toList();

  // ---- Auth (local, PIN-based; admin creates staff) ----
  // ---- Stock: never overwritten. Every change is a "move"; stock = sum of moves. ----
  // Two phones selling at once each add their own rows, so nothing is lost. Move ids can be fixed
  // (one per sale line) so the same move made on two phones is still one row.
  Map<String, int> _stock = {};
  void _rebuildStock() {
    _stock = {};
    for (final m in moves.values) { _stock[m['pid']] = (_stock[m['pid']] ?? 0) + (m['delta'] as num).toInt(); }
  }
  int stock(String pid) => _stock[pid] ?? 0;

  Future<void> move(String pid, int delta, String reason, {String? id}) async {
    if (delta == 0 || (id != null && moves.containsKey(id))) return;
    _stock[pid] = stock(pid) + delta;
    await put(moves, {'id': id, 'pid': pid, 'delta': delta, 'reason': reason, 'ts': DateTime.now().toIso8601String(), 'staff': session?['name']});
  }

  // ---- Auth ----
  Future<void> createAdmin(String shop, String name, String phone, String pin) async {
    final r = Random.secure(), p = normPhone(phone);
    await meta.put('shop', shop);
    await meta.put('shopId', newId());
    await meta.put('token', List.generate(32, (_) => r.nextInt(36).toRadixString(36)).join());
    await put(users, {'name': name, 'phone': p, 'role': 'admin', 'pin': hashPin(pin, p), 'shop': shop});
  }

  bool login(String phone, String pin) {
    final p = normPhone(phone);
    for (final u in users.values) {
      if (u['phone'] == p && u['pin'] == hashPin(pin, p) && u['active'] != false) { session = Map.from(u); notifyListeners(); return true; }
    }
    return false;
  }

  void clearProblem() { meta.delete('syncProblem'); notifyListeners(); }

  void logout() { session = null; notifyListeners(); }
  bool get isAdmin => session?['role'] == 'admin';

  // ---- Joining an existing shop from a new phone ----
  bool joining = false;
  void join(bool v) { joining = v; notifyListeners(); }

  /// Local PIN check first (works offline). If it fails, ask the server and download the shop.
  // ---- PIN lockout on this phone: 5 wrong tries lock that number for 15 minutes (works offline) ----
  int lockedMinutes(String phone) {
    final f = (meta.get('fails') as Map?)?[normPhone(phone)];
    final ms = ((f?['until'] ?? 0) as int) - DateTime.now().millisecondsSinceEpoch;
    return ms > 0 ? (ms / 60000).ceil() : 0;
  }

  Future<void> _wrong(String phone) async {
    final all = Map<String, dynamic>.from(meta.get('fails') ?? {}), p = normPhone(phone);
    final f = Map<String, dynamic>.from(all[p] ?? {'n': 0, 'until': 0});
    f['n'] = (f['n'] as int) + 1;
    if (f['n'] >= 5) { f['n'] = 0; f['until'] = DateTime.now().add(const Duration(minutes: 15)).millisecondsSinceEpoch; }
    all[p] = f;
    await meta.put('fails', all);
  }

  Future<void> _clearFails(String phone) async {
    final all = Map<String, dynamic>.from(meta.get('fails') ?? {})..remove(normPhone(phone));
    await meta.put('fails', all);
  }

  /// Local PIN check first (works offline). If it fails, ask the server and download the shop.
  Future<String?> signIn(String phone, String pin) async {
    final p = normPhone(phone), wait = lockedMinutes(p);
    if (wait > 0) return 'Too many wrong tries. Try again in $wait min.';
    if (login(phone, pin)) { await _clearFails(p); return null; }
    try {
      final r = await http.post(Uri.parse('$apiBase/auth/login'), headers: apiHeaders,
          body: jsonEncode({'phone': p, 'pin': hashPin(pin, p)})).timeout(const Duration(seconds: 12));
      if (r.statusCode == 429) return 'Too many wrong tries. Wait 15 minutes.';
      if (r.statusCode != 200) {
        await _wrong(p);
        return lockedMinutes(p) > 0 ? 'Too many wrong tries. Wait 15 minutes.' : 'Wrong phone number or PIN.';
      }
      final j = jsonDecode(r.body);
      await meta.put('shopId', j['shopId']);
      await meta.put('token', j['token']);
      await meta.put('shop', j['shop'] ?? 'ShopKeep');
      await meta.put('lastPull', '0');
      await pull();
      await _clearFails(p);
      return login(phone, pin) ? null : 'Could not load your shop. Try again.';
    } catch (_) {
      await _wrong(p);
      return needsSetup ? "Can't reach the server. Check your signal and try again." : 'Wrong phone number or PIN, or no signal.';
    }
  }

  /// Download rows changed since last time. Newer `updated` wins. Pulled rows are not re-queued.
  Future<bool> pull() async {
    if (meta.get('shopId') == null) return false;
    try {
      final r = await http.get(Uri.parse('$apiBase/pull?since=${meta.get('lastPull', defaultValue: '0')}'), headers: apiHeaders)
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return false;
      final j = jsonDecode(r.body) as Map;
      final boxes = {'products': products, 'customers': customers, 'sales': sales, 'expenses': expenses, 'users': users, 'moves': moves, 'collections': collections};
      for (final e in (j['rows'] as Map).entries) {
        final b = boxes[e.key];
        if (b == null) continue;
        for (final row in e.value) {
          final old = b.get(row['id']);
          if (old == null || old['updated'].toString().compareTo(row['updated'].toString()) < 0) await b.put(row['id'], Map<String, dynamic>.from(row));
        }
      }
      _rebuildStock();
      await meta.put('lastPull', '${j['now']}');
      notifyListeners();
      return true;
    } catch (_) { return false; }
  }

  // ---- Sales ----
  Future<Map> recordSale(List<Map> items, String method, {String? phone, String status = 'paid', String? ref, String? network, String? customerId}) async {
    final id = newId();
    final total = items.fold<double>(0, (s, e) => s + e['price'] * e['qty']);
    for (final it in items) { await move(it['pid'], -(it['qty'] as int), 'sale', id: 'sale:$id:${it['pid']}'); }
    final sale = {'id': id, 'ts': DateTime.now().toIso8601String(), 'items': items, 'total': total,
      'method': method, 'network': network, 'customerId': customerId, 'device': meta.get('deviceId'), 'phone': phone, 'status': status, 'ref': ref, 'staff': session?['name']};
    await put(sales, sale);
    return sale;
  }

  // ---- MoMo confirmation ----
  // A MoMo sale starts as 'pending' and only counts as revenue once the backend says 'paid'.
  Timer? _poll;
  bool _checking = false;

  void startPolling() {
    _poll ??= Timer.periodic(const Duration(seconds: 8), (_) => checkPending());
    Timer.periodic(const Duration(minutes: 2), (_) => pull());
    Connectivity().onConnectivityChanged.listen((_) { sync(); checkPending(); pull(); }); // back online: catch up
    checkPending();
    pull();
  }

  List<Map> pending() => all(sales).where((s) => s['status'] == 'pending').toList()
    ..sort((a, b) => b['ts'].compareTo(a['ts']));

  double pendingTotal() => pending().fold(0.0, (s, e) => s + (e['total'] as num));

  Future<void> checkPending() async {
    if (_checking) return;
    _checking = true;
    try {
      for (final s in pending()) {
        if (s['ref'] == null) continue; // never reached the gateway; needs "Resend"
        final st = await Momo.status(s['ref']);
        if (st == 'paid') { await settle(s['id']); }
        else if (st == 'failed') { await cancelSale(s['id'], 'failed'); }
      }
    } finally { _checking = false; }
  }

  /// Re-reads the sale first so a sale is never settled or restocked twice.
  Future<void> settle(String id) async {
    final s = Map.from(sales.get(id));
    if (s['status'] != 'pending') return;
    s['status'] = 'paid'; s['paidAt'] = DateTime.now().toIso8601String();
    await put(sales, s);
    if (s['phone'] != null && s['device'] == meta.get('deviceId')) { // only the selling phone sends the receipt
      Momo.notify(s['phone'], 'Received GHâ‚µ${(s['total'] as num).toStringAsFixed(2)} at ${meta.get('shop')}. Thank you!');
    }
  }

  /// status: 'failed' (gateway declined/expired) or 'cancelled' (shopkeeper). Puts stock back.
  Future<void> cancelSale(String id, String status) async {
    final s = Map.from(sales.get(id));
    if (s['status'] != 'pending') return;
    for (final it in s['items']) {
      await move(it['pid'], (it['qty'] as num).toInt(), 'sale $status', id: 'undo:$id:${it['pid']}');
    }
    s['status'] = status;
    await put(sales, s);
  }

  /// Removes a paid sale from revenue and puts the items back. Fixed move ids: refunding twice restocks once.
  Future<void> refundSale(String id) async {
    final s = Map.from(sales.get(id));
    if (s['status'] != 'paid') return;
    for (final it in s['items']) { await move(it['pid'], (it['qty'] as num).toInt(), 'refund', id: 'refund:$id:${it['pid']}'); }
    s['status'] = 'refunded';
    s['refundedAt'] = DateTime.now().toIso8601String();
    s['refundedBy'] = session?['name'];
    await put(sales, s);
  }

  Future<bool> resend(Map s) async {
    final ref = await Momo.request(Network.values.byName(s['network'] ?? 'mtn'), s['phone'], (s['total'] as num).toDouble());
    if (ref == null) return false;
    final u = Map.from(sales.get(s['id']));
    u['ref'] = ref;
    await put(sales, u);
    return true;
  }

  // ---- Credit (pay later) ----
  // Credit sales count as revenue the day they are made. A customer's balance = credit sales - payments received.
  Map<String, double> debts() {
    final m = <String, double>{};
    for (final s in sales.values) {
      if (s['status'] == 'credit' && s['customerId'] != null) m[s['customerId']] = (m[s['customerId']] ?? 0) + (s['total'] as num).toDouble();
    }
    for (final c in collections.values) { m[c['customerId']] = (m[c['customerId']] ?? 0) - (c['amount'] as num).toDouble(); }
    return m;
  }

  double totalOwed() => debts().values.where((v) => v > 0.005).fold(0.0, (a, b) => a + b);

  Future<void> collect(String customerId, double amount, String method) => put(collections,
      {'customerId': customerId, 'amount': amount, 'method': method, 'ts': DateTime.now().toIso8601String(), 'staff': session?['name']});

  // ---- Staff (admin only) ----
  Future<String?> addStaff(String name, String phone, String pin) async {
    final p = normPhone(phone);
    if (name.isEmpty || phone.isEmpty) return 'Enter a name and phone number.';
    if (pin.length < 4) return 'PIN must be at least 4 digits.';
    if (users.values.any((u) => u['phone'] == p)) return 'That phone number already has an account.';
    await put(users, {'name': name, 'phone': p, 'role': 'staff', 'pin': hashPin(pin, p), 'active': true});
    return null;
  }

  Future<void> resetPin(Map u, String pin) => put(users, {...u, 'pin': hashPin(pin, u['phone'])});

  // ---- Reports ----
  Map<String, double> summary(DateTime from, DateTime to) {
    bool inRange(String s) { final t = DateTime.parse(s); return !t.isBefore(from) && t.isBefore(to); }
    double rev = 0, cogs = 0, exp = 0;
    for (final s in sales.values.where((s) => (s['status'] == 'paid' || s['status'] == 'credit') && inRange(s['ts']))) {
      rev += s['total'];
      for (final it in s['items']) { cogs += it['cost'] * it['qty']; }
    }
    for (final e in expenses.values.where((e) => inRange(e['ts']))) { exp += e['amount']; }
    return {'revenue': rev, 'cogs': cogs, 'expenses': exp, 'profit': rev - cogs - exp};
  }

  Map<String, double> today() {
    final n = DateTime.now(), d = DateTime(n.year, n.month, n.day);
    return summary(d, d.add(const Duration(days: 1)));
  }

  List<Map> lowStock() => all(products).where((p) => stock(p['id']) <= (p['reorder'] ?? 5)).toList();

  // ---- Background sync: oldest first, stop on first failure, retry later ----
  bool _syncing = false;
  Future<void> sync() async {
    if (_syncing || queue.isEmpty || kIsWeb && false) return;
    _syncing = true;
    try {
      for (final k in queue.keys.toList()) {
        final r = await http.post(Uri.parse('$apiBase/sync'),
            headers: apiHeaders, body: jsonEncode(queue.get(k))).timeout(const Duration(seconds: 8));
        if (r.statusCode == 401 || r.statusCode == 429 || r.statusCode >= 500) break; // retry later
        if (r.statusCode == 409) await meta.put('syncProblem', 'That phone number already belongs to another shop. Use a different number.');
        await queue.delete(k); // done, or refused for good (403/409): do not block the rest
      }
    } catch (_) {/* offline: keep queue */} finally { _syncing = false; }
  }
}

