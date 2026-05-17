import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fm_mobile_app/offline_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders the offline A4 editor shell', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: OfflineStudioApp()));
    await tester.pump();

    expect(find.text('Offline A4 Studio'), findsOneWidget);
    expect(find.text('Local print layout'), findsOneWidget);
    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('Gallery'), findsOneWidget);
  });

  test('grid geometry creates a slot for every row and column', () {
    final state = EditorState.initial().copyWith(
      rows: 3,
      columns: 2,
      slots: List<PhotoSlot>.generate(6, (_) => const PhotoSlot()),
    );

    final slots = buildSlotRects(state);

    expect(slots, hasLength(6));
    expect(slots.first.left, state.marginMm);
    expect(slots.last.right, closeTo(a4WidthMm - state.marginMm, 0.001));
  });
}
