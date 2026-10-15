import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'ui.dart';

/// Opens the camera and returns the first barcode it reads (pops with a String).
class ScanScreen extends StatefulWidget { const ScanScreen({super.key}); @override State<ScanScreen> createState() => _ScanState(); }
class _ScanState extends State<ScanScreen> {
  bool done = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(title: const Text('Scan barcode'), backgroundColor: Colors.black, foregroundColor: Colors.white),
    body: Stack(children: [
      MobileScanner(onDetect: (capture) {
        final code = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
        if (code == null || done) return;
        done = true; // read once, then close
        Navigator.pop(context, code);
      }),
      Center(child: Container(width: 260, height: 160, decoration: BoxDecoration(border: Border.all(color: sun, width: 3), borderRadius: BorderRadius.circular(18)))),
      const Positioned(left: 0, right: 0, bottom: 40, child: Text('Point the camera at the barcode', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 16))),
    ]));
}
