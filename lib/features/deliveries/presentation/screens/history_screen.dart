import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../utilities/app_theme.dart';
import '../../application/deliveries_controller.dart';
import '../widgets/delivery_card.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(deliveriesHistoryControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Historique',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref
                .read(deliveriesHistoryControllerProvider.notifier)
                .refresh(),
          ),
        ],
      ),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(e.toString(), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref
                    .read(deliveriesHistoryControllerProvider.notifier)
                    .refresh(),
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
        data: (deliveries) => deliveries.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.history, size: 72, color: AppColors.textLight),
                    const SizedBox(height: 16),
                    Text(
                      'Aucune livraison effectuée',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.textMed,
                      ),
                    ),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: () => ref
                    .read(deliveriesHistoryControllerProvider.notifier)
                    .refresh(),
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: deliveries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final d = deliveries[i];
                    return DeliveryCard(
                      delivery: d,
                      onTap: () => context.push('/deliveries/${d.id}'),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
