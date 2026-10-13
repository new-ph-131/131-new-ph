import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharoah_erp/main.dart';

void main() {
  testWidgets('Pharoah ERP root app builds', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    final appFinder = find.byType(MaterialApp);
    expect(appFinder, findsOneWidget);
    final app = tester.widget<MaterialApp>(appFinder);
    expect(app.title, 'Pharoah ERP');
  });
}
