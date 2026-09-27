import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'position_queue_service.g.dart';

const _kPrefsKey = 'tracking_position_queue';
const _kMaxQueueSize = 1000;

/// Position GPS en attente de sync — sérialisable en JSON.
class QueuedPosition {
  /// Commande suivie — c'est elle que le lot `POST /tracking/position/batch`
  /// exige (F3-12.1, gate R8). `null` sur les entrées écrites par une version
  /// antérieure de l'app : elles ne peuvent plus être envoyées.
  final String? orderId;
  final String deliveryId;
  final double latitude;
  final double longitude;
  final double? accuracy;
  final DateTime recordedAt;

  const QueuedPosition({
    required this.orderId,
    required this.deliveryId,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    required this.recordedAt,
  });

  /// Forme de STOCKAGE local (préférences).
  Map<String, dynamic> toJson() => {
        if (orderId != null) 'orderId': orderId,
        'deliveryId': deliveryId,
        'latitude': latitude,
        'longitude': longitude,
        if (accuracy != null) 'accuracy': accuracy,
        'recordedAt': recordedAt.toIso8601String(),
      };

  factory QueuedPosition.fromJson(Map<String, dynamic> json) => QueuedPosition(
        orderId: json['orderId'] as String?,
        deliveryId: json['deliveryId'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        accuracy: (json['accuracy'] as num?)?.toDouble(),
        recordedAt: DateTime.parse(json['recordedAt'] as String),
      );

  /// Forme du CONTRAT serveur (`BufferedPositionDto`) : `lat`/`lng`, et un
  /// horodatage en millisecondes epoch. L'ancien envoi (`latitude`,
  /// `recordedAt` ISO) était rejeté en 400 à chaque fois.
  Map<String, dynamic> toBatchJson() => {
        'lat': latitude,
        'lng': longitude,
        'timestamp': recordedAt.millisecondsSinceEpoch,
        if (accuracy != null) 'accuracy': accuracy,
      };
}

/// Une entrée de la file : sa forme brute (clé de suppression) et, si elle
/// se lit, la position qu'elle porte.
class QueuedEntry {
  const QueuedEntry(this.raw, this.position);
  final String raw;
  final QueuedPosition? position;
}

/// File persistante de positions GPS — utilisée quand le réseau est down.
/// Vidée par `PositionBatchFlusher` quand le réseau revient.
class PositionQueueService {
  PositionQueueService(this._prefs);

  final SharedPreferences _prefs;

  int get queuedCount => _readRaw().length;

  Future<void> enqueue(QueuedPosition p) async {
    final raw = _readRaw();
    raw.add(jsonEncode(p.toJson()));
    while (raw.length > _kMaxQueueSize) {
      raw.removeAt(0);
    }
    await _prefs.setStringList(_kPrefsKey, raw);
    debugPrint('📍 PositionQueue: enqueued, total=${raw.length}');
  }

  /// Toute la file, dans l'ordre d'arrivée. Une entrée illisible est rendue
  /// avec `position == null`, pour pouvoir être retirée.
  List<QueuedEntry> readEntries() => _readRaw().map((raw) {
        try {
          return QueuedEntry(
            raw,
            QueuedPosition.fromJson(jsonDecode(raw) as Map<String, dynamic>),
          );
        } catch (_) {
          return QueuedEntry(raw, null);
        }
      }).toList();

  /// Retire ces entrées-là, une occurrence chacune, en relisant la file :
  /// une position arrivée pendant l'envoi n'est jamais effacée par erreur.
  /// (L'ancien `markFlushed(n)` retirait les n premières, quelles qu'elles
  /// soient.)
  Future<void> remove(Iterable<String> raws) async {
    final pending = <String, int>{};
    for (final r in raws) {
      pending[r] = (pending[r] ?? 0) + 1;
    }
    final kept = <String>[];
    for (final r in _readRaw()) {
      final left = pending[r] ?? 0;
      if (left > 0) {
        pending[r] = left - 1;
      } else {
        kept.add(r);
      }
    }
    if (kept.isEmpty) {
      await _prefs.remove(_kPrefsKey);
    } else {
      await _prefs.setStringList(_kPrefsKey, kept);
    }
    debugPrint('📍 PositionQueue: remaining=${kept.length}');
  }

  List<String> _readRaw() => _prefs.getStringList(_kPrefsKey) ?? [];
}

@Riverpod(keepAlive: true)
Future<PositionQueueService> positionQueueService(Ref ref) async {
  final prefs = await SharedPreferences.getInstance();
  return PositionQueueService(prefs);
}
