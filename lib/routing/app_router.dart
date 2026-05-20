import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/presentation/screens/sign_in_screen.dart';
import '../features/deliveries/presentation/screens/delivery_detail_screen.dart'
    show DeliveryDetailScreen, FullscreenDriverMapScreen;
import '../features/deliveries/presentation/screens/history_screen.dart';
import '../features/deliveries/presentation/screens/missions_screen.dart';
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
        builder: (context, state, shell) => _MainScaffold(shell: shell),
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
