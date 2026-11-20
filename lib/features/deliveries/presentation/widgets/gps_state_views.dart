import 'package:flutter/material.dart';

import '../../../../utilities/app_theme.dart';
import '../../application/driver_gps_watcher.dart';

IconData _gpsStateIcon(MapGpsState state) => switch (state) {
  MapGpsState.acquiring || MapGpsState.live => Icons.location_searching,
  MapGpsState.weakSignal => Icons.gps_not_fixed,
  MapGpsState.serviceDisabled => Icons.location_disabled,
  MapGpsState.denied || MapGpsState.deniedForever => Icons.location_off,
  MapGpsState.streamFailed => Icons.error_outline,
};

/// Carte sans aucun point à montrer (ni le livreur, ni la destination).
///
/// Remplace « Acquisition du signal GPS… », affiché indéfiniment quand la
/// localisation était coupée ou que le flux avait échoué (audit du 18/11).
class GpsStatePlaceholder extends StatelessWidget {
  const GpsStatePlaceholder({
    super.key,
    required this.state,
    required this.onAction,
  });

  final MapGpsState state;
  final ValueChanged<MapGpsAction> onAction;

  @override
  Widget build(BuildContext context) {
    final label = state.actionLabel;
    return Container(
      color: const Color(0xFFF5F5F5),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_gpsStateIcon(state), size: 40, color: AppColors.textLight),
            const SizedBox(height: 8),
            Text(
              state.message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMed, fontSize: 13),
            ),
            if (label != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => onAction(state.action),
                child: Text(label),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Bandeau posé sur la carte quand la position du livreur manque : la carte
/// reste utilisable (destination), le livreur sait pourquoi il n'y figure pas.
class GpsStatusStrip extends StatelessWidget {
  const GpsStatusStrip({
    super.key,
    required this.state,
    required this.onAction,
  });

  final MapGpsState state;
  final ValueChanged<MapGpsAction> onAction;

  @override
  Widget build(BuildContext context) {
    final label = state.actionLabel;
    return Material(
      color: Colors.white,
      elevation: 2,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            Icon(_gpsStateIcon(state), size: 18, color: AppColors.warning),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                state.message,
                style: const TextStyle(fontSize: 12, color: AppColors.textMed),
              ),
            ),
            if (label != null)
              TextButton(
                onPressed: () => onAction(state.action),
                child: Text(label),
              ),
          ],
        ),
      ),
    );
  }
}
