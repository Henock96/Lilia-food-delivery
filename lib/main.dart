import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'common_widgets/app_cached_image.dart';
import 'features/deliveries/application/connectivity_watcher.dart';
import 'features/deliveries/application/tracking_resume_service.dart';
import 'routing/app_router.dart';
import 'services/notification_service.dart';
import 'features/deliveries/presentation/widgets/tracking_issue_banner.dart';
import 'utilities/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Cache mémoire images plafonné à 100 MB (LIL-37).
  LiliaImageCache.configureMemoryCache();

  // DSN injecté au build via --dart-define=SENTRY_DSN=... (jamais en dur).
  // DSN vide => Sentry se désactive tout seul, l'appRunner s'exécute quand même.
  await Firebase.initializeApp();
  await initializeDateFormatting('fr_FR', null);
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  runApp(const ProviderScope(child: LiliaDeliveryApp()));
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
       
        ref.read(deliveryNotificationServiceProvider).init();
        ref.read(trackingResumeServiceProvider).start();
        ref.read(connectivityWatcherProvider).start();
      } else {
        ref.read(deliveryNotificationServiceProvider).removeToken();
        ref.read(trackingResumeServiceProvider).stop();
        ref.read(connectivityWatcherProvider).stop();
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
      // Le bandeau « le client ne vous voit pas » vit au-dessus du routeur, et
      // non dans le shell : le livreur passe sa course sur l'écran de détail,
      // poussé par-dessus les onglets. Un bandeau logé dans le shell serait
      // invisible exactement pendant les minutes où l'information compte.
      builder: (context, child) =>
          TrackingIssueBanner(child: child ?? const SizedBox.shrink()),
    );
  }
}
