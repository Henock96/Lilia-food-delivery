import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../models/driver_earnings.dart';
import '../../../../utilities/app_theme.dart';
import '../../../deliveries/data/delivery_repository.dart';

/// Ce que le livreur a gagné, et ce qu'il a reçu.
///
/// ## Ce que cet écran doit dire, et que l'application ne disait pas
///
/// Jusqu'ici, rien n'indiquait au livreur sa rémunération : ses écrans
/// n'affichaient que le total des commandes, c'est-à-dire l'argent du client,
/// dont l'essentiel revient au vendeur.
///
/// ## Ce qu'il ne doit PAS laisser croire
///
/// Qu'un virement va partir tout seul. Aucun paiement n'est déclenché par
/// l'application : l'argent est remis hors système, en espèces ou par un
/// transfert fait à la main. L'écran l'écrit noir sur blanc — un livreur qui
/// attendrait un virement automatique attendrait indéfiniment.
class MyEarningsScreen extends ConsumerWidget {
  const MyEarningsScreen({super.key});

  static String _xaf(int amount) =>
      '${NumberFormat.decimalPattern('fr').format(amount)} XAF';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outstanding = ref.watch(myOutstandingProvider);
    final settlements = ref.watch(mySettlementsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mes gains')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myOutstandingProvider);
          ref.invalidate(mySettlementsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            outstanding.when(
              loading: () =>
                  const Center(child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  )),
              error: (e, _) => _ErrorBox(
                message: '$e',
                onRetry: () => ref.invalidate(myOutstandingProvider),
              ),
              data: (due) => _OutstandingCard(due: due),
            ),
            const SizedBox(height: 24),
            Text(
              'Versements reçus',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            settlements.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => _ErrorBox(
                message: '$e',
                onRetry: () => ref.invalidate(mySettlementsProvider),
              ),
              data: (list) => list.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Aucun versement enregistré pour le moment.',
                        style: TextStyle(color: AppColors.textMed),
                      ),
                    )
                  : Column(
                      children: list
                          .map((s) => _SettlementTile(settlement: s))
                          .toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutstandingCard extends StatelessWidget {
  const _OutstandingCard({required this.due});

  final DriverOutstanding due;

  @override
  Widget build(BuildContext context) {
    final nothing = due.courseCount == 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Reste à vous verser',
              style: TextStyle(color: AppColors.textMed, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              MyEarningsScreen._xaf(due.amountXaf),
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              nothing
                  ? 'Aucune course en attente de règlement.'
                  : '${due.courseCount} course${due.courseCount > 1 ? 's' : ''} '
                        'non encore réglée${due.courseCount > 1 ? 's' : ''}.',
              style: const TextStyle(color: AppColors.textMed, fontSize: 13),
            ),
            const SizedBox(height: 12),
            // ⚠️ La phrase qui évite une attente infinie. Sans elle, ce montant
            // se lit comme un virement à venir.
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Ce montant vous est remis directement par Lilia Food — en '
                'espèces ou par transfert. Aucun virement automatique n’est '
                'déclenché depuis l’application.',
                style: TextStyle(fontSize: 12, color: AppColors.textMed),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettlementTile extends StatelessWidget {
  const _SettlementTile({required this.settlement});

  final DriverSettlement settlement;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('d MMM y', 'fr').format(settlement.paidAt);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        settlement.cancelled
            ? Icons.cancel_outlined
            : Icons.check_circle_outline,
        color: settlement.cancelled ? AppColors.textMed : AppColors.success,
      ),
      title: Text(
        MyEarningsScreen._xaf(settlement.amountXaf),
        style: TextStyle(
          fontWeight: FontWeight.bold,
          // Barré plutôt que masqué : un versement qui disparaîtrait de
          // l'historique inquiéterait à raison. Les courses correspondantes
          // sont redevenues dues, et elles réapparaissent dans le montant
          // ci-dessus.
          decoration: settlement.cancelled ? TextDecoration.lineThrough : null,
          color: settlement.cancelled ? AppColors.textMed : AppColors.textDark,
        ),
      ),
      subtitle: Text(
        '$date · ${settlement.method.label} · '
        '${settlement.courseCount} course${settlement.courseCount > 1 ? 's' : ''}'
        '${settlement.cancelled ? ' · annulé' : ''}',
        style: const TextStyle(fontSize: 12, color: AppColors.textMed),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        const Icon(Icons.error_outline, size: 40, color: AppColors.error),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        ElevatedButton(onPressed: onRetry, child: const Text('Réessayer')),
      ],
    ),
  );
}
