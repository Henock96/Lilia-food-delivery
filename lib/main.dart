import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/deliveries/application/tracking_resume_service.dart';
import 'routing/app_router.dart';
import 'services/notification_service.dart';
import 'utilities/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
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
        ref.read(deliveryNotificationServiceProvider).init();
        ref.read(trackingResumeServiceProvider).start();
      } else {
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
