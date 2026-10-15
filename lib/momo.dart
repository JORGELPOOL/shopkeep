import 'dart:convert';
import 'package:http/http.dart' as http;
import 'data.dart';

enum Network { mtn, telecel, airteltigo }
const networkLabel = {Network.mtn: 'MTN MoMo', Network.telecel: 'Telecel Cash', Network.airteltigo: 'AirtelTigo Money'};

/// All three wallets go through YOUR backend, which holds API keys and talks to
/// MTN MoMo Collection API (first), then Telecel / AirtelTigo (directly or via an aggregator).
/// The phone never sees a secret. Flow: request -> customer approves prompt on handset -> poll.
class Momo {
  /// Returns a payment reference, or null if offline / failed.
  static Future<String?> request(Network n, String phone, double amount) async {
    try {
      final r = await http.post(Uri.parse('$apiBase/payments/momo'),
          headers: apiHeaders,
          body: jsonEncode({'network': n.name, 'phone': phone, 'amount': amount, 'currency': 'GHS'}))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) return jsonDecode(r.body)['ref'];
    } catch (_) {}
    return null;
  }

  /// 'paid' | 'pending' | 'failed'
  static Future<String> status(String ref) async {
    try {
      final r = await http.get(Uri.parse('$apiBase/payments/momo/$ref'), headers: apiHeaders).timeout(const Duration(seconds: 8));
      return jsonDecode(r.body)['status'];
    } catch (_) { return 'pending'; }
  }

  /// Backend sends SMS first, WhatsApp as a second channel (receipts, low stock, debt reminders).
  static Future<void> notify(String phone, String message) async {
    Db.i.queue.put(newId(), {'box': 'notify', 'row': {'phone': phone, 'message': message, 'channels': ['sms', 'whatsapp']}});
    Db.i.sync();
  }
}
