import 'package:flutter/material.dart';
import 'data/inventory_store.dart';
import 'ui/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StocklyApp());
}

class StocklyApp extends StatelessWidget {
  const StocklyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Stockly',
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
    home: const StartupScreen(),
  );
}

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});
  @override
  State<StartupScreen> createState() => _StartupScreenState();
}
class _StartupScreenState extends State<StartupScreen> {
  late Future<InventoryStore> store = InventoryStore.open();
  @override
  Widget build(BuildContext context) => FutureBuilder<InventoryStore>(
    future: store,
    builder: (context, state) {
      if (state.hasData) return HomeScreen(store: state.data!);
      return Scaffold(body: Center(child: state.hasError
        ? Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Could not open inventory.'),
            FilledButton(onPressed: () => setState(() { store = InventoryStore.open(); }), child: const Text('Retry')),
          ])
        : const CircularProgressIndicator()));
    },
  );
}
