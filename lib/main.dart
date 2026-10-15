import 'package:flutter/material.dart';
import 'data.dart';
import 'screens.dart';
import 'ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Db.i.init();
  Db.i.startPolling();
  runApp(const ShopKeep());
}


class ShopKeep extends StatelessWidget {
  const ShopKeep({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'ShopKeep',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: ListenableBuilder(
          listenable: Db.i,
          builder: (_, __) => Db.i.needsSetup && !Db.i.joining ? const SetupScreen() : Db.i.session == null ? const LoginScreen() : const Home(),
        ),
      );
}
