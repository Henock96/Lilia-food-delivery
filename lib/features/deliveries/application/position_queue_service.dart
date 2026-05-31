import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'position_queue_service.g.dart';

const _kPrefsKey = 'tracking_position_queue';
const _kMaxQueueSize = 1000;

/// Position GPS en attente de sync — sérialisable en JSON.
class QueuedPosition {
  final String deliveryId;
  final double latitude;
  final double longitude;
  final double? accuracy;
  final DateTime recordedAt;

  const QueuedPosition({
    required this.deliveryId,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    required this.recordedAt,
  });

  Map<String, dynamic> toJson() => {
        'deliveryId': deliveryId,
        'latitude': latitude,
        'longitude': longitude,
        if (accuracy != null) 'accuracy': accuracy,
        'recordedAt': recordedAt.toIso8601String(),
      };

  factory QueuedPosition.fromJson(Map<String, dynamic> json) => QueuedPosition(
        deliveryId: json['deliveryId'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        accuracy: (json['accuracy'] as num?)?.toDouble(),
        recordedAt: DateTime.parse(json['recordedAt'] as String),
      );
}

/// File persistante de positions GPS — utilisée quand le réseau est down.
/// Drainée par ConnectivityWatcher quand le réseau revient.
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

  Future<List<QueuedPosition>> drainBatch(int max) async {
    final raw = _readRaw();
    final slice = raw.take(max).toList();
    return slice
        .map((s) => QueuedPosition.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  Future<void> markFlushed(int count) async {
    final raw = _readRaw();
    if (count >= raw.length) {
      await _prefs.remove(_kPrefsKey);
    } else {
      await _prefs.setStringList(_kPrefsKey, raw.sublist(count));
    }
    debugPrint('📍 PositionQueue: flushed $count, remaining=$queuedCount');
  }

  List<String> _readRaw() => _prefs.getStringList(_kPrefsKey) ?? [];
}

@Riverpod(keepAlive: true)
Future<PositionQueueService> positionQueueService(Ref ref) async {
  final prefs = await SharedPreferences.getInstance();
  return PositionQueueService(prefs);
}
