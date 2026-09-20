import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../models/delivery.dart';
import '../data/delivery_repository.dart';
import 'connectivity_watcher.dart';
import 'location_service.dart';
import 'tracking_issue.dart';

part 'tracking_resume_service.g.dart';

/// Observe le lifecycle de l'app et redémarre `LocationService.startTracking`
/// si une mission EN_TRANSIT existe quand l'app revient au premier plan
/// (ou au boot).
///
/// Utile quand :
///   - L'app est tuée par le système (mémoire faible)
///   - L'app est minimisée longtemps (le Timer Dart s'arrête)
///   - L'utilisateur ouvre l'app après un crash
///
/// ⚠️ Ne remplace PAS un vrai service background : si l'app est complètement
/// fermée, aucun tracking n'a lieu. Pour ça il faudrait
/// `flutter_background_geolocation` (payant) ou un foreground service Android.
class TrackingResumeService with WidgetsBindingObserver {
  final DeliveryRepository _repo;
  final LocationService _location;
  final Ref _ref;

  bool _checking = false;

  TrackingResumeService(this._repo, this._location, this._ref);

  void start() {
    WidgetsBinding.instance.addObserver(this);
    // Check immédiat au démarrage de l'app
    _checkAndResume();
  }

  void stop() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndResume();
    }
  }

  Future<void> _checkAndResume() async {
    if (_checking || _location.isTracking) return;
    _checking = true;

    // Ceinture + bretelles : flush la queue offline au cas où le
    // ConnectivityWatcher aurait raté une transition réseau pendant
    // que l'app était en pause.
    try {
      await _ref.read(connectivityWatcherProvider).flushQueue();
    } catch (e) {
      debugPrint('⚠️ Resume flush failed: $e');
    }

    try {
      final missions = await _repo.getMyMissions();
      // `en_transit` uniquement, et pas `accepter` : tant que le livreur n'a
      // pas le repas, sa position n'a pas à être diffusée au client.
      final active = missions
          .where((m) => m.status == DeliveryStatus.en_transit)
          .toList();
      if (active.isEmpty) return;

      // Reprend le tracking sur la 1ère mission EN_TRANSIT
      // (en pratique un livreur n'a qu'une livraison active à la fois)
      final mission = active.first;
      final permission = await _location.requestPermissionDetailed();
      if (!permission.granted) {
        // Ce service n'a pas de `BuildContext` : il ne peut rien afficher
        // lui-même. Il publie donc l'interruption dans un état observable, que
        // `TrackingIssueBanner` rend visible par-dessus le routeur.
        //
        // Sans cela, le refus n'allait que dans les logs : le livreur reprenait
        // sa course en croyant être suivi, et le client regardait un marqueur
        // figé jusqu'à la sonnette. Ni l'un ni l'autre ne pouvait s'en rendre
        // compte — c'est précisément le genre de panne qui doit se voir.
        _ref
            .read(trackingIssueControllerProvider.notifier)
            .report(permission, deliveryId: mission.id);

        debugPrint(
          '[TrackingResume] tracking non repris — ${permission.reason?.name} : '
          '${permission.message}',
        );
        return;
      }

      // Reprise réussie : on lève une éventuelle alerte précédente.
      _ref.read(trackingIssueControllerProvider.notifier).clear();
      _location.startTracking(deliveryId: mission.id, orderId: mission.orderId);
      debugPrint('[TrackingResume] tracking repris pour mission ${mission.id}');
    } catch (e) {
      debugPrint('[TrackingResume] erreur : $e');
    } finally {
      _checking = false;
    }
  }
}

@Riverpod(keepAlive: true)
TrackingResumeService trackingResumeService(Ref ref) {
  final service = TrackingResumeService(
    ref.watch(deliveryRepositoryProvider),
    ref.watch(locationServiceProvider),
    ref,
  );
  ref.onDispose(service.stop);
  return service;
}
