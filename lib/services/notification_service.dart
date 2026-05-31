import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../constants/app_constants.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/deliveries/application/deliveries_controller.dart';

part 'notification_service.g.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  if (message.notification != null) {
    final plugin = FlutterLocalNotificationsPlugin();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await plugin.initialize(
      settings: const InitializationSettings(android: android),
    );

    await plugin.show(
      id: message.notification.hashCode,
      title: message.notification!.title,
      body: message.notification!.body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel',
          'Notifications Commandes',
          channelDescription: 'Notifications pour les nouvelles missions.',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }
}

class DeliveryNotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  final AuthRepository _authRepo;
  final Ref _ref;

  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  StreamSubscription<String>? _tokenRefreshSub;
  bool _initialized = false;
  bool _disposed = false;

  String? fcmToken;

  DeliveryNotificationService(this._authRepo, this._ref);

  Future<void> init() async {
    if (_disposed || _initialized) return;
    _initialized = true;
    try {
      await _initLocalNotifications();
      await _requestPermission();
      _setupHandlers();

      try {
        fcmToken = await _fcm.getToken();
      } on FirebaseException catch (e) {
        if (e.code == 'apns-token-not-set') {
          debugPrint('APNS non disponible (simulateur), FCM skippé');
          return;
        }
        rethrow;
      }

      if (fcmToken != null) await _registerToken();

      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub = _fcm.onTokenRefresh.listen((newToken) {
        if (_disposed) return;
        fcmToken = newToken;
        _registerToken();
      });

      final initial = await _fcm.getInitialMessage();
      if (initial != null) _handleData(initial.data);
    } catch (e) {
      _initialized = false;
      debugPrint('NotificationService init error: $e');
    }
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
            _handleData(jsonDecode(r.payload!));
          } catch (_) {}
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
      _handleData(msg.data);
      if (msg.notification != null) {
        _showLocal(msg);
      }
    });

    _openedSub = FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      _handleData(msg.data);
    });
  }

  void _handleData(Map<String, dynamic> data) {
    // Nouvelle mission assignée → rafraîchir la liste
    if (data['type'] == 'new_mission' || data.containsKey('deliveryId')) {
      _ref.read(missionsControllerProvider.notifier).refresh();
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

  Future<void> _registerToken({int maxRetries = 3}) async {
    if (fcmToken == null) return;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final idToken = await _authRepo.getIdToken();
        if (idToken == null) return;
        final response = await http
            .post(
              Uri.parse('${AppConstants.baseUrl}/notifications/register-token'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $idToken',
              },
              body: jsonEncode({'token': fcmToken}),
            )
            .timeout(const Duration(seconds: 35));
        if (response.statusCode == 200 || response.statusCode == 201) return;
        debugPrint(
          'FCM register failed (attempt $attempt/$maxRetries): ${response.statusCode}',
        );
      } catch (e) {
        debugPrint(
          'Erreur enregistrement FCM token (attempt $attempt/$maxRetries): $e',
        );
        if (attempt == maxRetries) return;
        await Future.delayed(Duration(seconds: attempt * 15));
      }
    }
  }

  Future<void> removeToken() async {
    if (fcmToken == null) return;
    try {
      final idToken = await _authRepo.getIdToken();
      if (idToken == null) return;
      await http
          .delete(
            Uri.parse('${AppConstants.baseUrl}/notifications/token'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({'token': fcmToken}),
          )
          .timeout(const Duration(seconds: 15));
      fcmToken = null;
    } catch (_) {}
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _foregroundSub?.cancel();
    _openedSub?.cancel();
    _tokenRefreshSub?.cancel();
  }
}

@Riverpod(keepAlive: true)
DeliveryNotificationService deliveryNotificationService(Ref ref) {
  final svc = DeliveryNotificationService(
    ref.watch(authRepositoryProvider),
    ref,
  );
  ref.onDispose(svc.dispose);
  return svc;
}
