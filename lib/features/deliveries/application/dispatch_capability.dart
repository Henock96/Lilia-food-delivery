import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/delivery_repository.dart';

part 'dispatch_capability.g.dart';

/// Déclare au serveur que cette version de l'app sait recevoir et accepter
/// des propositions de course (dispatch FCFS, 10/11/2026).
///
/// Le serveur ne propose une commande qu'aux apps qui l'ont dit
/// (`DriverProfile.offersEnabledAt`) : une ancienne version, qui ouvrirait
/// une mission qui n'est pas la sienne, n'est jamais candidate. La
/// déclaration sert aussi de signe de vie — passé 12 h sans renouvellement,
/// le livreur n'est plus notifié, même « Disponible ».
///
/// Pur et sans horloge réelle (injectable) : la cadence est vérifiable sans
/// Firebase ni Riverpod. Silencieux : un échec n'est jamais montré, la
/// prochaine occasion (retour au premier plan, connexion) réessaiera.
class DispatchCapabilityDeclarer {
  DispatchCapabilityDeclarer({
    required Future<void> Function() declare,
    this.minInterval = const Duration(minutes: 30),
    DateTime Function()? now,
  }) : _declare = declare,
       _now = now ?? DateTime.now;

  final Future<void> Function() _declare;
  final DateTime Function() _now;

  /// En deçà, un nouvel appel est ignoré : le retour au premier plan peut
  /// se répéter toutes les quelques secondes.
  final Duration minInterval;

  DateTime? _lastSuccess;
  bool _inFlight = false;

  DateTime? get lastSuccess => _lastSuccess;

  /// Rend `true` si une déclaration est réellement partie et a abouti.
  Future<bool> declare({bool force = false}) async {
    if (_inFlight) return false;
    final last = _lastSuccess;
    if (!force && last != null && _now().difference(last) < minInterval) {
      return false;
    }
    _inFlight = true;
    try {
      await _declare();
      _lastSuccess = _now();
      return true;
    } catch (e) {
      debugPrint('[Dispatch] déclaration de capacité en échec : $e');
      return false;
    } finally {
      _inFlight = false;
    }
  }

  /// Nouvelle session (déconnexion puis connexion d'un autre compte) : la
  /// capacité est propre au compte, on la redéclare.
  void reset() => _lastSuccess = null;
}

@Riverpod(keepAlive: true)
DispatchCapabilityDeclarer dispatchCapability(Ref ref) =>
    DispatchCapabilityDeclarer(
      declare: () =>
          ref.read(deliveryRepositoryProvider).declareDispatchCapability(),
    );
