/// Ce que Lilia Food doit au livreur, et ce qu'elle lui a déjà versé.
///
/// ⚠️ **Aucun paiement ne part de l'application.** L'argent est remis hors
/// système (espèces, Mobile Money passé à la main) ; ces objets en tiennent le
/// compte. L'écran doit le dire, sans quoi un livreur attendrait un virement
/// automatique qui n'existe pas.
library;

/// Ce qui reste dû, à l'instant de la consultation.
class DriverOutstanding {
  /// Montant restant dû, en XAF.
  final int amountXaf;

  /// Nombre de courses non encore réglées.
  final int courseCount;

  /// Première course non réglée. `null` s'il n'y a rien à régler.
  final DateTime? periodStart;

  /// Coupure du décompte — les courses terminées après n'y sont pas.
  final DateTime coveredUntil;

  const DriverOutstanding({
    required this.amountXaf,
    required this.courseCount,
    required this.coveredUntil,
    this.periodStart,
  });

  factory DriverOutstanding.fromJson(Map<String, dynamic> json) =>
      DriverOutstanding(
        amountXaf: (json['amountXaf'] as num?)?.toInt() ?? 0,
        courseCount: (json['courseCount'] as num?)?.toInt() ?? 0,
        periodStart: _date(json['periodStart']),
        coveredUntil: _date(json['coveredUntil']) ?? DateTime.now(),
      );
}

/// Comment l'argent a été remis.
enum SettlementMethod { cash, mobileMoney, bankTransfer, other }

extension SettlementMethodX on SettlementMethod {
  static SettlementMethod fromString(String? raw) => switch (raw) {
    'CASH' => SettlementMethod.cash,
    'MOBILE_MONEY' => SettlementMethod.mobileMoney,
    'BANK_TRANSFER' => SettlementMethod.bankTransfer,
    _ => SettlementMethod.other,
  };

  String get label => switch (this) {
    SettlementMethod.cash => 'Espèces',
    SettlementMethod.mobileMoney => 'Mobile Money',
    SettlementMethod.bankTransfer => 'Virement',
    SettlementMethod.other => 'Autre',
  };
}

/// Un versement déjà reçu.
class DriverSettlement {
  final String id;
  final int amountXaf;
  final int courseCount;
  final DateTime paidAt;
  final SettlementMethod method;
  final String? reference;

  /// `true` = la saisie a été annulée par l'administration ; les courses
  /// correspondantes sont redevenues dues. L'afficher barré plutôt que le
  /// masquer : un versement qui disparaît de l'historique inquiète à raison.
  final bool cancelled;

  const DriverSettlement({
    required this.id,
    required this.amountXaf,
    required this.courseCount,
    required this.paidAt,
    required this.method,
    required this.cancelled,
    this.reference,
  });

  factory DriverSettlement.fromJson(Map<String, dynamic> json) =>
      DriverSettlement(
        id: json['id'] as String? ?? '',
        amountXaf: (json['amountXaf'] as num?)?.toInt() ?? 0,
        courseCount: (json['courseCount'] as num?)?.toInt() ?? 0,
        paidAt: _date(json['paidAt']) ?? DateTime.now(),
        method: SettlementMethodX.fromString(json['method'] as String?),
        reference: json['reference'] as String?,
        cancelled: json['status'] == 'CANCELLED',
      );
}

DateTime? _date(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}
