import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../constants/app_constants.dart';
import '../../../models/delivery.dart';
import '../../../models/app_user.dart';
import '../../auth/data/auth_repository.dart';

part 'delivery_repository.g.dart';

class DeliveryRepository {
  final AuthRepository _auth;
  final http.Client _client;

  DeliveryRepository(this._auth, this._client);

  Future<Map<String, String>> _headers() async {
    final token = await _auth.getIdToken();
    if (token == null) {
      throw Exception('Session expirée. Veuillez vous reconnecter.');
    }
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  String _extractError(String body) {
    try {
      final json = jsonDecode(body);
      if (json['message'] is String) return json['message'] as String;
      if (json['message'] is List) return (json['message'] as List).join(', ');
    } catch (_) {}
    return 'Une erreur est survenue';
  }

  bool _isSuccess(http.Response response) =>
      response.statusCode >= 200 && response.statusCode < 300;

  Map<String, dynamic> _decodeObject(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    throw const FormatException('Réponse API invalide');
  }

  List<dynamic> _decodeList(String body) {
    final decoded = jsonDecode(body);
    if (decoded is List<dynamic>) return decoded;
    if (decoded is Map<String, dynamic> && decoded['data'] is List<dynamic>) {
      return decoded['data'] as List<dynamic>;
    }
    throw const FormatException('Liste API invalide');
  }

  Delivery _decodeDelivery(String body) {
    final json = _decodeObject(body);
    final payload = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;
    return Delivery.fromJson(payload);
  }

  AppUser _decodeUser(String body) {
    final json = _decodeObject(body);
    final payload = json['user'] is Map<String, dynamic>
        ? json['user'] as Map<String, dynamic>
        : json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;
    return AppUser.fromJson(payload);
  }

  /// GET /deliveries/mine — livraisons assignées au livreur connecté
  Future<List<Delivery>> getMyDeliveries({DeliveryStatus? status}) async {
    final headers = await _headers();
    final uri = Uri.parse('${AppConstants.baseUrl}/deliveries/mine').replace(
      queryParameters: status != null ? {'status': status.toApiString()} : null,
    );

    final response = await _client.get(uri, headers: headers);
    if (_isSuccess(response)) {
      final data = _decodeList(response.body);
      return data
          .map((e) => Delivery.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception(_extractError(response.body));
  }

  /// GET /deliveries/my-missions — missions actives (ASSIGNER + EN_TRANSIT)
  Future<List<Delivery>> getMyMissions() async {
    final headers = await _headers();
    final response = await _client.get(
      Uri.parse('${AppConstants.baseUrl}/deliveries/my-missions'),
      headers: headers,
    );
    if (_isSuccess(response)) {
      final data = _decodeList(response.body);
      return data
          .map((e) => Delivery.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception(_extractError(response.body));
  }

  /// GET /deliveries/:id
  Future<Delivery> getDelivery(String id) async {
    final headers = await _headers();
    final response = await _client.get(
      Uri.parse('${AppConstants.baseUrl}/deliveries/$id'),
      headers: headers,
    );
    if (_isSuccess(response)) {
      return _decodeDelivery(response.body);
    }
    throw Exception(_extractError(response.body));
  }

  /// PATCH /deliveries/:id/accept — accepter la livraison (ASSIGNER → EN_TRANSIT)
  Future<Delivery> acceptDelivery(String id) async {
    final headers = await _headers();
    final response = await _client.patch(
      Uri.parse('${AppConstants.baseUrl}/deliveries/$id/accept'),
      headers: headers,
    );
    if (_isSuccess(response)) {
      return _decodeDelivery(response.body);
    }
    throw Exception(_extractError(response.body));
  }

  /// PATCH /deliveries/:id/status — mettre à jour le statut (ex: LIVRER ou ECHEC)
  Future<Delivery> updateStatus(String id, DeliveryStatus status) async {
    final headers = await _headers();
    final response = await _client.patch(
      Uri.parse('${AppConstants.baseUrl}/deliveries/$id/status'),
      headers: headers,
      body: jsonEncode({'status': status.toApiString()}),
    );
    if (_isSuccess(response)) {
      return _decodeDelivery(response.body);
    }
    throw Exception(_extractError(response.body));
  }

  /// PATCH /deliveries/driver-status — changer le statut du livreur
  Future<void> setDriverStatus(DriverStatus status) async {
    final headers = await _headers();
    final response = await _client.patch(
      Uri.parse('${AppConstants.baseUrl}/deliveries/driver-status'),
      headers: headers,
      body: jsonEncode({'status': status.toApiString()}),
    );
    if (!_isSuccess(response)) throw Exception(_extractError(response.body));
  }

  /// PATCH /deliveries/:id/location — envoyer la position GPS
  Future<void> updateLocation(
    String deliveryId,
    double latitude,
    double longitude,
    double accuracy,
  ) async {
    final headers = await _headers();
    final response = await _client.patch(
      Uri.parse('${AppConstants.baseUrl}/deliveries/$deliveryId/location'),
      headers: headers,
      body: jsonEncode({
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
      }),
    );
    if (!_isSuccess(response)) throw Exception(_extractError(response.body));
  }

  /// GET /users/me — profil du livreur connecté
  Future<AppUser> getMe() async {
    final headers = await _headers();
    final response = await _client.get(
      Uri.parse('${AppConstants.baseUrl}/users/me'),
      headers: headers,
    );
    if (_isSuccess(response)) {
      return _decodeUser(response.body);
    }
    throw Exception(_extractError(response.body));
  }
}

@Riverpod(keepAlive: true)
http.Client httpClient(Ref ref) => http.Client();

@Riverpod(keepAlive: true)
DeliveryRepository deliveryRepository(Ref ref) => DeliveryRepository(
  ref.watch(authRepositoryProvider),
  ref.watch(httpClientProvider),
);
