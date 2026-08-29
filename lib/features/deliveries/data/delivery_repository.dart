import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/network/api_client.dart';
import '../../../models/delivery.dart';
import '../../../models/app_user.dart';

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

  AppUser _toUser(dynamic decoded) {
    final json = _asObject(decoded);
    final payload = json['user'] is Map<String, dynamic>
        ? json['user'] as Map<String, dynamic>
        : json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;
    return AppUser.fromJson(payload);
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
  Future<Delivery> updateStatus(String id, DeliveryStatus status) async {
    final res = await _api.patchJson(
      '/deliveries/$id/status',
      body: {'status': status.toApiString()},
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

  /// GET /users/me — profil du livreur connecté
  Future<AppUser> getMe() async {
    final res = await _api.getJson('/users/me');
    return _toUser(res.data);
  }
}

@Riverpod(keepAlive: true)
DeliveryRepository deliveryRepository(Ref ref) =>
    DeliveryRepository(ref.watch(apiClientProvider));
