import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../models/delivery.dart';
import '../../../../utilities/app_theme.dart';
import '../../application/deliveries_controller.dart';
import '../widgets/delivery_card.dart';

class MissionsScreen extends ConsumerWidget {
  const MissionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missionsAsync = ref.watch(missionsControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Mes missions',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(missionsControllerProvider.notifier).refresh(),
          ),
        ],
      ),
      body: missionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 12),
              Text(e.toString(), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () =>
                    ref.read(missionsControllerProvider.notifier).refresh(),
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
        data: (missions) => missions.isEmpty
            ? _EmptyMissions()
            : RefreshIndicator(
                onRefresh: () =>
                    ref.read(missionsControllerProvider.notifier).refresh(),
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: missions.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final delivery = missions[i];
                    return DeliveryCard(
                      delivery: delivery,
                      onTap: () => context.push('/deliveries/${delivery.id}'),
                      onAccept: delivery.status == DeliveryStatus.assigner
                          ? () => ref
                                .read(missionsControllerProvider.notifier)
                                .acceptDelivery(delivery.id)
                          : null,
                    );
                  },
                ),
              ),
      ),
    );
  }
}

class _EmptyMissions extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.inbox_outlined, size: 72, color: AppColors.textLight),
        const SizedBox(height: 16),
        Text(
          'Aucune mission en cours',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: AppColors.textMed),
        ),
        const SizedBox(height: 8),
        Text(
          'Passez en mode disponible pour recevoir des livraisons',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.textLight),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}
