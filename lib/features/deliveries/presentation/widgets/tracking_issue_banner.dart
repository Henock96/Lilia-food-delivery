import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../utilities/app_theme.dart';
import '../../application/location_service.dart';
import '../../application/tracking_issue.dart';

/// Bandeau d'alerte : la position du livreur ne part plus.
///
/// Monté **au-dessus du routeur**, pas dans un écran : le livreur passe sa
/// course sur l'écran de détail, poussé par-dessus le shell. Un bandeau logé
/// dans le shell y serait invisible — c'est-à-dire absent exactement pendant
/// les vingt minutes où l'information compte.
///
/// Il ne se ferme pas à la main, et c'est délibéré. Le problème dure tant que
/// la localisation est coupée ; un bandeau qu'on peut écarter finit écarté,
/// et l'on se retrouve avec la panne silencieuse qu'on cherchait à rendre
/// visible. Il disparaît seul quand le suivi repart.
class TrackingIssueBanner extends ConsumerStatefulWidget {
  const TrackingIssueBanner({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<TrackingIssueBanner> createState() =>
      _TrackingIssueBannerState();
}

class _TrackingIssueBannerState extends ConsumerState<TrackingIssueBanner> {
  bool _busy = false;

  /// L'action utile dépend du motif : redemander l'autorisation ne sert à rien
  /// si c'est le GPS de l'appareil qui est éteint, et l'système ne repropose
  /// plus la boîte de dialogue après un refus définitif.
  String _actionLabel(LocationDenialReason? reason) => switch (reason) {
    LocationDenialReason.serviceDisabled => 'Activer',
    LocationDenialReason.deniedForever => 'Réglages',
    _ => 'Autoriser',
  };

  Future<void> _resolve(TrackingIssue issue) async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final location = ref.read(locationServiceProvider);

      switch (issue.reason) {
        // Le GPS de l'appareil est éteint : aucune permission applicative ne
        // peut y remédier, il faut passer par les réglages du téléphone.
        case LocationDenialReason.serviceDisabled:
          await Geolocator.openLocationSettings();

        // Refus définitif : Android et iOS ne réaffichent plus la demande.
        // La fiche de l'application est le seul chemin.
        case LocationDenialReason.deniedForever:
          await Geolocator.openAppSettings();

        // Refus ponctuel : on peut redemander sur place.
        case LocationDenialReason.denied:
        case null:
          break;
      }

      // Dans tous les cas on revérifie : le livreur revient des réglages, ou
      // vient d'accepter la demande. C'est ce contrôle qui fait disparaître le
      // bandeau — jamais un geste de fermeture.
      final permission = await location.requestPermissionDetailed();
      if (!mounted) return;

      if (permission.granted) {
        ref.read(trackingIssueControllerProvider.notifier).clear();
      } else {
        // Toujours refusé : on met à jour le motif, qui a pu changer (un refus
        // ponctuel devient définitif au second rejet).
        ref
            .read(trackingIssueControllerProvider.notifier)
            .report(permission, deliveryId: issue.deliveryId);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(permission.message),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final issue = ref.watch(trackingIssueControllerProvider);

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: [
            if (issue != null)
              SafeArea(
                bottom: false,
                child: _Banner(
                  message: issue.message,
                  actionLabel: _actionLabel(issue.reason),
                  busy: _busy,
                  onAction: () => _resolve(issue),
                ),
              ),
            Expanded(child: widget.child),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.message,
    required this.actionLabel,
    required this.busy,
    required this.onAction,
  });

  final String message;
  final String actionLabel;
  final bool busy;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.error,
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.location_off, color: Colors.white, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Le titre dit la conséquence, pas la cause technique : ce qui
                // décide un livreur à agir, c'est de savoir que son client ne
                // le voit pas — pas qu'une permission est à `deniedForever`.
                const Text(
                  'Le client ne vous voit pas',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          busy
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                )
              : TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.error,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: Text(
                    actionLabel,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
        ],
      ),
    );
  }
}
