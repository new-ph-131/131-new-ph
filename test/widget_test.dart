import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pharoah_erp/main.dart';
import 'package:pharoah_erp/pharoah_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ERP app boots with its required manager provider', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ChangeNotifierProvider<PharoahManager>(
        create: (_) => PharoahManager(),
        child: const MyApp(),
      ),
    );
    await tester.pump();

    expect(find.text('Pharoah ERP'), findsNothing); // MaterialApp title is metadata, not body text.
    expect(find.byType(AppGateway), findsOneWidget);
  });
}
