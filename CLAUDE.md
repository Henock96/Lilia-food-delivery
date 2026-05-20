# CLAUDE.md — Lilia Food Delivery (App Livreur)

App mobile Flutter pour les **livreurs** de la plateforme Lilia Food (Brazzaville, Congo). Rôle Firebase `LIVREUR`.

**Backend URL** : `https://lilia-backend.onrender.com`
**Org** : `com.dreesis`

## Écosystème

| Composant | Stack | Dossier |
|-----------|-------|---------|
| Backend API | NestJS + Prisma | `lilia-backend/` |
| Client mobile | Flutter + Riverpod | `lilia-app/` |
| Admin dashboard | Flutter + Riverpod | `lilia-food-admin/` |
| **App livreur** | **Flutter + Riverpod** | **`lilia_food_delivery/`** |

---

## Commandes essentielles

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
dart run build_runner watch --delete-conflicting-outputs
flutter run
flutter analyze
```

---

## Architecture

```
lib/
├── features/
│   ├── auth/
│   │   ├── data/auth_repository.dart            # Firebase Auth + getIdToken
│   │   ├── application/auth_controller.dart     # signIn/signOut
│   │   └── presentation/sign_in_screen.dart
│   ├── deliveries/
│   │   ├── data/delivery_repository.dart            # Tous les /deliveries/*
│   │   ├── application/
│   │   │   ├── deliveries_controller.dart           # missions / history / detail / accept / status
│   │   │   ├── tracking_socket_service.dart         # Socket.io /tracking (push position WS)
│   │   │   ├── tracking_resume_service.dart         # Lifecycle observer (auto-resume)
│   │   │   └── location_service.dart                # Timer 5s (WS) + fallback HTTP 15s
│   │   └── presentation/
│   │       ├── screens/missions_screen, delivery_detail_screen, history_screen
│   │       └── widgets/delivery_card.dart
│   ├── notifications/                           # Local notifs + history
│   └── profile/
│       ├── application/profile_controller.dart  # getMe + setDriverStatus
│       └── presentation/profile_screen.dart
├── models/
│   ├── delivery.dart                            # Delivery + DeliveryStatus enum
│   ├── order.dart                               # DeliveryOrder, DeliveryRestaurant, OrderItem, DeliveryAddress
│   └── app_user.dart                            # AppUser + DriverStatus enum
├── routing/app_router.dart                      # go_router + auth redirect
├── services/notification_service.dart           # FCM (DeliveryNotificationService)
├── common_widgets/
├── constants/app_constants.dart                 # baseUrl
├── utilities/app_theme.dart                     # AppColors, AppTheme
└── main.dart
```

---

## Navigation (go_router)

`StatefulShellRoute` avec 3 tabs :
1. `/` → MissionsScreen (missions actives)
2. `/history` → HistoryScreen (toutes les livraisons)
3. `/profile` → ProfileScreen (statut + déconnexion)

Route détail : `/deliveries/:id` → DeliveryDetailScreen

Auth redirect : non connecté → `/signin`, connecté sur `/signin` → `/`

---

## Endpoints backend consommés

| Méthode | Endpoint | Description |
|---------|----------|-------------|
| `POST` | `/users/sync` | Sync Firebase user à la connexion |
| `GET` | `/users/me` | Profil du livreur connecté |
| `GET` | `/deliveries/mine?status=` | Mes livraisons (paginé, wrappé `{ data, count }`) |
| `GET` | `/deliveries/my-missions` | Missions actives (ASSIGNER + EN_TRANSIT) — **liste directe** |
| `GET` | `/deliveries/:id` | Détail d'une livraison — `{ data: {...} }` |
| `PATCH` | `/deliveries/:id/accept` | Accepter → EN_TRANSIT + Order → EN_ROUTE |
| `PATCH` | `/deliveries/:id/status` | Mettre à jour le statut (LIVRER, ECHEC) |
| `PATCH` | `/deliveries/:id/location` | Envoyer position GPS (toutes les 15s pendant EN_TRANSIT) |
| `PATCH` | `/deliveries/driver-status` | DriverStatus (AVAILABLE/ON_DELIVERY/OFFLINE) |
| `POST` | `/notifications/register-token` | Token FCM au login |
| `DELETE` | `/notifications/token` | Token FCM au logout |

Format Auth : `Authorization: Bearer <Firebase ID token>` sur toutes les requêtes.

---

## Statuts métier

### DeliveryStatus (livraison)
```
EN_ATTENTE  → ASSIGNER (admin/restaurateur assigne)
ASSIGNER    → EN_TRANSIT (livreur accepte → Order → EN_ROUTE)
EN_TRANSIT  → LIVRER (livraison confirmée)
EN_TRANSIT  → ECHEC (échec de livraison)
```

### DriverStatus (livreur)
```
AVAILABLE   — en attente de missions
ON_DELIVERY — en cours de livraison (auto-set à l'accept)
OFFLINE     — non disponible
```

---

## Order Flow — Côté livreur

```
1. Admin assigne via PATCH /deliveries/by-order/:orderId/assign
   → backend FCM "Nouvelle mission" arrive sur l'app livreur
2. MissionsScreen liste la mission (status ASSIGNER)
3. Livreur ouvre detail → bouton "Accepter"
   → PATCH /deliveries/:id/accept
     • Delivery → EN_TRANSIT
     • DriverStatus → ON_DELIVERY (auto)
     • Order → EN_ROUTE (backend met à jour, notifie le client)
   → LocationService.startTracking(deliveryId) côté Flutter
4. Timer 15s → Geolocator.getCurrentPosition() → PATCH /deliveries/:id/location
5. Client poll position via /deliveries/by-order/:orderId (10s) — pas de WS
6. Livreur arrive → PATCH /deliveries/:id/status { LIVRER }
   → LocationService.stopTracking
   ⚠️ Bug backend : passer par /deliveries/:id/status met Order → LIVRER
      directement sans déclencher l'event → pas de FCM client, pas de
      loyalty points crédités. (workaround : RESTAURATEUR/ADMIN doit
      PATCH /orders/:id/status pour bien déclencher)
```

---

## Tracking GPS — Architecture (mai 2026 — WebSocket)

### Vue d'ensemble

```
LocationService (Timer 5s)
  ├─ Geolocator.getCurrentPosition() — high accuracy
  ├─ 1. TrackingSocketService.emitPosition() — WebSocket Socket.io /tracking
  │    └─ event 'driver:position' { orderId, lat, lng, accuracy? }
  │    Backend → Redis GEO + broadcast à tous les watchers de la commande
  └─ 2. Fallback HTTP `PATCH /deliveries/:id/location` toutes les 15s
       (= tous les 3 ticks de 5s) — garantit l'écriture DB régulière
       même si WS marche, ou prend le relai si WS down
```

### TrackingSocketService

`lib/features/deliveries/application/tracking_socket_service.dart`

- `@Riverpod(keepAlive: true)`
- Connexion lazy (à la 1ère position envoyée)
- Auth Firebase token dans `OptionBuilder().setAuth({'token': ...})`
- Transports : `['websocket', 'polling']` (polling = fallback réseau faible Congo)
- Reconnexion auto : 10 tentatives, backoff 2s → 10s max
- `emitPosition()` retourne `bool` (false si pas connecté) → `LocationService` peut compter sur HTTP fallback

### LocationService refactor

`lib/features/deliveries/application/location_service.dart`

```dart
void startTracking({required String deliveryId, required String orderId}) {
  _ws.connect();                                  // lazy WS connect
  _timer = Timer.periodic(Duration(seconds: 5), (_) => _sendLocation());
}

// Push WS chaque 5s + HTTP fallback chaque 15s (1 sur 3 ticks)
Future<void> _sendLocation() async {
  final position = await Geolocator.getCurrentPosition(...);
  final wsSent = _ws.emitPosition(orderId, lat, lng, accuracy);
  final shouldFallbackHttp = !wsSent || (_tickCount % 3 == 0);
  if (shouldFallbackHttp) {
    await _repo.updateLocation(deliveryId, lat, lng, accuracy);
  }
}
```

### TrackingResumeService — auto-resume après lifecycle

`lib/features/deliveries/application/tracking_resume_service.dart`

- `WidgetsBindingObserver` → `didChangeAppLifecycleState(AppLifecycleState.resumed)`
- Au retour foreground (et au boot après login) :
  1. Fetch `GET /deliveries/my-missions`
  2. Filtre les missions `EN_TRANSIT`
  3. Si trouvée et tracking pas actif → `requestPermission` + `startTracking(deliveryId, orderId)`
- Démarré dans `main.dart` au login Firebase, arrêté au logout
- Garde-fou `_checking` flag

⚠️ **Toujours limité par Android/iOS** : si l'app est complètement fermée (force-stop ou tuée par OS), aucun tracking n'a lieu. Pour ça → `flutter_background_geolocation` (payant) ou foreground service Android.

### Config Google Maps requise
- Android : `android/app/src/main/AndroidManifest.xml` → remplacer `YOUR_GOOGLE_MAPS_API_KEY`
- iOS : `ios/Runner/AppDelegate.swift` → remplacer `YOUR_GOOGLE_MAPS_API_KEY`
- Maps SDK Android + iOS activés sur Google Cloud Console

### Constantes (`AppConstants`)
- `baseUrl` : `https://lilia-backend.onrender.com`
- `wsUrl` : `https://lilia-backend.onrender.com`
- `trackingNamespace` : `/tracking`

---

## Push Notifications FCM (mai 2026)

`lib/services/notification_service.dart` → `DeliveryNotificationService`

- Initialisé dans `main.dart` (après Firebase) : `ref.read(deliveryNotificationServiceProvider).init()`
- Provider : `@Riverpod(keepAlive: true) deliveryNotificationService`
- Token FCM enregistré via `POST /notifications/register-token` (retry 3x backoff 15s)
- Token supprimé au logout via `DELETE /notifications/token`
- Handler background (top-level) : `firebaseMessagingBackgroundHandler`
- `data.type == 'new_mission'` ou `data.deliveryId` → `missionsControllerProvider.notifier.refresh()`
- Canal Android : `high_importance_channel` (max + son + vibration)
- iOS simulateur : skip si `apns-token-not-set` (graceful)

**Firebase à compléter** : `android/app/google-services.json` + `ios/Runner/GoogleService-Info.plist` (même projet Firebase que `lilia-app`).

---

## Patterns Riverpod

- `@Riverpod(keepAlive: true)` pour : authRepository, httpClient, deliveryRepository, profileController, locationService, deliveryNotificationService
- `@riverpod` simple : missionsController, deliveriesHistoryController, deliveryDetailController(id)
- Toujours utiliser `Ref` (générique) — Riverpod 3.x n'utilise plus les types `XxxRef` spécifiques
- Après toute modif `@riverpod` → `dart run build_runner build`

---

## Format des réponses

- `GET /deliveries/my-missions` → liste directe (`[ {...}, {...} ]`)
- `GET /deliveries/mine` → `{ data: [...], count }`
- `GET /deliveries/:id` → `{ data: {...} }`
- `PATCH /deliveries/:id/accept` → Delivery mise à jour (pas de body en input)
- `PATCH /deliveries/driver-status` → `{ "status": "AVAILABLE" | "ON_DELIVERY" | "OFFLINE" }`
- `GET /users/me` → `{ user: {...} }` OU `{ data: {...} }`

Le helper `_decodeDelivery` / `_decodeUser` dans `delivery_repository.dart` gère les 2 formats (`data` ou `user` ou plat).

---

## Gotchas importants

- `Firebase.initializeApp()` AVANT `ProviderScope` dans `main.dart`
- Token Firebase via `_auth.currentUser.getIdToken()` (pas de cache statique)
- `PATCH /deliveries/:id/accept` sans body
- `LocationService` doit explicitement appeler `startTracking` après `accept` et `stopTracking` après `markDelivered`/`markFailed`
- Permission GPS : refus partiel → tracking échoue silencieusement (pas d'UX feedback)

---

## Dépendances clés

```yaml
flutter_riverpod: ^3.3.1
riverpod_annotation: ^4.0.0
go_router: ^17.2.3
firebase_core: ^4.7.0
firebase_auth: ^6.4.0
firebase_messaging: ^16.2.0
firebase_analytics: ^12.3.0
flutter_local_notifications: ^21.0.0
http: ^1.6.0
socket_io_client: ^3.1.2     # WebSocket tracking
shared_preferences: ^2.5.5
google_maps_flutter: ^2.10.0
geolocator: ^13.0.4
permission_handler: ^11.4.0
intl: ^0.20.2
iconsax: ^0.0.8
google_fonts: ^8.1.0
url_launcher: ^6.3.1
```

---

## Corrections appliquées (mai 2026)

1. ✅ **WebSocket Socket.io** : `TrackingSocketService` créé, push position toutes les 5s (au lieu de 15s polling HTTP). Auth Firebase token, reconnexion auto, fallback HTTP 15s
2. ✅ **TrackingResumeService** : `WidgetsBindingObserver` redémarre auto le tracking si mission `EN_TRANSIT` au retour foreground / boot
3. ✅ **`LocationService.startTracking({deliveryId, orderId})`** : signature mise à jour pour passer l'orderId au WS event
4. ✅ **Backend bug coordonné corrigé** : `DeliveriesService.updateStatus(LIVRER)` émet maintenant `order.status.updated` → FCM client + broadcast WS + loyalty points crédités

## À compléter

- [ ] Firebase config : `google-services.json` (Android) + `GoogleService-Info.plist` (iOS) — même projet que `lilia-app`
- [ ] Remplacer `YOUR_GOOGLE_MAPS_API_KEY` dans `AndroidManifest.xml` + `AppDelegate.swift`
- [ ] Permission `ACCESS_BACKGROUND_LOCATION` Android + `NSLocationAlwaysAndWhenInUseUsageDescription` iOS si tracking arrière-plan
- [ ] **Tracking arrière-plan complet** : utiliser `flutter_background_geolocation` (payant) ou foreground service Android pour continuer à envoyer la position si l'app est complètement fermée (le `TrackingResumeService` actuel ne couvre que pause/resume foreground)
- [ ] **Sync offline batch** : utiliser `POST /tracking/position/batch` quand le réseau revient après une coupure (positions accumulées localement entre-temps)
