import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../models/delivery.dart';
import '../../../models/app_user.dart';
import '../../../models/driver_earnings.dart';

part 'delivery_repository.g.dart';

class DeliveryRepository {
  final ApiClient _api;

  DeliveryRepository(this._api);

  Map<String, dynamic> _asObject(dynamic decoded) {
    if (decoded is Map<String, dynamic>) return decoded;
    throw const FormatException('Réponse API invalide');
  }

  List<dynamic> _asList(dynamic decoded) {
    if (decoded is List<dynamic>) return decoded;
    if (decoded is Map<String, dynamic> && decoded['data'] is List<dynamic>) {
      return decoded['data'] as List<dynamic>;
    }
    throw const FormatException('Liste API invalide');
  }

  Delivery _toDelivery(dynamic decoded) {
    final json = _asObject(decoded);
    final payload = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;
    return Delivery.fromJson(payload);
  }

  /// Déballe les enveloppes du backend jusqu'à l'objet utilisateur.
  ///
  /// ⚠️ Il y en a **deux** sur `GET /users/me` : le contrôleur renvoie
  /// `{ user }`, que l'intercepteur global enveloppe en `{ data: { user } }`.
  /// L'ancienne version n'en retirait qu'une seule et rendait donc
  /// `AppUser.fromJson({ user: … })` — tous les champs absents, `nom` retombant
  /// sur son défaut « Livreur ». Le profil affichait ce mot pour tout le monde.
  ///
  /// La boucle tolère les deux ordres et les deux profondeurs : une app
  /// déployée continue de fonctionner si le backend aplatit sa réponse.
  AppUser _toUser(dynamic decoded) {
    var payload = _asObject(decoded);
    for (var i = 0; i < 3; i++) {
      final inner = payload['data'] ?? payload['user'];
      if (inner is Map<String, dynamic>) {
        payload = inner;
      } else {
        break;
      }
    }
    return AppUser.fromJson(payload);
  }

  /// GET /drivers/me/earnings/outstanding — ce qui me reste dû.
  ///
  /// ⚠️ Lecture pure côté serveur : la consulter ne verrouille aucune course
  /// et ne déclenche aucun versement.
  Future<DriverOutstanding> getOutstanding() async {
    final res = await _api.getJson('/drivers/me/earnings/outstanding');
    final json = _asObject(res.data);
    final payload = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;
    return DriverOutstanding.fromJson(payload);
  }

  /// GET /drivers/me/earnings — mes versements déjà reçus.
  Future<List<DriverSettlement>> getSettlements() async {
    final res = await _api.getJson('/drivers/me/earnings');
    return _asList(res.data)
        .map((e) => DriverSettlement.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// GET /deliveries/mine — livraisons assignées au livreur connecté
  Future<List<Delivery>> getMyDeliveries({DeliveryStatus? status}) async {
    final res = await _api.getJson(
      '/deliveries/mine',
      query: status != null ? {'status': status.toApiString()} : null,
    );
    return _asList(res.data)
        .map((e) => Delivery.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// GET /deliveries/my-missions — missions actives (ASSIGNER + EN_TRANSIT)
  Future<List<Delivery>> getMyMissions() async {
    final res = await _api.getJson('/deliveries/my-missions');
    return _asList(res.data)
        .map((e) => Delivery.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// GET /deliveries/:id
  Future<Delivery> getDelivery(String id) async {
    final res = await _api.getJson('/deliveries/$id');
    return _toDelivery(res.data);
  }

  /// PATCH /deliveries/:id/accept — accepter la mission (ASSIGNER → ACCEPTER).
  ///
  /// N'envoie AUCUNE notification au client : accepter, c'est s'engager à aller
  /// chercher le repas, pas être en route vers lui.
  Future<Delivery> acceptDelivery(String id) async {
    final res = await _api.patchJson('/deliveries/$id/accept');
    return _toDelivery(res.data);
  }

  /// PATCH /deliveries/:id/decline — refuser une mission non encore acceptée.
  ///
  /// La livraison redevient assignable et le vendeur est prévenu qu'il doit
  /// désigner quelqu'un d'autre. Sans ce chemin, le seul moyen de ne pas faire
  /// une course était de l'ignorer — le vendeur attendait alors dans le vide.
  Future<void> declineDelivery(String id, {String? reason}) async {
    await _api.patchJson(
      '/deliveries/$id/decline',
      body: {
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
  }

  /// PATCH /deliveries/:id/pickup — confirmer la récupération du repas
  /// (ACCEPTER → EN_TRANSIT).
  ///
  /// C'est ce geste qui fait passer la commande EN_ROUTE côté backend et
  /// déclenche le « votre commande est en route » chez le client.
  Future<Delivery> confirmPickup(String id) async {
    final res = await _api.patchJson('/deliveries/$id/pickup');
    return _toDelivery(res.data);
  }

  /// PATCH /deliveries/:id/status — mettre à jour le statut (ex: LIVRER ou ECHEC)
  ///
  /// [handoverCode] : code de remise à 4 chiffres dicté par le client, qui
  /// atteste la livraison (Master Audit v1, F-06). Le serveur le vérifie dès
  /// qu'il est fourni, et finira par l'exiger.
  Future<Delivery> updateStatus(
    String id,
    DeliveryStatus status, {
    String? handoverCode,
  }) async {
    final res = await _api.patchJson(
      '/deliveries/$id/status',
      body: {'status': status.toApiString(), 'handoverCode': ?handoverCode},
    );
    return _toDelivery(res.data);
  }

  /// PATCH /deliveries/driver-status — changer le statut du livreur
  Future<void> setDriverStatus(DriverStatus status) async {
    await _api.patchJson(
      '/deliveries/driver-status',
      body: {'status': status.toApiString()},
    );
  }

  /// PATCH /deliveries/:id/location — envoyer la position GPS
  Future<void> updateLocation(
    String deliveryId,
    double latitude,
    double longitude,
    double accuracy,
  ) async {
    await _api.patchJson(
      '/deliveries/$deliveryId/location',
      body: {
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
      },
    );
  }

  /// Envoie un batch de positions GPS accumulées offline.
  /// Backend : POST /tracking/position/batch — body `{ positions: [...] }`.
  /// Retourne true si succès, false sinon (la queue n'est pas vidée).
  Future<bool> sendPositionsBatch(List<Map<String, dynamic>> positions) async {
    if (positions.isEmpty) return true;
    try {
      await _api.postJson(
        '/tracking/position/batch',
        body: {'positions': positions},
      );
      return true;
    } catch (e) {
      debugPrint('⚠️ sendPositionsBatch failed: $e');
      return false;
    }
  }

  /// GET /drivers/me — compte **et** profil métier du livreur connecté.
  ///
  /// Remplace `GET /users/me`, qui ne portait ni `statusUser` ni le profil
  /// métier : l'écran ne pouvait donc afficher que « Actif » écrit en dur.
  /// Repli sur `/users/me` si le backend n'expose pas encore la route — une
  /// app publiée ne doit pas devenir inutilisable parce que le serveur est en
  /// retard d'un déploiement.
  Future<AppUser> getMe() async {
    try {
      final res = await _api.getJson('/drivers/me');
      return _toUser(res.data);
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
      final res = await _api.getJson('/users/me');
      return _toUser(res.data);
    }
  }

  /// PATCH /drivers/me — le livreur corrige son nom, son téléphone ou sa photo.
  ///
  /// Volontairement limité à ces trois champs : véhicule, plaque, permis et
  /// zones sont vérifiés par l'administration, les laisser modifier ici
  /// viderait la vérification de son sens.
  Future<AppUser> updateMe({
    String? nom,
    String? phone,
    String? imageUrl,
  }) async {
    final res = await _api.patchJson(
      '/drivers/me',
      // Seuls les champs réellement fournis partent : un `null` explicite
      // effacerait la valeur côté serveur, ce qui n'est pas l'intention d'un
      // formulaire dont on n'a touché qu'un champ.
      body: {'nom': ?nom, 'phone': ?phone, 'imageUrl': ?imageUrl},
    );
    return _toUser(res.data);
  }
}

@Riverpod(keepAlive: true)
DeliveryRepository deliveryRepository(Ref ref) =>
    DeliveryRepository(ref.watch(apiClientProvider));

/// Ce qui reste dû au livreur connecté.
///
/// ⚠️ Lecture pure : la consulter ne verrouille aucune course et ne déclenche
/// aucun versement. Elle peut donc être rafraîchie librement.
@riverpod
Future<DriverOutstanding> myOutstanding(Ref ref) =>
    ref.watch(deliveryRepositoryProvider).getOutstanding();

/// Les versements déjà reçus par le livreur connecté.
@riverpod
Future<List<DriverSettlement>> mySettlements(Ref ref) =>
    ref.watch(deliveryRepositoryProvider).getSettlements();
