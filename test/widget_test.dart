// This is a basic Flutter widget test.
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/app.dart';

void main() {
  testWidgets('App starts', (WidgetTester tester) async {
    // App starts without crashing
    await tester.pumpWidget(const LezPosApp());
  });
}
