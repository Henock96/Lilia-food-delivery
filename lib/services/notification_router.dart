/// D'où vient le message FCM en cours de traitement.
///
/// La distinction évite qu'une mission reçue **pendant** que le livreur
/// consulte un autre écran (une course en cours, sa carte) ne le déplace sans
/// qu'il ait rien demandé : seul un tap explicite autorise une navigation.
enum NotificationTrigger { foreground, tap }

/// Ce qu'il faut rafraîchir à réception.
enum NotificationTarget {
  missions,

  /// Dispatch FCFS : la liste des commandes disponibles.
  available,
}

/// Ce que l'app doit faire en réponse à un message FCM.
class NotificationAction {
  const NotificationAction({this.refresh, this.route});

  /// Provider à recharger, `null` si rien à faire.
  final NotificationTarget? refresh;

  /// Chemin go_router à ouvrir, `null` hors d'un tap explicite. Les routes de
  /// cette app ne sont pas nommées : on navigue par chemin.
  final String? route;

  static const none = NotificationAction();

  @override
  bool operator ==(Object other) =>
      other is NotificationAction &&
      other.refresh == refresh &&
      other.route == route;

  @override
  int get hashCode => Object.hash(refresh, route);

  @override
  String toString() => 'NotificationAction(refresh: $refresh, route: $route)';
}

/// Traduit le payload `data` d'un push FCM en action applicative.
///
/// Volontairement pur : aucune dépendance à Firebase, Riverpod ou go_router,
/// pour que la correspondance avec ce qu'émet réellement le backend
/// (`delivery-assignment.service.ts`) soit vérifiable directement.
class NotificationRouter {
  const NotificationRouter();

  /// Types émis par le backend à destination du livreur
  /// (`DeliveriesListener`, backend).
  ///
  /// Le livreur ne recevait historiquement que `delivery_assigned` : ni la
  /// commande prête, ni l'annulation, ni le retrait de sa mission ne lui
  /// parvenaient. Tous ces messages doivent recharger sa liste de missions.
  static const _missionTypes = {
    'delivery_assigned',
    // La commande qu'il attend vient de passer PRET.
    'delivery_ready',
    // Sa mission lui a été retirée (réassignée à un autre livreur).
    'delivery_unassigned',
    // La commande a été annulée : la mission disparaît de sa liste.
    'delivery_cancelled',
    // Sa livraison a été marquée en échec.
    'delivery_failed',
  };

  /// Types qui **retirent** une mission : ouvrir son détail au tap n'aurait
  /// pas de sens, la course n'existe plus pour ce livreur.
  static const _removalTypes = {
    'delivery_unassigned',
    'delivery_cancelled',
  };

  /// Dispatch FCFS (10/11/2026). ⚠️ Ces pushs portent `openDeliveryId`,
  /// jamais `deliveryId` : la course n'est pas celle du livreur, et le repli
  /// « tout `deliveryId` ouvre `/deliveries/:id` » lui vaudrait un 403.
  /// Un tap mène à l'onglet Disponibles ; jamais à une mission.
  static const _offerType = 'delivery_offer';

  /// Data seule : la course vient d'être prise (ou retirée). On retire la
  /// carte, sans naviguer nulle part.
  static const _offerTakenType = 'delivery_offer_taken';

  NotificationAction resolve(
    Map<String, dynamic> data, {
    required NotificationTrigger trigger,
  }) {
    final type = data['type'] as String?;

    if (type == _offerType) {
      return NotificationAction(
        refresh: NotificationTarget.available,
        route: trigger == NotificationTrigger.tap ? '/available' : null,
      );
    }
    if (type == _offerTakenType) {
      return const NotificationAction(refresh: NotificationTarget.available);
    }

    final deliveryId = data['deliveryId'] as String?;
    final hasDeliveryId = deliveryId != null && deliveryId.isNotEmpty;

    // On reconnaît une mission au type **ou** à la présence d'un deliveryId :
    // si le backend introduit un nouveau type, le rafraîchissement continue de
    // marcher.
    if (!_missionTypes.contains(type) && !hasDeliveryId) {
      return NotificationAction.none;
    }

    // Une mission retirée ne mène nulle part : on rafraîchit la liste, sans
    // ouvrir un écran de détail sur une course qui n'est plus la sienne.
    final isRemoval = _removalTypes.contains(type);

    return NotificationAction(
      refresh: NotificationTarget.missions,
      route: trigger == NotificationTrigger.tap && hasDeliveryId && !isRemoval
          ? '/deliveries/$deliveryId'
          : null,
    );
  }
}
