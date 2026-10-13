import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pharoah_erp/main.dart';
import 'package:pharoah_erp/pharoah_manager.dart';

void main() {
  testWidgets('Pharoah ERP root app builds', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => PharoahManager(),
        child: const MyApp(),
      ),
    );
    await tester.pump();

    final appFinder = find.byType(MaterialApp);
    expect(appFinder, findsOneWidget);
    expect(tester.widget<MaterialApp>(appFinder).title, 'Pharoah ERP');
  });
}
