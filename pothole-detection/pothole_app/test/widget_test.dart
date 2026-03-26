import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pothole_app/main.dart';
import 'package:pothole_app/theme_provider.dart';

void main() {
  testWidgets('PotholeApp smoke test — login screen renders',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeProvider(),
        child: const PotholeApp(),
      ),
    );
    // Login screen should appear
    expect(find.text('PotholeWatch'), findsOneWidget);
  });
}
