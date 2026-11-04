import 'package:flutter_test/flutter_test.dart';

import 'package:android_screen/main.dart';

void main() {
  testWidgets('Setup screen asks for a screen ID', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Enter Screen ID'), findsOneWidget);
    expect(find.text('CONNECT'), findsOneWidget);
  });
}
