import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:garage_attendance/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ProviderScope(child: GarageAttendanceApp()));

    // Verify that the app builds successfully without throwing errors.
    expect(find.byType(GarageAttendanceApp), findsOneWidget);
  });
}
