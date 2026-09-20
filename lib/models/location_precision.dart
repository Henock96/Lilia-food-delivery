/// Fiabilité de la destination d'une course — miroir de l'enum backend
/// `LocationPrecision` (Prisma).
///
/// Pour le livreur, ces trois valeurs ne sont pas une nuance technique : elles
/// décident de ce qu'il doit faire en arrivant. Un point `EXACT` se vise, un
/// point `APPROXIMATE` impose d'appeler en entrant dans le quartier, et
/// `UNKNOWN` impose d'appeler avant même de partir.
enum LocationPrecision {
  /// Le client a posé le point sur la carte.
  exact,

  /// Centroïde du quartier. Bon à l'échelle du quartier, faux à celle de la
  /// rue. ⚠️ Ne jamais afficher ce point comme l'adresse du client.
  approximate,

  /// Aucune coordonnée : pas de marqueur, pas d'itinéraire, pas d'ETA.
  unknown;

  String get wireValue => switch (this) {
    LocationPrecision.exact => 'EXACT',
    LocationPrecision.approximate => 'APPROXIMATE',
    LocationPrecision.unknown => 'UNKNOWN',
  };

  /// Toute valeur inconnue — y compris `null`, renvoyé par un backend
  /// antérieur à ce champ — devient `unknown`. C'est le repli sûr : il fait
  /// taire la carte au lieu de la faire mentir.
  static LocationPrecision fromWire(String? value) => switch (value) {
    'EXACT' => LocationPrecision.exact,
    'APPROXIMATE' => LocationPrecision.approximate,
    _ => LocationPrecision.unknown,
  };

  bool get hasPosition => this != LocationPrecision.unknown;

  /// Libellé court affiché sous la destination.
  String get label => switch (this) {
    LocationPrecision.exact => 'Position exacte',
    LocationPrecision.approximate => 'Position approximative — appelez le client',
    LocationPrecision.unknown => 'Position indisponible — appelez le client',
  };
}
