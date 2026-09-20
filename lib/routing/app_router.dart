import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/presentation/screens/sign_in_screen.dart';
import '../features/deliveries/presentation/screens/delivery_detail_screen.dart'
    show DeliveryDetailScreen, FullscreenDriverMapScreen;
import '../features/deliveries/presentation/screens/history_screen.dart';
import '../features/deliveries/presentation/screens/missions_screen.dart';
import '../features/profile/application/profile_controller.dart';
import '../features/profile/presentation/screens/profile_screen.dart';

part 'app_router.g.dart';

@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final authState = ref.watch(authStateChangeProvider);

  return GoRouter(
    redirect: (context, state) {
      final isLoggedIn = authState.asData?.value != null;
      final isOnAuth = state.matchedLocation == '/signin';

      if (!isLoggedIn && !isOnAuth) return '/signin';
      if (isLoggedIn && isOnAuth) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/signin', builder: (_, _) => const SignInScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) =>
            _RoleGuard(child: _MainScaffold(shell: shell)),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/', builder: (_, _) => const MissionsScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/history',
                builder: (_, _) => const HistoryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (_, _) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/deliveries/:id',
        builder: (_, state) =>
            DeliveryDetailScreen(deliveryId: state.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'map',
            builder: (_, state) => FullscreenDriverMapScreen(
              deliveryId: state.pathParameters['id']!,
            ),
          ),
        ],
      ),
    ],
  );
}

/// Refuse l'application livreur aux comptes qui n'en relèvent pas.
///
/// Le routeur ne vérifiait **que** la présence d'une session Firebase :
/// n'importe quel client avec un compte e-mail/mot de passe entrait ici. Il ne
/// voyait rien — les routes sont `@Roles('LIVREUR')` côté serveur — mais il
/// obtenait une application en erreur plutôt qu'un refus lisible. Les deux
/// autres applications ont ce garde-fou depuis le début.
///
/// Trois états, et la nuance compte :
///  - profil **non encore chargé** → on laisse passer. Le chargement est
///    asynchrone ; bloquer ici ferait clignoter un refus à chaque démarrage.
///  - rôle LIVREUR → l'application.
///  - autre rôle → écran d'explication, avec la sortie.
class _RoleGuard extends ConsumerWidget {
  const _RoleGuard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileControllerProvider);
    // `asData` plutôt que `valueOrNull` : celui-ci n'existe pas sur
    // l'`AsyncValue` de riverpod_annotation utilisé ici.
    final role = profile.asData?.value.role;
    if (role == null || role == 'LIVREUR') return child;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_accounts_outlined, size: 48),
              const SizedBox(height: 16),
              Text(
                'Cette application est réservée aux livreurs.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Votre compte a le rôle $role.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () =>
                    ref.read(authControllerProvider.notifier).signOut(),
                icon: const Icon(Icons.logout),
                label: const Text('Se déconnecter'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MainScaffold extends StatelessWidget {
  final StatefulNavigationShell shell;
  const _MainScaffold({required this.shell});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: shell,
    bottomNavigationBar: NavigationBar(
      selectedIndex: shell.currentIndex,
      onDestinationSelected: shell.goBranch,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.delivery_dining),
          label: 'Missions',
        ),
        NavigationDestination(icon: Icon(Icons.history), label: 'Historique'),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          label: 'Profil',
        ),
      ],
    ),
  );
}
