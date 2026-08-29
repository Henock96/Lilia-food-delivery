import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../utilities/app_theme.dart';
import '../../data/ratings_repository.dart';

/// Les notes reçues par le livreur connecté.
///
/// Le backend sert la note et le commentaire, **sans l'identité du client** :
/// une note doit pouvoir être honnête sans exposer son auteur à la personne
/// notée. C'est aussi pour ça que l'écran n'offre aucun moyen de répondre.
class MyRatingsScreen extends ConsumerWidget {
  const MyRatingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ratingsAsync = ref.watch(myRatingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mes notes')),
      body: ratingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                const SizedBox(height: 12),
                Text('$e', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => ref.invalidate(myRatingsProvider),
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
        data: (ratings) {
          if (ratings.isEmpty) {
            return const _EmptyRatings();
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myRatingsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: ratings.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final r = ratings[i];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            ...List.generate(
                              5,
                              (s) => Icon(
                                s < r.rating
                                    ? Icons.star_rounded
                                    : Icons.star_border_rounded,
                                color: Colors.amber,
                                size: 20,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              r.shortOrderRef,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textMed,
                              ),
                            ),
                          ],
                        ),
                        if (r.comment != null && r.comment!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(r.comment!, style: const TextStyle(fontSize: 14)),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          _formatDate(r.createdAt),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  String _formatDate(DateTime d) {
    final local = d.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mi = local.minute.toString().padLeft(2, '0');
    return '$dd/$mm à $hh:$mi';
  }
}

class _EmptyRatings extends StatelessWidget {
  const _EmptyRatings();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.star_border_rounded, size: 56, color: AppColors.textLight),
            SizedBox(height: 12),
            Text(
              'Pas encore de note',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 6),
            Text(
              'Les clients peuvent vous noter après réception de leur commande.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMed),
            ),
          ],
        ),
      ),
    );
  }
}
