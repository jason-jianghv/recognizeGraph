import 'package:flutter_test/flutter_test.dart';
import 'package:shitu_app/main.dart';

void main() {
  testWidgets('App boots to splash', (tester) async {
    await tester.pumpWidget(const ShituApp());
    expect(find.textContaining('欢迎来到识图'), findsOneWidget);
    // Flush splash timer so the test binding stays clean.
    await tester.pump(const Duration(milliseconds: 2300));
    expect(find.text('探索世界'), findsOneWidget);
  });
}
