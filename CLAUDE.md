# CLAUDE.md — Lilia Food Delivery (App Livreur)

App mobile Flutter pour les **livreurs** de la plateforme Lilia Food (Brazzaville, Congo). Rôle Firebase `LIVREUR`.

Lilia Food est une **marketplace locale multi-vendeurs** (restaurants, cuisines
maison, boulangeries, pâtisseries, boissons). Côté livreur l'impact est léger :
le point de retrait peut être n'importe quel type de vendeur. `lib/models/vendor_type.dart`
(enum `VendorType`) sert à afficher le bon label/emoji du vendeur sur la mission
(`delivery_card.dart`, `delivery_detail_screen.dart`) ; `order.dart` porte le
`vendorType` du point de retrait.

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
│   └── profile/
│       ├── application/profile_controller.dart  # getMe + setDriverStatus
│       └── presentation/profile_screen.dart
├── models/
│   ├── delivery.dart                            # Delivery + DeliveryStatus enum
│   ├── order.dart                               # DeliveryOrder, DeliveryRestaurant, OrderItem, DeliveryAddress
│   └── app_user.dart                            # AppUser + DriverStatus enum
├── routing/app_router.dart                      # go_router + auth redirect
├── services/
│   ├── notification_service.dart                # FCM (DeliveryNotificationService)
│   ├── notification_router.dart                 # payload FCM → action (pur, testé)
│   └── fcm_token_registrar.dart                 # cycle de vie du token (pur, testé)
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
| `GET` | `/deliveries/my-missions` | Missions actives (ASSIGNER + ACCEPTER + EN_TRANSIT) — **liste directe** |
| `GET` | `/deliveries/:id` | Détail d'une livraison — `{ data: {...} }` |
| `PATCH` | `/deliveries/:id/accept` | Accepter la mission → ACCEPTER (**la commande ne bouge pas**) |
| `PATCH` | `/deliveries/:id/pickup` | Repas récupéré → EN_TRANSIT + Order → EN_ROUTE (notifie le client) |
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
EN_ATTENTE  → ASSIGNER   (admin/restaurateur assigne)
ASSIGNER    → ACCEPTER   (livreur accepte — PATCH /accept)
ACCEPTER    → EN_TRANSIT (livreur récupère le repas — PATCH /pickup → Order → EN_ROUTE)
EN_TRANSIT  → LIVRER     (livraison confirmée)
*           → ECHEC      (échec, depuis ASSIGNER / ACCEPTER / EN_TRANSIT)
```

⚠️ **`ACCEPTER` ≠ `EN_TRANSIT`** (29/08/2026). Accepter une mission signifie
« je vais chercher le repas », pas « la commande est en route ». Avant cette
séparation, `/accept` faisait passer la livraison directement en `EN_TRANSIT`,
écrivait `pickedUpAt` et basculait la commande en `EN_ROUTE` : le client
recevait « votre livreur est en chemin » alors que le livreur n'avait pas
quitté son domicile.

`LIVRER` n'est atteignable que depuis `EN_TRANSIT` : impossible de déclarer
livrée une commande jamais récupérée.

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
3. Livreur ouvre detail → bouton "Accepter la mission"
   → PATCH /deliveries/:id/accept
     • Delivery → ACCEPTER (+ acceptedAt)
     • DriverStatus → ON_DELIVERY (auto)
     • Order INCHANGÉE (reste PRET) → le client n'est PAS notifié
     • le RESTAURANT reçoit « le livreur a accepté »
   → aucun tracking GPS : le livreur n'a pas le repas, sa position ne
     regarde pas encore le client
4. Livreur au comptoir → bouton "J'ai récupéré la commande"
   → PATCH /deliveries/:id/pickup
     • Delivery → EN_TRANSIT (+ pickedUpAt, le vrai)
     • Order → EN_ROUTE → **c'est ici** que le client reçoit
       « 🛵 votre commande est en route »
     • le RESTAURANT reçoit « la commande a quitté le comptoir »
   → LocationService.startTracking(deliveryId) côté Flutter
5. Timer 5s WS + fallback HTTP 15s → position
6. Livreur arrive → PATCH /deliveries/:id/status { LIVRER }
   → LocationService.stopTracking
   → FCM client + restaurant, loyalty points crédités
   → le client peut alors noter le livreur (1–5 étoiles)
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

## Push Notifications FCM (mai 2026, revu août 2026)

Trois fichiers, dont deux purs et testés :

| Fichier | Rôle |
|---|---|
| `services/notification_service.dart` | `DeliveryNotificationService` — colle Firebase / plugin local |
| `services/notification_router.dart` | payload FCM → `NotificationAction` (**pur, testé**) |
| `services/fcm_token_registrar.dart` | token : register / remove / garde de session (**pur, testé**) |

Le service touche `FirebaseMessaging.instance` dès sa construction, donc il
n'est pas instanciable en test unitaire. Toute logique décidable en est
extraite — c'est ce qui rend le routage et le cycle de vie du token
vérifiables. **Y ajouter de la logique = l'ajouter dans un des deux fichiers
purs.**

- Initialisé dans `main.dart` au login Firebase : `ref.read(deliveryNotificationServiceProvider).init()`
- Token enregistré via `POST /notifications/register-token` (retry 3x, backoff 15s)
- Token supprimé au logout via `DELETE /notifications/token`, **dans
  `AuthController.signOut()` avant le signOut Firebase** — après, le DELETE
  authentifié ne passerait plus
- `remove()` réarme la garde de session : sans ça une reconnexion sans
  redémarrage de l'app n'enregistrait plus aucun token
- Backend → `data.type == 'delivery_assigned'` + `deliveryId`
  (`delivery-assignment.service.ts`). Le routeur reconnaît aussi n'importe quel
  payload portant un `deliveryId`, pour survivre à un nouveau type backend
- **Navigation seulement au tap** (`onMessageOpenedApp`, `getInitialMessage`,
  tap sur notif locale) → `push('/deliveries/<id>')`. En foreground on
  rafraîchit sans déplacer le livreur, qui peut être en pleine course
- Canal Android : `high_importance_channel` (max + son + vibration)
- ⚠️ **Le handler background n'affiche rien** : Android affiche déjà la notif
  lui-même (bloc `notification` backend + `default_notification_channel_id` au
  manifest). Un `show()` dedans en produisait une seconde, identique
- iOS : `_fetchFcmToken()` retente pendant 10s tant qu'APNS répond
  `apns-token-not-set` (l'enregistrement APNS est asynchrone au 1er lancement)

### iOS — entitlements requis

`ios/Runner/Runner.entitlements` (Debug + Profile) et `RunnerRelease.entitlements`
portent `aps-environment`, câblés via `CODE_SIGN_ENTITLEMENTS` sur les 3 build
configs. Sans eux, `getToken()` échoue et **aucun push n'arrive, même sur
iPhone physique**. `UIBackgroundModes: remote-notification` est dans
`Info.plist`.

⚠️ Les deux fichiers sont sur `development`. À basculer sur `production` avant
la première distribution TestFlight / App Store.

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
- `LocationService.startTracking` se déclenche après **`confirmPickup`**, pas
  après `accept` : diffuser la position d'un livreur qui n'a pas encore le repas
  faisait croire au client que sa commande était partie. `stopTracking` après
  `markDelivered` / `markFailed`
- `TrackingResumeService` ne reprend le tracking que sur les missions
  `EN_TRANSIT` — surtout pas `ACCEPTER`, pour la même raison
- Permission GPS : `requestPermissionDetailed()` partout où un écran peut
  afficher le motif (récupération, carte de course). Le booléen
  `requestPermission()` avalait le refus : le livreur croyait être suivi, le
  client voyait un marqueur figé.
  Le refus remonte dans `trackingIssueControllerProvider`
  (`application/tracking_issue.dart`), que `TrackingIssueBanner` affiche
  **au-dessus du routeur** (`MaterialApp.router(builder:)`) — et non dans le
  shell, sans quoi il serait invisible sur l'écran de détail, là où le livreur
  passe sa course. `TrackingResumeService` n'a pas de `BuildContext` : publier
  un état observable est le seul moyen pour lui de se faire entendre.
  Le bandeau **n'a pas de bouton de fermeture** : la cause dure tant qu'elle
  n'est pas traitée, et un bandeau qu'on peut écarter finit écarté. Il disparaît
  seul quand le suivi repart ou quand la course se termine. L'action proposée
  suit le motif : « Activer » (GPS éteint) → réglages de localisation,
  « Réglages » (refus définitif) → fiche de l'app, « Autoriser » (refus
  ponctuel) → nouvelle demande sur place.
- `MissionsController.confirmPickup` a été **supprimé** (29/08/2026) : jamais
  appelé, il dupliquait la logique de `DeliveryDetailController` avec l'ancien
  `requestPermission()`. Un duplicat mort conserve le bug qu'on vient de
  corriger, prêt à resurgir au premier branchement.

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

## Remédiation audit (août 2026 — `AUDIT_2026-08-01.md`)

1. ✅ **Keystore retiré du dépôt** (C-1) — `upload-keystore.jks` sorti de l'index
   (`git rm --cached`, fichier local préservé). `.gitignore` durci : `*.jks`,
   `*.keystore`, `/android/key.properties`, `/android/local.properties`,
   `/android/build/`, `/android/app/build/`.
   ⚠️ Il reste dans l'historique git → rotation du keystore + purge historique +
   Play App Signing à décider.
2. ✅ **Pattern `MapsKeys.xcconfig`** — celui de cette app a servi de modèle pour
   sortir la clé Google Maps du code de `lilia-app` (template committé +
   `MapsKeys.local.xcconfig` gitignoré + `#include?`).
3. ✅ **Dépendances alignées** sur les 3 apps Flutter (`firebase_core ^4.10.0`,
   `firebase_auth ^6.5.2`, `flutter_riverpod ^3.3.2`, `riverpod_annotation
   ^4.0.3`, `go_router ^17.3.0`, `dio ^5.9.2`), `build_runner` régénéré.
4. ✅ **Côté backend** (impacte cette app) : le WebSocket `/tracking` revalide
   `exp` du token **et** `statusUser` à chaque message, et valide le payload
   `driver:position` via un DTO class-validator. Un token expiré en cours de
   mission fait maintenant échouer l'émission → la reconnexion Socket.io doit
   repartir sur un token frais.

Résultat : `flutter analyze` **0 erreur / 0 warning**, tests **21/21**.

---

## À compléter

- [ ] **Clé APNs valide dans Firebase Console** (Team ID `4R7BCB3ZSZ`) — les
      entitlements sont en place côté app, mais la console rejette encore la
      clé (« Invalid APNs credential »). Tant que ce n'est pas réglé, aucun
      push iOS n'arrive
- [ ] Basculer `aps-environment` sur `production` dans
      `ios/Runner/RunnerRelease.entitlements` avant distribution App Store
- [ ] Créer les 6 clés Maps restreintes et révoquer les 2 actuelles — voir
      `lilia-backend/docs/01-architecture/google-maps-keys.md`. Le build de
      release échoue désormais si la clé est absente.
- [x] ~~Tracking arrière-plan~~ — fait le 01/09/2026 via un service de premier
      plan Android (`geolocator`) + `UIBackgroundModes: location` iOS, sans
      dépendance payante. Voir la section dédiée plus bas.
      ⚠️ Reste hors de portée : l'app **complètement fermée** (force-stop ou
      tuée par l'OS). Aucune solution Flutter n'y répond sans un service
      redémarré au boot, hors périmètre.
- [ ] **Sync offline batch** : utiliser `POST /tracking/position/batch` quand le réseau revient après une coupure (positions accumulées localement entre-temps)

---

## Destination, caméra et suivi en arrière-plan (1er septembre 2026)

### La destination vient de la commande

`DeliveryOrder.clientLatitude/Longitude` sont désormais résolus par le serveur
depuis l'adresse du client — plus le GPS de son téléphone au moment de commander.
Deux champs les accompagnent :

- `clientLocationPrecision` (`exact` / `approximate` / `unknown`) — décide de ce
  que le livreur doit faire en arrivant : viser le point, ou appeler ;
- `clientLandmark` — « portail bleu face à la pharmacie ». À Brazzaville, souvent
  la seule information qui situe réellement une porte.

`_DestinationPanel` affiche les trois. Aucun marqueur n'est posé si la position
est inconnue, et le repli codé en dur sur le centre de Brazzaville a disparu des
deux cartes.

### Caméra : `FOLLOWING` / `EXPLORING`

Chaque point GPS appelait `animateCamera` (filtre 10 m encarté, 5 m plein
écran). À scooter, la carte se recentrait plusieurs fois par seconde : le
livreur ne pouvait ni regarder la destination, ni dézoomer. C'était le symptôme
numéro un de « Maps ne marche pas ».

Désormais : `FOLLOWING` au départ, bascule en `EXPLORING` au premier geste,
bouton « recentrer » pour revenir. **Le GPS continue de tourner dans les deux
modes** — seule la caméra change.

⚠️ `onCameraMoveStarted` ne distingue pas un geste d'un `animateCamera`
programmatique. Un drapeau `_selfDrivenCameraMove` est posé juste avant chaque
animation ; sans lui, notre propre recentrage ferait basculer en `EXPLORING` au
premier point reçu et le suivi ne marcherait jamais.

### Suivi écran éteint

`LocationService` n'utilise plus `Timer.periodic` + `getCurrentPosition` : les
deux sont suspendus par Android et iOS dès que l'app quitte le premier plan. Le
suivi s'arrêtait donc quand le livreur rangeait son téléphone — c'est-à-dire
pendant à peu près toute la course.

Un `getPositionStream` avec réglages par plateforme le remplace :

- **Android** : `ForegroundNotificationConfig` → service de premier plan de type
  `location`, notification persistante. Permissions `FOREGROUND_SERVICE` et
  `FOREGROUND_SERVICE_LOCATION` au manifeste.
  ⚠️ `ACCESS_BACKGROUND_LOCATION` n'est **délibérément pas** demandée : un
  service de premier plan reçoit les positions sans elle. La demander imposerait
  un second dialogue système hors de l'app et une justification Play Store, pour
  une capacité inutile — on ne suit jamais un livreur hors course.
- **iOS** : `allowBackgroundLocationUpdates` + `UIBackgroundModes: location`
  dans `Info.plist`. `NSLocationAlwaysAndWhenInUseUsageDescription` était déjà
  déclarée mais **inopérante** sans ce mode.
  `showBackgroundLocationIndicator: true` — le bandeau bleu : le livreur sait
  qu'il est suivi. `pauseLocationUpdatesAutomatically: false` — une pause iOS
  est indistinguable d'une panne côté client.

Publication throttlée (5 s minimum) + battement (20 s) : un livreur arrêté à un
feu n'émet aucun point avec un filtre de distance, et les métadonnées Redis
expirent au bout de 5 minutes. 1 écriture HTTP sur 3 publications.

### Token WebSocket

`reconnect()` existait et n'était **jamais appelé**. Le token Firebase, capturé
à l'ouverture du socket, expire au bout d'une heure ; Socket.io rejouait le même
à chaque reconnexion, la gateway déconnectait en boucle, et le repli HTTP
prenait le relais toutes les 5 s — panne invisible, au prix de la batterie et
des requêtes. Le correctif existait côté app cliente depuis août (C3) sans avoir
été porté ici. `firebaseIdTokenProvider` (nouveau) déclenche la reconnexion.
