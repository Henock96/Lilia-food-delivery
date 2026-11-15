import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../models/app_user.dart';
import '../../../../models/delivery_offer.dart';
import '../../../../utilities/app_theme.dart';
import '../../../profile/application/profile_controller.dart';
import '../../application/available_deliveries_controller.dart';

/// Onglet « Disponibles » — dispatch FCFS (10/11/2026).
///
/// Les commandes prêtes proposées à tous les livreurs disponibles. Le
/// premier qui appuie sur « ACCEPTER LA LIVRAISON » et que le serveur valide
/// l'obtient ; les autres voient la carte disparaître. Distinct de Missions :
/// ici rien n'est encore à lui.
class AvailableScreen extends ConsumerWidget {
  const AvailableScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available = ref.watch(availableDeliveriesControllerProvider);
    final driverStatus = ref
        .watch(profileControllerProvider)
        .asData
        ?.value
        .driverStatus;
    final notifier = ref.read(availableDeliveriesControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Commandes disponibles',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
            onPressed: notifier.refresh,
          ),
        ],
      ),
      body: available.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Message(
          icon: Icons.wifi_off_outlined,
          title: 'Impossible de charger les commandes',
          detail: e.toString(),
          action: FilledButton(
            onPressed: notifier.refresh,
            child: const Text('Réessayer'),
          ),
        ),
        data: (data) {
          if (!data.eligible) {
            final offline = data.ineligibility == OfferIneligibility.offline;
            return _Message(
              icon: offline ? Icons.power_settings_new : Icons.info_outline,
              title: offline ? 'Vous êtes hors ligne' : 'Aucune proposition',
              detail:
                  data.ineligibility?.message ?? data.ineligibilityRaw ?? '',
              action: offline && driverStatus != DriverStatus.available
                  ? FilledButton.icon(
                      onPressed: () => ref
                          .read(profileControllerProvider.notifier)
                          .setDriverStatus(DriverStatus.available)
                          .then((_) => notifier.refresh()),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Passer disponible'),
                    )
                  : null,
            );
          }
          if (data.offers.isEmpty) {
            return RefreshIndicator(
              onRefresh: notifier.refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  _Message(
                    icon: Icons.inbox_outlined,
                    title: 'Aucune commande disponible',
                    detail:
                        'Vous serez notifié dès qu’une commande sera prête près de vous.',
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: notifier.refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: data.offers.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) => _OfferCard(
                offer: data.offers[i],
                onClaim: () => _claim(context, ref, data.offers[i]),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _claim(
    BuildContext context,
    WidgetRef ref,
    DeliveryOffer offer,
  ) async {
    final outcome = await ref
        .read(availableDeliveriesControllerProvider.notifier)
        .claim(offer.deliveryId);
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    switch (outcome) {
      case ClaimWon(:final delivery):
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Livraison acceptée ! Rendez-vous au point de retrait.',
            ),
            backgroundColor: AppColors.success,
          ),
        );
        // La mission est à lui : il n'a pas à l'accepter une seconde fois.
        context.push('/deliveries/${delivery.id}');
      case ClaimTaken(:final message):
        messenger.showSnackBar(
          SnackBar(content: Text(message), backgroundColor: AppColors.textDark),
        );
      case ClaimRefused(:final message):
        messenger.showSnackBar(
          SnackBar(content: Text(message), backgroundColor: AppColors.warning),
        );
      case ClaimFailed(:final message):
        messenger.showSnackBar(
          SnackBar(content: Text(message), backgroundColor: AppColors.error),
        );
      case ClaimIgnored():
        break;
    }
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.offer, required this.onClaim});

  final DeliveryOffer offer;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    offer.vendorType.emoji,
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        offer.restaurantName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      if (offer.restaurantQuartier != null)
                        Text(
                          offer.restaurantQuartier!,
                          style: const TextStyle(
                            color: AppColors.textMed,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  offer.orderRef,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppColors.textMed,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            _Line(
              icon: Icons.location_on_outlined,
              text: offer.deliveryQuartier != null
                  ? 'Livraison : ${offer.deliveryQuartier}'
                  : 'Quartier de livraison communiqué après acceptation',
            ),
            const SizedBox(height: 6),
            _Line(
              icon: Icons.shopping_bag_outlined,
              text:
                  '${offer.itemCount} article${offer.itemCount > 1 ? 's' : ''}'
                  ' · prête ${_since(offer.readySince)}',
            ),
            if (offer.isPreorder && offer.scheduledFor != null) ...[
              const SizedBox(height: 6),
              _Line(
                icon: Icons.event_outlined,
                text: 'Précommande pour ${_when(offer.scheduledFor!)}',
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onClaim,
                icon: const Icon(Icons.check),
                label: const Text('ACCEPTER LA LIVRAISON'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _since(DateTime? at) {
    if (at == null) return 'à l’instant';
    final m = DateTime.now().difference(at).inMinutes;
    if (m < 1) return 'à l’instant';
    if (m < 60) return 'depuis $m min';
    return 'depuis ${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')}';
  }

  static String _when(DateTime d) {
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day}/${d.month.toString().padLeft(2, '0')} à $hh:$mm';
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 16, color: AppColors.textMed),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(fontSize: 13, color: AppColors.textMed),
        ),
      ),
    ],
  );
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: AppColors.textLight),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: AppColors.textMed),
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textLight),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    ),
  );
}
