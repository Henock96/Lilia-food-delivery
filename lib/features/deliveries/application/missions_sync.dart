import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../models/app_user.dart';
import '../../profile/application/profile_controller.dart';
import 'deliveries_controller.dart';

part 'missions_sync.g.dart';

/// Crée le minuteur périodique — injectable pour les tests.
typedef PeriodicTimerFactory =
    Timer Function(Duration period, void Function(Timer) tick);

/// Les missions ne dépendent plus seulement du push (DEL-005).
///
/// Un push perdu (FCM en retard, APNs iOS non prouvé, Android en économie
/// d'énergie) laissait une mission assignée invisible : la liste ne bougeait
/// que sur notification ou geste manuel, et le vendeur attendait une réponse
/// qui ne venait pas. Le push reste un signal ; la vérité est relue au
/// serveur :
///
/// - **retour au premier plan** : relecture immédiate des missions et du
///   profil (le statut du livreur a pu changer pendant l'absence) ;
/// - **polling léger** : une relecture toutes les [interval], tant que l'app
///   est visible **et** que le livreur est `AVAILABLE`. Hors ligne, il n'attend
///   rien ; en course, ses missions ne changent qu'au rythme de ses gestes.
///
/// `inactive` (volet des notifications, appel entrant) compte comme visible :
/// l'écran est encore là. `hidden`, `paused` et `detached` arrêtent tout.
///
/// Un seul minuteur à la fois : il n'existe que quand les conditions sont
/// réunies ([evaluate]), et il est détruit dès qu'elles cessent.
class MissionsSync with WidgetsBindingObserver {
  MissionsSync({
    required Future<void> Function() refresh,
    required void Function() refreshProfile,
    required DriverStatus? Function() driverStatus,
    this.interval = const Duration(seconds: 60),
    PeriodicTimerFactory? periodic,
  }) : _refresh = refresh,
       _refreshProfile = refreshProfile,
       _driverStatus = driverStatus,
       _periodic = periodic ?? Timer.periodic;

  final Future<void> Function() _refresh;
  final void Function() _refreshProfile;
  final DriverStatus? Function() _driverStatus;
  final PeriodicTimerFactory _periodic;
  final Duration interval;

  bool _started = false;
  bool _visible = true;
  bool _refreshing = false;
  Timer? _timer;

  /// Le polling tourne-t-il en ce moment ?
  bool get isPolling => _timer != null;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _visible = state == null || _isVisible(state);
    evaluate();
  }

  void stop() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasVisible = _visible;
    _visible = _isVisible(state);
    if (state == AppLifecycleState.resumed && !wasVisible) {
      // Le statut a pu changer en arrière-plan (course close par l'admin,
      // passage hors ligne ailleurs) : on le relit avec les missions.
      _refreshProfile();
      if (_driverStatus() != DriverStatus.offline) unawaited(_sync());
    }
    evaluate();
  }

  /// Démarre ou arrête le minuteur selon les conditions du moment. À appeler
  /// quand le statut du livreur change.
  void evaluate() {
    final shouldPoll =
        _started && _visible && _driverStatus() == DriverStatus.available;
    if (shouldPoll && _timer == null) {
      _timer = _periodic(interval, (_) {
        if (_driverStatus() == DriverStatus.available) unawaited(_sync());
      });
    } else if (!shouldPoll) {
      _cancel();
    }
  }

  /// Une relecture à la fois : un retour au premier plan qui tombe sur un
  /// cycle de polling n'en déclenche pas deux.
  Future<void> _sync() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      await _refresh();
    } finally {
      _refreshing = false;
    }
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }

  static bool _isVisible(AppLifecycleState s) =>
      s == AppLifecycleState.resumed || s == AppLifecycleState.inactive;
}

@Riverpod(keepAlive: true)
MissionsSync missionsSync(Ref ref) {
  final sync = MissionsSync(
    refresh: () async {
      await ref.read(missionsControllerProvider.notifier).syncSilently();
    },
    refreshProfile: () => ref.invalidate(profileControllerProvider),
    driverStatus: () => ref.read(profileControllerProvider).value?.driverStatus,
  );
  // Disponible ↔ en course ↔ hors ligne : le minuteur suit.
  ref.listen(profileControllerProvider, (_, _) => sync.evaluate());
  ref.onDispose(sync.stop);
  return sync;
}
