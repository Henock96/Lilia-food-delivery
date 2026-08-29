import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/network/api_client.dart';

part 'ratings_repository.g.dart';

/// Une note reçue par le livreur.
///
/// L'identité du client n'est **pas** servie par le backend, volontairement :
/// une note doit pouvoir être honnête sans que son auteur soit identifiable
/// par la personne notée.
class MyRating {
  final String id;
  final int rating;
  final String? comment;
  final String orderId;
  final DateTime createdAt;

  const MyRating({
    required this.id,
    required this.rating,
    required this.orderId,
    required this.createdAt,
    this.comment,
  });

  String get shortOrderRef => orderId.length >= 6
      ? '#${orderId.substring(orderId.length - 6).toUpperCase()}'
      : '#$orderId';

  factory MyRating.fromJson(Map<String, dynamic> json) {
    return MyRating(
      id: json['id'] as String? ?? '',
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      comment: json['comment'] as String?,
      orderId: json['orderId'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// Synthèse affichée sur le profil : moyenne + nombre d'avis.
class RatingSummary {
  final double? average;
  final int total;

  const RatingSummary({required this.average, required this.total});

  /// `null` = jamais noté. À ne pas confondre avec 0, qui serait une très
  /// mauvaise note : un livreur qui débute n'est pas un mauvais livreur.
  bool get hasRatings => total > 0 && average != null;
}

class RatingsRepository {
  final ApiClient _api;

  RatingsRepository(this._api);

  /// `GET /delivery-reviews/mine`
  Future<List<MyRating>> getMyRatings() async {
    final res = await _api.getJson('/delivery-reviews/mine');
    final data = res.data;
    final list = data is Map<String, dynamic> ? data['data'] : data;
    if (list is! List) return const [];
    return list
        .map((e) => MyRating.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// `GET /delivery-reviews/deliverer/:id/stats`
  Future<RatingSummary> getSummary(String delivererId) async {
    final res = await _api.getJson(
      '/delivery-reviews/deliverer/$delivererId/stats',
    );
    final data = res.data;
    final map = (data is Map<String, dynamic> ? data['data'] : data);
    if (map is! Map<String, dynamic>) {
      return const RatingSummary(average: null, total: 0);
    }
    return RatingSummary(
      average: (map['averageRating'] as num?)?.toDouble(),
      total: (map['totalReviews'] as num?)?.toInt() ?? 0,
    );
  }
}

@Riverpod(keepAlive: true)
RatingsRepository ratingsRepository(Ref ref) =>
    RatingsRepository(ref.watch(apiClientProvider));

@riverpod
Future<List<MyRating>> myRatings(Ref ref) =>
    ref.watch(ratingsRepositoryProvider).getMyRatings();

@riverpod
Future<RatingSummary> myRatingSummary(Ref ref, String delivererId) =>
    ref.watch(ratingsRepositoryProvider).getSummary(delivererId);
