import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../core/network/api_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../features/deliveries/application/deliveries_controller.dart';
import '../routing/app_router.dart';
import 'fcm_token_registrar.dart';
import 'notification_router.dart';

part 'notification_service.g.dart';

/// ⚠️ Ne PAS y afficher de notification locale. Le backend envoie toujours un
/// bloc `notification` (`notifications.service.ts`) et l'app déclare
/// `default_notification_channel_id` dans son manifest : Android affiche donc
/// déjà la notification tout seul quand l'app est en arrière-plan. Un `show()`
/// ici en produisait une seconde, identique.
///
/// Ce handler tourne dans un isolate séparé : il n'a accès ni au ProviderScope
/// ni au router. Le rafraîchissement des missions se fait au retour au premier
/// plan (`onMessageOpenedApp` / `getInitialMessage`).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('Message FCM reçu en arrière-plan: ${message.data}');
}

class DeliveryNotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  final FcmTokenRegistrar _registrar;
  final Ref _ref;
  static const NotificationRouter _router = NotificationRouter();

  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  StreamSubscription<String>? _tokenRefreshSub;
  bool _disposed = false;

  /// Token FCM effectivement enregistré côté serveur (`null` hors session).
  String? get fcmToken => _registrar.token;

  DeliveryNotificationService(this._registrar, this._ref);

  Future<void> init() async {
    // La garde de session vit dans le registrar : `removeToken()` la réarme,
    // pour qu'une reconnexion sans redémarrage de l'app réenregistre bien un
    // token.
    if (_disposed || !_registrar.beginSession()) return;
    try {
      await _initLocalNotifications();
      await _requestPermission();
      _setupHandlers();

      final token = await _fetchFcmToken();
      if (token != null) await _registrar.register(token);

      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub = _fcm.onTokenRefresh.listen((newToken) {
        if (_disposed) return;
        _registrar.register(newToken);
      });

      final initial = await _fcm.getInitialMessage();
      // L'app a été lancée en tapant la notification : la navigation est bien
      // voulue par le livreur.
      if (initial != null) {
        _handleData(initial.data, NotificationTrigger.tap);
      }
    } catch (e) {
      // Referme la session pour qu'un init ultérieur puisse retenter.
      await _registrar.remove();
      debugPrint('NotificationService init error: $e');
    }
  }

  /// Récupère le token FCM en attendant d'abord le token APNS sur iOS.
  ///
  /// L'enregistrement APNS est **asynchrone** : au premier lancement, il n'est
  /// pas encore terminé quand `init()` s'exécute. Appeler `getToken()` tout de
  /// suite lève `apns-token-not-set`, et l'ancienne version abandonnait
  /// définitivement — le livreur restait sans token FCM pour toute la session,
  /// donc sans aucune mission poussée.
  ///
  /// Renvoie `null` quand APNS est réellement indisponible (simulateur iOS).
  Future<String?> _fetchFcmToken({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final deadline = DateTime.now().add(timeout);
    var attempt = 0;

    while (DateTime.now().isBefore(deadline)) {
      attempt++;
      try {
        return await _fcm.getToken();
      } on FirebaseException catch (e) {
        if (e.code != 'apns-token-not-set') rethrow;
        // APNS pas encore prêt : on retente jusqu'à l'échéance.
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }

    debugPrint(
      '⚠️ Token APNS indisponible après $attempt tentatives '
      '(${timeout.inSeconds}s). Simulateur iOS, ou entitlement '
      '`aps-environment` absent de la config de build. Aucun push ne sera reçu.',
    );
    return null;
  }

  Future<void> _initLocalNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _local.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (r) {
        if (r.payload != null) {
          try {
            _handleData(
              Map<String, dynamic>.from(jsonDecode(r.payload!) as Map),
              NotificationTrigger.tap,
            );
          } catch (_) {
            // Payload non-JSON : on ignore (notif sans données exploitables).
          }
        }
      },
    );
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            'high_importance_channel',
            'Notifications Commandes',
            description: 'Notifications pour les nouvelles missions.',
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
          ),
        );
  }

  Future<void> _requestPermission() async {
    await _fcm.requestPermission(alert: true, badge: true, sound: true);
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  void _setupHandlers() {
    _foregroundSub?.cancel();
    _openedSub?.cancel();

    _foregroundSub = FirebaseMessaging.onMessage.listen((msg) {
      // Trigger foreground : on recharge les missions, mais on ne déplace pas
      // le livreur — il est peut-être en pleine course.
      _handleData(msg.data, NotificationTrigger.foreground);
      if (msg.notification != null) {
        _showLocal(msg);
      }
    });

    _openedSub = FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      _handleData(msg.data, NotificationTrigger.tap);
    });
  }

  /// Applique l'action décidée par [NotificationRouter] (couvert par
  /// `test/services/notification_router_test.dart`).
  void _handleData(Map<String, dynamic> data, NotificationTrigger trigger) {
    if (_disposed) return;

    final action = _router.resolve(data, trigger: trigger);
    if (action == NotificationAction.none) return;

    switch (action.refresh) {
      case NotificationTarget.missions:
        _ref.read(missionsControllerProvider.notifier).refresh();
      case null:
        break;
    }

    final route = action.route;
    if (route == null) return;

    // `push` empile par dessus l'écran courant : le livreur peut revenir à ce
    // qu'il faisait.
    try {
      _ref.read(appRouterProvider).push(route);
    } catch (e) {
      debugPrint('Erreur navigation notification ($route): $e');
    }
  }

  String _buildNotifTitle(RemoteMessage message) {
    final data = message.data;
    final fallbackTitle = message.notification?.title ?? 'Nouvelle mission';

    final isPreorder = data['isPreorder'] == 'true';
    final scheduledForStr = data['scheduledFor'] as String? ?? '';
    final scheduledFor = DateTime.tryParse(scheduledForStr);

    if (isPreorder && scheduledFor != null) {
      return '📅 Pré-commande à récupérer le ${_formatDateFr(scheduledFor)}';
    }
    return fallbackTitle;
  }

  String _formatDateFr(DateTime utc) {
    final local = utc.toLocal();
    const days = [
      'Dimanche', 'Lundi', 'Mardi', 'Mercredi',
      'Jeudi', 'Vendredi', 'Samedi',
    ];
    const months = [
      'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
      'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
    ];
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${days[local.weekday % 7]} ${local.day} ${months[local.month - 1]} à $hh:$mm';
  }

  void _showLocal(RemoteMessage msg) {
    _local.show(
      id: msg.notification.hashCode,
      title: _buildNotifTitle(msg),
      body: msg.notification?.body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel',
          'Notifications Commandes',
          channelDescription: 'Notifications pour les nouvelles missions.',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          playSound: true,
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: jsonEncode(msg.data),
    );
  }

  /// Purge le token côté serveur au logout et réarme la session, pour qu'une
  /// reconnexion dans la même session d'app réenregistre bien un token.
  Future<void> removeToken() => _registrar.remove();

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _foregroundSub?.cancel();
    _openedSub?.cancel();
    _tokenRefreshSub?.cancel();
  }
}

@Riverpod(keepAlive: true)
FcmTokenRegistrar fcmTokenRegistrar(Ref ref) =>
    FcmTokenRegistrar(ref.watch(apiClientProvider));

@Riverpod(keepAlive: true)
DeliveryNotificationService deliveryNotificationService(Ref ref) {
  final svc = DeliveryNotificationService(
    ref.watch(fcmTokenRegistrarProvider),
    ref,
  );
  ref.onDispose(svc.dispose);
  return svc;
}
