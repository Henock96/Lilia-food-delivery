import 'package:flutter/foundation.dart';

import 'package:lilia_food_delivery/features/deliveries/application/position_queue_service.dart';
import 'package:lilia_food_delivery/features/deliveries/application/tracking_batch_policy.dart';

/// Envoi d'un lot : `POST /tracking/position/batch` pour UNE commande. Lève
/// en cas d'échec — c'est [classifyTrackingError] qui décide de la suite.
typedef SendPositionBatch =
    Future<void> Function(String orderId, List<Map<String, dynamic>> positions);

/// Bilan d'un vidage, pour les journaux et les tests.
class FlushReport {
  const FlushReport({
    this.sent = 0,
    this.dropped = 0,
    this.batches = 0,
    this.stoppedOnTransientError = false,
  });

  /// Positions acceptées par le serveur.
  final int sent;

  /// Positions abandonnées : refus définitif, entrée héritée sans `orderId`,
  /// entrée illisible.
  final int dropped;

  /// Lots effectivement tentés.
  final int batches;

  /// Le vidage s'est arrêté sur une panne passagère : le reste attend le
  /// prochain déclencheur.
  final bool stoppedOnTransientError;
}

/// Vide la file des positions accumulées hors ligne (F3-12.1, gate R8).
///
/// Le serveur exige UN `orderId` par lot ; la file, elle, peut mélanger
/// plusieurs courses (réassignation, courses successives pendant une même
/// coupure). Les positions sont donc regroupées par commande, triées par
/// heure de relevé, puis découpées en lots de [chunkSize] au plus
/// (`BatchPositionsDto` en accepte 500).
///
/// Chaque lot a exactement trois issues :
/// - accepté → retiré de la file ;
/// - refus définitif (400, 403, 404…) → retiré, jamais rejoué ;
/// - panne passagère → gardé, et le vidage s'arrête : la suite attend le
///   prochain retour réseau ou la prochaine reprise.
class PositionBatchFlusher {
  PositionBatchFlusher({
    required this.queue,
    required this.send,
    this.chunkSize = 100,
  });

  final PositionQueueService queue;
  final SendPositionBatch send;
  final int chunkSize;

  Future<FlushReport> flush() async {
    final entries = queue.readEntries();
    if (entries.isEmpty) return const FlushReport();

    // Héritées (sans `orderId`) ou illisibles : le serveur n'en ferait rien.
    final unusable = entries
        .where((e) => e.position?.orderId == null)
        .map((e) => e.raw)
        .toList();
    if (unusable.isNotEmpty) {
      await queue.remove(unusable);
      debugPrint('📡 ${unusable.length} position(s) héritée(s) abandonnée(s)');
    }
    var dropped = unusable.length;
    var sent = 0;
    var batches = 0;

    final byOrder = <String, List<QueuedEntry>>{};
    for (final e in entries) {
      final orderId = e.position?.orderId;
      if (orderId == null) continue;
      byOrder.putIfAbsent(orderId, () => []).add(e);
    }

    for (final MapEntry(key: orderId, value: group) in byOrder.entries) {
      group.sort(
        (a, b) => a.position!.recordedAt.compareTo(b.position!.recordedAt),
      );
      for (var i = 0; i < group.length; i += chunkSize) {
        final chunk = group.sublist(
          i,
          i + chunkSize > group.length ? group.length : i + chunkSize,
        );
        batches++;
        try {
          await send(
            orderId,
            chunk.map((e) => e.position!.toBatchJson()).toList(),
          );
          sent += chunk.length;
          await queue.remove(chunk.map((e) => e.raw));
        } catch (error) {
          if (classifyTrackingError(error) == BatchFailureAction.drop) {
            dropped += chunk.length;
            await queue.remove(chunk.map((e) => e.raw));
            debugPrint(
              '📡 Lot de ${chunk.length} position(s) refusé définitivement '
              '(commande $orderId) — abandonné : $error',
            );
            continue;
          }
          debugPrint(
            '📡 Lot en échec passager, nouvel essai plus tard : $error',
          );
          return FlushReport(
            sent: sent,
            dropped: dropped,
            batches: batches,
            stoppedOnTransientError: true,
          );
        }
      }
    }
    return FlushReport(sent: sent, dropped: dropped, batches: batches);
  }
}
