class AppConstants {
  /// Backend. Surchargeable au build, comme les apps client et vendeurs :
  /// `--dart-define=API_URL=https://…` (préproduction). Défaut : production.
  static const String baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://lilia-backend.onrender.com',
  );

  /// Hôte WebSocket (Socket.io). Suit [baseUrl] par défaut, surchargeable
  /// séparément : `--dart-define=WS_URL=https://…`.
  static const String wsUrl = String.fromEnvironment(
    'WS_URL',
    defaultValue: 'https://lilia-backend.onrender.com',
  );
  static const String trackingNamespace = '/tracking';
  static const String appName = 'Lilia Livreur';
}
