/// Échec de livraison (F3-05), côté livreur.
///
/// Le livreur **déclare** ce qui s'est passé ; il ne conclut pas. C'est
/// l'administration qui décide qui en répond — donc si le client est
/// remboursé et si la course est payée.
enum DeliveryFailureReason {
  customerUnreachable('CUSTOMER_UNREACHABLE', 'Client injoignable'),
  addressNotFound('ADDRESS_NOT_FOUND', 'Adresse introuvable'),
  customerRefused('CUSTOMER_REFUSED', 'Le client refuse la commande'),
  accident('ACCIDENT', 'Accident ou panne'),
  lostOrDamaged('LOST_OR_DAMAGED', 'Commande perdue ou abîmée'),
  other('OTHER', 'Autre problème');

  const DeliveryFailureReason(this.wire, this.label);

  final String wire;
  final String label;
}

/// État du protocole « client injoignable », tel que le serveur le tient.
class UnreachableProtocol {
  final int callAttempts;
  final bool smsSent;

  /// Secondes avant que « Déclarer l'échec » soit permis (0 = permis).
  final int waitRemainingSeconds;

  const UnreachableProtocol({
    required this.callAttempts,
    required this.smsSent,
    required this.waitRemainingSeconds,
  });

  /// Deux appels au moins : c'est ce que l'arbitrage exige pour tenir le
  /// client responsable. Le serveur, lui, n'exige que l'attente — on guide
  /// le livreur vers la preuve complète.
  static const minCallAttempts = 2;

  bool get canDeclare =>
      waitRemainingSeconds == 0 && callAttempts >= minCallAttempts;

  factory UnreachableProtocol.fromJson(Map<String, dynamic> json) =>
      UnreachableProtocol(
        callAttempts: (json['callAttempts'] as num?)?.toInt() ?? 0,
        smsSent: json['smsSent'] as bool? ?? false,
        waitRemainingSeconds:
            (json['waitRemainingSeconds'] as num?)?.toInt() ?? 0,
      );

  UnreachableProtocol tick() => UnreachableProtocol(
    callAttempts: callAttempts,
    smsSent: smsSent,
    waitRemainingSeconds: waitRemainingSeconds > 0
        ? waitRemainingSeconds - 1
        : 0,
  );
}
