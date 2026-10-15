import 'package:flutter/material.dart';
import 'ui.dart';

/// Web build: Bluetooth printing is not available in browsers.
Future<void> printReceipt(BuildContext context, Map sale) async =>
    snack(context, 'Printing works in the Android app. Use WhatsApp or SMS here.');
