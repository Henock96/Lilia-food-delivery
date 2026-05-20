import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'features/deliveries/application/tracking_resume_service.dart';
import 'routing/app_router.dart';
import 'services/notification_service.dart';
import 'utilities/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // DSN injecté au build via --dart-define=SENTRY_DSN=... (jamais en dur).
  // DSN vide => Sentry se désactive tout seul, l'appRunner s'exécute quand même.
  await SentryFlutter.init(
    (options) {
      options.dsn = const String.fromEnvironment('SENTRY_DSN');
      options.environment = const String.fromEnvironment(
        'SENTRY_ENV',
        defaultValue: 'production',
      );
      options.tracesSampleRate = 0.1;
      // Profiling Sentry Flutter encore en bêta — API stable en pratique.
      // ignore: experimental_member_use
      options.profilesSampleRate = 0.1;
    },
    appRunner: () async {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      runApp(const ProviderScope(child: LiliaDeliveryApp()));
    },
  );
}

class LiliaDeliveryApp extends ConsumerStatefulWidget {
  const LiliaDeliveryApp({super.key});

  @override
  ConsumerState<LiliaDeliveryApp> createState() => _LiliaDeliveryAppState();
}

class _LiliaDeliveryAppState extends ConsumerState<LiliaDeliveryApp> {
  @override
  void initState() {
    super.initState();
    // Initialise les notifications + auto-resume tracking dès qu'un livreur est connecté
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        // Associe les erreurs Sentry au livreur connecté (rôle constant LIVREUR).
        Sentry.configureScope(
          (scope) => scope.setUser(
            SentryUser(
              id: user.uid,
              email: user.email,
              data: const {'role': 'LIVREUR'},
            ),
          ),
        );
        ref.read(deliveryNotificationServiceProvider).init();
        ref.read(trackingResumeServiceProvider).start();
      } else {
        Sentry.configureScope((scope) => scope.setUser(null));
        ref.read(deliveryNotificationServiceProvider).removeToken();
        ref.read(trackingResumeServiceProvider).stop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Lilia Food Livreur',
      theme: AppTheme.theme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
