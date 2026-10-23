import 'package:flutter_test/flutter_test.dart';
import 'package:lilia_food_delivery/constants/app_constants.dart';

/// Choix du backend au build.
///
/// Sans `--dart-define`, l'app vise la production : une build publiée ne doit
/// rien changer. Une build de préproduction passe
/// `--dart-define=API_URL=… --dart-define=WS_URL=…`, comme les apps client et
/// vendeurs. Ce test, lancé sans define, fige le défaut.
void main() {
  test('sans --dart-define, API et WebSocket visent la production', () {
    expect(AppConstants.baseUrl, 'https://lilia-backend.onrender.com');
    expect(AppConstants.wsUrl, 'https://lilia-backend.onrender.com');
  });
}
