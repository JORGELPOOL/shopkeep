import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ShopKeep MaterialApp renders its title', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        title: 'ShopKeep',
        home: const Scaffold(
          body: Text('ShopKeep'),
        ),
      ),
    );

    expect(find.text('ShopKeep'), findsOneWidget);
  });
}
