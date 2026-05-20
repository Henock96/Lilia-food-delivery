# AGENTS.md — Lilia Food Delivery (App Livreur)

Application mobile Flutter pour les livreurs de la plateforme Lilia Food (Brazzaville, Congo).

## Contexte projet

Cette app est le **3e composant** de l'écosystème Lilia Food :
| Composant | Stack | Dossier |
|-----------|-------|---------|
| Client mobile | Flutter + Riverpod | `lilia-app/` |
| Backend API | NestJS + Prisma + PostgreSQL | `lilia-backend/` |
| Admin dashboard | Flutter + Riverpod | `lilia-food-admin/` |
| **App livreur** | **Flutter + Riverpod** | **`lilia_food_delivery/`** |

**Backend URL** : `https://lilia-backend.onrender.com`  
**Rôle Firebase** : `LIVREUR`  
**Org** : `com.dreesis`

---

## Commandes essentielles

```bash
flutter pub get
dart run build_runner build          # Générer les .g.dart Riverpod
dart run build_runner watch          # Watch mode pendant le dev
flutter run
flutter analyze
```

---

## Architecture

```
lib/
├── features/
│   ├── auth/
│   │   ├── data/         auth_repository.dart   # Firebase Auth + getIdToken
│   │   ├── application/  auth_controller.dart   # signIn/signOut
│   │   └── presentation/ sign_in_screen.dart
│   ├── deliveries/
│   │   ├── data/         delivery_repository.dart  # Tous les appels /deliveries/*
│   │   ├── application/  deliveries_controller.dart # Missions, historique, détail
│   │   └── presentation/
│   │       ├── screens/  missions_screen, delivery_detail_screen, history_screen
│   │       └── widgets/  delivery_card.dart
│   └── profile/
│       ├── application/  profile_controller.dart  # getMe + setDriverStatus
│       └── presentation/ profile_screen.dart
├── models/
│   ├── delivery.dart     # Delivery + DeliveryStatus enum
│   ├── order.dart        # DeliveryOrder, DeliveryRestaurant, OrderItem, DeliveryAddress
│   └── app_user.dart     # AppUser + DriverStatus enum
├── routing/              app_router.dart (go_router + auth redirect)
├── constants/            app_constants.dart (baseUrl)
└── utilities/            app_theme.dart (AppColors, AppTheme)
```

---

## Endpoints backend consommés

| Méthode | Endpoint | Description |
|---------|----------|-------------|
| `GET` | `/deliveries/mine?status=` | Mes livraisons assignées |
| `GET` | `/deliveries/my-missions` | Missions actives (ASSIGNER + EN_TRANSIT) |
| `GET` | `/deliveries/:id` | Détail d'une livraison |
| `PATCH` | `/deliveries/:id/accept` | Accepter → ASSIGNER→EN_TRANSIT, commande→EN_ROUTE |
| `PATCH` | `/deliveries/:id/status` | Mettre à jour le statut (LIVRER, ECHEC) |
| `PATCH` | `/deliveries/driver-status` | Changer statut livreur (AVAILABLE/ON_DELIVERY/OFFLINE) |
| `GET` | `/users/me` | Profil du livreur connecté |

**Format Auth** : `Authorization: Bearer <Firebase ID token>` sur chaque requête.

---

## Statuts métier

### DeliveryStatus (livraison)
```
EN_ATTENTE → ASSIGNER (admin assigne)
ASSIGNER → EN_TRANSIT (livreur accepte → commande passe EN_ROUTE)
EN_TRANSIT → LIVRER (livraison confirmée)
EN_TRANSIT → ECHEC (échec de livraison)
```

### DriverStatus (livreur)
```
AVAILABLE   — en attente de missions
ON_DELIVERY — en cours de livraison (auto-set à l'accept)
OFFLINE     — non disponible
```

---

## Patterns Riverpod

- `@Riverpod(keepAlive: true)` pour : authRepository, httpClient, deliveryRepository, profileController
- `@riverpod` simple pour : missionsController, deliveriesHistoryController, deliveryDetailController(id)
- Toujours utiliser `Ref` (générique) comme type de ref dans les providers fonctionnels — Riverpod 3.x n'utilise plus les types `XxxRef` spécifiques
- Après toute modification `@riverpod` → `dart run build_runner build`

---

## Navigation (go_router)

3 tabs via `StatefulShellRoute` :
1. `/` → MissionsScreen (missions actives)
2. `/history` → HistoryScreen (toutes les livraisons)
3. `/profile` → ProfileScreen (statut + déconnexion)

Route détail : `/deliveries/:id` → DeliveryDetailScreen

Auth redirect : non connecté → `/signin`, connecté sur `/signin` → `/`

---

## Gotchas importants

- `Firebase.initializeApp()` AVANT `ProviderScope` dans main.dart
- Le token Firebase doit être rafraîchi via `_auth.currentUser.getIdToken()` (pas en cache statique)
- `PATCH /deliveries/driver-status` accepte `{ "status": "AVAILABLE" | "ON_DELIVERY" | "OFFLINE" }`
- `PATCH /deliveries/:id/accept` ne prend pas de body — retourne directement la Delivery mise à jour
- La réponse de `/deliveries/my-missions` est une liste directe (pas wrappée dans `{ data: [...] }`)
- La réponse de `/deliveries/mine` est `{ data: [...], count: N }`
- La réponse de `/deliveries/:id` est `{ data: {...} }`

---

## Notifications FCM (mai 2026)

`lib/services/notification_service.dart` → `DeliveryNotificationService`

- Initialisation dans `main.dart` (après Firebase) : `ref.read(deliveryNotificationServiceProvider).init()`
- Provider : `@Riverpod(keepAlive: true) deliveryNotificationService`
- Token FCM enregistré via `POST /notifications/register-token` (retry 3x avec backoff 15s)
- Token supprimé à la déconnexion via `DELETE /notifications/token`
- Handler background (top-level) : `firebaseMessagingBackgroundHandler`
- Quand `data['type'] == 'new_mission'` ou `data.containsKey('deliveryId')` → `missionsControllerProvider.notifier.refresh()`
- Canal Android : `high_importance_channel` (importance MAX, son + vibration)
- Gestion erreur APNS simulateur : graceful skip si `apns-token-not-set`

**Note** : Firebase (google-services.json + GoogleService-Info.plist) doit encore être configuré pour que les notifs fonctionnent en production. Voir section "À compléter".

---

## Tracking GPS — Architecture

### Flow complet
1. Livreur accepte une mission → `acceptDelivery()` → `LocationService.startTracking(id)`
2. Timer toutes les 15s → `Geolocator.getCurrentPosition()` → `PATCH /deliveries/:id/location`
3. Backend stocke `lastLatitude`, `lastLongitude`, `lastPositionAt` + crée un `DeliveryLocation`
4. Client app poll `GET /deliveries/by-order/:orderId` toutes les 10s → affiche sur Google Maps

### Fichiers clés
- `lib/features/deliveries/application/location_service.dart` — `LocationService` (timer + Geolocator)
- `lib/features/deliveries/application/deliveries_controller.dart` — intègre start/stopTracking
- Widget carte : `_DriverMapCard` dans `delivery_detail_screen.dart`

### Config requise (avant build)
- Android : `android/app/src/main/AndroidManifest.xml` → remplacer `YOUR_GOOGLE_MAPS_API_KEY`
- iOS : `ios/Runner/AppDelegate.swift` → remplacer `YOUR_GOOGLE_MAPS_API_KEY`
- Clé à créer sur Google Cloud Console → Maps SDK for Android + Maps SDK for iOS activés

---

## À compléter

- [ ] Intégration Firebase : `android/app/google-services.json` + `ios/Runner/GoogleService-Info.plist` (même projet Firebase que lilia-app)
- [ ] Remplacer `YOUR_GOOGLE_MAPS_API_KEY` dans `AndroidManifest.xml` + `AppDelegate.swift`
- [ ] Migrer le tracking de HTTP polling (15s) vers WebSocket Socket.io — le backend expose `/tracking` (namespace Socket.io, auth via `handshake.auth.token`)

**Note backend tracking** : le backend enregistre la position en DB max 1x/min (lock Redis 60s), mais diffuse via WebSocket en temps réel. L'HTTP polling actuel est suffisant pour la MVP.
