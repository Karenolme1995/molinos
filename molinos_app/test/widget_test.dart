import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:molinos_app/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('MolinosApp inicia correctamente',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MolinosApp());

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(MolinosApp), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
