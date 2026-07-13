import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:timer_app/main.dart';

void main() {
  testWidgets('Tela de configuração abre com os campos principais',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const TimerApp());
    await tester.pumpAndSettle();

    expect(find.text('Número de lutas'), findsOneWidget);
    expect(find.text('Tempo de luta'), findsOneWidget);
    expect(find.text('Tempo de descanso'), findsOneWidget);
    expect(find.text('INICIAR'), findsOneWidget);
  });
}
