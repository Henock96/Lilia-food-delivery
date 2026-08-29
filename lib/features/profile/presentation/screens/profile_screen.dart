import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../common_widgets/app_cached_image.dart';
import '../../../../models/app_user.dart';
import '../../../../utilities/app_theme.dart';
import '../../../auth/application/auth_controller.dart';
import '../../application/profile_controller.dart';
import '../../data/ratings_repository.dart';
import 'my_ratings_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Mon profil',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (user) => _ProfileBody(user: user),
      ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  final AppUser user;
  const _ProfileBody({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Avatar (image réseau cachée — LIL-37)
          AppCachedAvatar(
            imageUrl: user.imageUrl,
            radius: 48,
            fallback: Text(
              user.nom.isNotEmpty ? user.nom[0].toUpperCase() : 'L',
              style: const TextStyle(
                fontSize: 36,
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            user.nom,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (user.phone != null)
            Text(user.phone!, style: const TextStyle(color: AppColors.textMed)),
          const SizedBox(height: 12),

          // Note moyenne : le livreur est noté par les clients depuis le
          // 29/08, mais il ne pouvait pas voir sa note — une notation que le
          // noté ignore n'a aucun effet sur la qualité de service.
          _RatingSummaryTile(delivererId: user.id),
          const SizedBox(height: 24),

          // Driver status toggle
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.wifi_tethering, color: AppColors.primary),
                      SizedBox(width: 8),
                      Text(
                        'Statut de disponibilité',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _DriverStatusSelector(
                    currentStatus: user.driverStatus ?? DriverStatus.offline,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Info card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _InfoTile(
                    icon: Icons.badge_outlined,
                    label: 'Rôle',
                    value: 'Livreur',
                  ),
                  const Divider(),
                  _InfoTile(
                    icon: Icons.circle,
                    label: 'Statut compte',
                    value: 'Actif',
                    iconColor: AppColors.success,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Sign out
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).signOut(),
              icon: const Icon(Icons.logout, color: AppColors.error),
              label: const Text(
                'Se déconnecter',
                style: TextStyle(color: AppColors.error),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.error),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverStatusSelector extends ConsumerWidget {
  final DriverStatus currentStatus;
  const _DriverStatusSelector({required this.currentStatus});

  Color _color(DriverStatus s) => switch (s) {
    DriverStatus.available => AppColors.success,
    DriverStatus.on_delivery => AppColors.primary,
    DriverStatus.offline => AppColors.textLight,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: DriverStatus.values.map((status) {
        final selected = currentStatus == status;
        final color = _color(status);
        return Expanded(
          child: GestureDetector(
            onTap: selected
                ? null
                : () => ref
                      .read(profileControllerProvider.notifier)
                      .setDriverStatus(status),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: selected ? color : color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? color : color.withValues(alpha: 0.2),
                ),
              ),
              child: Text(
                status.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? Colors.white : color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color iconColor;
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor = AppColors.textMed,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(color: AppColors.textMed)),
        const Spacer(),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
      ],
    ),
  );
}


/// Note moyenne du livreur + accès à l'historique de ses avis.
///
/// Affiche « Pas encore noté » plutôt que 0 tant qu'aucun client n'a voté :
/// un livreur qui débute n'est pas un livreur mal noté.
class _RatingSummaryTile extends ConsumerWidget {
  const _RatingSummaryTile({required this.delivererId});

  final String delivererId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(myRatingSummaryProvider(delivererId));

    return summaryAsync.maybeWhen(
      // Une note indisponible ne doit pas trouer le profil.
      orElse: () => const SizedBox.shrink(),
      data: (summary) => Card(
        child: ListTile(
          leading: Icon(
            Icons.star_rounded,
            color: summary.hasRatings ? Colors.amber : AppColors.textLight,
            size: 32,
          ),
          title: Text(
            summary.hasRatings
                ? '${summary.average!.toStringAsFixed(1)} / 5'
                : 'Pas encore noté',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            summary.hasRatings
                ? '${summary.total} avis client${summary.total > 1 ? 's' : ''}'
                : 'Vos notes apparaîtront ici',
            style: const TextStyle(fontSize: 12),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const MyRatingsScreen(),
            ),
          ),
        ),
      ),
    );
  }
}
