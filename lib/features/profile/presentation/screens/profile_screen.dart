import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../common_widgets/app_cached_image.dart';
import '../../../../models/app_user.dart';
import '../../../../utilities/app_theme.dart';
import '../../../auth/application/auth_controller.dart';
import '../../application/profile_controller.dart';
import '../../data/ratings_repository.dart';
import 'my_earnings_screen.dart';
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
    final profile = user.driverProfile;
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
          const SizedBox(height: 12),

          // Accès à la rémunération. Placé sur le profil et non dans les
          // missions : c'est une information sur LUI, pas sur une course.
          Card(
            child: ListTile(
              leading: const Icon(
                Icons.account_balance_wallet_outlined,
                color: AppColors.primary,
              ),
              title: const Text(
                'Mes gains',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'Ce qui vous reste dû et vos versements',
                style: TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const MyEarningsScreen(),
                ),
              ),
            ),
          ),
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

          // Bandeau d'explication quand le livreur ne peut PAS recevoir de
          // course. Sans lui, une liste de missions vide est indiscernable
          // d'une journée creuse : le livreur attend sans savoir qu'il attend
          // pour rien.
          if (!user.canReceiveMissions) ...[
            _BlockedBanner(user: user),
            const SizedBox(height: 12),
          ],

          // Informations professionnelles — vides jusqu'à septembre 2026 :
          // l'écran ne montrait que « Rôle : Livreur » et un « Statut compte :
          // Actif » écrit en dur, affiché tel quel même sur un compte suspendu.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.badge_outlined, color: AppColors.primary),
                      SizedBox(width: 8),
                      Text(
                        'Informations professionnelles',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (profile == null)
                    const Text(
                      'Profil non renseigné. Contactez l\'administration : sans '
                      'profil livreur, aucune course ne peut vous être confiée.',
                      style: TextStyle(color: AppColors.textMed, fontSize: 13),
                    )
                  else ...[
                    _InfoTile(
                      icon: Icons.two_wheeler_outlined,
                      label: 'Véhicule',
                      value: profile.vehicleType.label,
                    ),
                    if (profile.plateNumber != null) ...[
                      const Divider(),
                      _InfoTile(
                        icon: Icons.confirmation_number_outlined,
                        label: 'Immatriculation',
                        value: profile.plateNumber!,
                      ),
                    ],
                    if (profile.licenseNumber != null) ...[
                      const Divider(),
                      _InfoTile(
                        icon: Icons.card_membership_outlined,
                        label: 'Permis',
                        value: profile.licenseNumber!,
                      ),
                    ],
                    if (profile.licenseExpiry != null) ...[
                      const Divider(),
                      _InfoTile(
                        icon: Icons.event_outlined,
                        label: 'Expiration du permis',
                        value: _formatDate(profile.licenseExpiry!),
                        // Alerte 30 jours avant : le livreur est le mieux placé
                        // pour renouveler, encore faut-il le prévenir avant
                        // qu'une course lui soit refusée.
                        iconColor: profile.licenseExpiringSoon
                            ? AppColors.error
                            : AppColors.textMed,
                      ),
                    ],
                    const Divider(),
                    _InfoTile(
                      icon: Icons.map_outlined,
                      label: 'Zone',
                      value: profile.zones.isEmpty
                          ? 'Toute la ville'
                          : profile.zones.join(', '),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Les TROIS statuts, séparément.
          //
          // Ils portent sur trois objets différents et sont décidés par trois
          // acteurs : le compte par l'administration, le profil par
          // l'administration également, la disponibilité par le livreur.
          // « Compte actif, profil actif, hors ligne » décrit quelqu'un qui a
          // fini sa journée — ce n'est ni une anomalie ni une sanction, et les
          // fondre en un seul « statut » obligerait à choisir lequel ment.
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
                    label: 'Statut du compte',
                    value: user.statusUser.label,
                    iconColor: user.statusUser.isUsable
                        ? AppColors.success
                        : AppColors.error,
                  ),
                  const Divider(),
                  _InfoTile(
                    icon: Icons.verified_outlined,
                    label: 'Profil livreur',
                    value: profile == null
                        ? 'Non renseigné'
                        : (profile.isActive ? 'Actif' : 'Inactif'),
                    iconColor: (profile?.isActive ?? false)
                        ? AppColors.success
                        : AppColors.error,
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

/// Explique pourquoi la liste de missions restera vide.
///
/// Le serveur refuse d'assigner une course à un livreur dont le compte est
/// suspendu ou le profil hors service (`assertAssignable`). Sans ce bandeau,
/// l'application se contente d'une liste vide : le livreur attend une mission
/// qui ne viendra jamais, sans qu'aucun écran ne le lui dise.
class _BlockedBanner extends StatelessWidget {
  final AppUser user;
  const _BlockedBanner({required this.user});

  @override
  Widget build(BuildContext context) {
    final compteHS = !user.statusUser.isUsable;
    final message = compteHS
        ? 'Votre compte est ${user.statusUser.label.toLowerCase()}. '
              'Contactez l\'administration Lilia Food.'
        : user.driverProfile == null
        ? 'Votre profil livreur n\'est pas encore créé. '
              'Aucune course ne peut vous être confiée.'
        : 'Votre profil livreur est inactif. '
              'Contactez l\'administration pour le réactiver.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
