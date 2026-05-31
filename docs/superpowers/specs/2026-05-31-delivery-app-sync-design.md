# Design — Sync app livreur avec les nouveaux endpoints backend

**Date** : 2026-05-31
**Chantier** : A (premier des 3 du sprint LIL-1XX — voir aussi B preorder web, C redesign restaurant page)
**Auteur** : Henok Mipoka + Claude
**Status** : Approved → ready for implementation plan

## Contexte

Après les sprints LIL-117 (mobile marketplace), LIL-122 (mobile preorder UX) et LIL-124→LIL-130 (admin marketplace), le backend expose désormais :

- `Order.isPreorder` + `Order.scheduledFor` — commandes différées (pâtissiers, traiteurs)
- `Restaurant.vendorType` — `RESTAURANT | HOME_COOK | BAKERY | BEVERAGE_SHOP | GROCERY`
- `Restaurant.acceptsPreorders` + `Restaurant.preorderLeadHours` — info contextuelle vendeur
- `Product.madeToOrder` + `Product.productType` — métadonnée item
- `POST /tracking/position/batch` — sync batch positions GPS offline

L'app livreur `lilia_food_delivery` n'est consciente d'aucun de ces concepts. Conséquences :
- Le livreur ne sait pas si une mission est une preorder pour plus tard
- Les labels UI disent toujours "restaurant" même pour boulangerie/HOME_COOK
- En cas de coupure réseau, les positions GPS sont perdues
- Le titre des notifs FCM ne distingue pas mission immédiate vs preorder

## Objectif

Aligner l'app livreur sur la surface backend marketplace + preorder, et ajouter la robustesse offline via batch sync GPS.

## Non-objectifs

- `VendorProfile` (story, certifications, spécialités vendeur) — info marketing/client, pas utile au livreur
- Tracking arrière-plan complet (foreground service Android / `flutter_background_geolocation`) — autre chantier, hors scope
- Tests automatisés — l'app n'a pas de suite de tests aujourd'hui, on reste sur vérification manuelle

## Architecture

### 1. Modèles (data layer)

Modifs dans `lib/models/order.dart` + nouveau fichier `lib/models/vendor_type.dart`.

**`DeliveryOrder`** :
- `final bool isPreorder` (default `false`)
- `final DateTime? scheduledFor` (UTC, parsé via `DateTime.tryParse`)
- Getter `String? scheduledForFormatted` — "Jeudi 30 mai à 14:30" via `intl` (`fr_FR` déjà initialisé au boot)
- Getter `bool get isReadyToPickup` :
  ```dart
  !isPreorder || (scheduledFor != null &&
    scheduledFor!.subtract(const Duration(hours: 1)).isBefore(DateTime.now()))
  ```
  → utilisé pour griser le bouton "Accepter" si on est >1h avant l'heure prévue.

**`DeliveryRestaurant`** :
- `final VendorType vendorType` (default `RESTAURANT`)
- Parsé via `VendorType.fromString(json['vendorType'])`

**`OrderItem`** :
- `final bool madeToOrder` (default `false`)
- Parsé depuis `json['product']?['madeToOrder']` avec fallback `false`

**`lib/models/vendor_type.dart`** — nouveau, copié du modèle existant dans `lilia-app/lib/models/vendor_type.dart` (enum + `label`, `shortLabel`, `pickupLocationLabel`, `emoji`, `fromString`). Inclut `ProductType` et `StockMode` même si non utilisés actuellement (cohérence inter-app, code mort minime).

### 2. UI (presentation layer)

**`lib/features/deliveries/presentation/widgets/delivery_card.dart`** :
- Badge orange `🕒 Pré-commande` en haut à droite si `order.isPreorder`
- Sous le nom du restaurant : `${restaurant.vendorType.emoji} ${restaurant.vendorType.label}` quand `vendorType != RESTAURANT` (caché pour resto classique = bruit visuel)
- Si preorder → `order.scheduledForFormatted` en gras sous l'adresse

**`lib/features/deliveries/presentation/screens/delivery_detail_screen.dart`** :
- Banner orange en haut (sous AppBar) si preorder :
  > *"Pré-commande pour {scheduledForFormatted} — ne pas récupérer avant {scheduledFor - 1h}"*
- Section "Récupération" : titre adapté via `vendorType.pickupLocationLabel` ("Récupérer au restaurant" / "…à la boulangerie" / "…chez le vendeur")
- Bouton "Accepter la mission" :
  - `disabled` si `!order.isReadyToPickup`
  - Tooltip *"Trop tôt — pré-commande pour HH:mm"*
- Liste d'items : badge gris `Sur commande` à côté du nom si `item.madeToOrder`

**`lib/services/notification_service.dart` (FCM)** :
- Lit `data['isPreorder']` et `data['scheduledFor']`
- Si `isPreorder == 'true'` → titre = *"📅 Pré-commande à récupérer le {date}"* au lieu de *"🚚 Nouvelle mission"*

Aucun changement structurel sur `MissionsScreen`, `HistoryScreen`, `ProfileScreen`, `SignInScreen`.

### 3. Tracking offline batch sync

**Nouveau service** : `lib/features/deliveries/application/position_queue_service.dart` (`@Riverpod(keepAlive: true)`)

```dart
class QueuedPosition {
  final String deliveryId;
  final double latitude, longitude;
  final double? accuracy;
  final DateTime recordedAt;
}

class PositionQueueService {
  Future<void> enqueue(QueuedPosition p);
  Future<List<QueuedPosition>> drainBatch(int max);
  Future<void> markFlushed(List<QueuedPosition> flushed);
  int get queuedCount;
}
```

- Persistance : `SharedPreferences` (déjà dans `pubspec.yaml`), clé `tracking_position_queue` = `List<String>` JSON-encodés
- Capacité max : 1000 positions (~1h25 à 5s/tick), FIFO eviction au-delà

**`location_service.dart` modifs** :
```
Chaque tick (5s) :
  1. Geolocator.getCurrentPosition()
  2. Try WS emit (rapide, non bloquant)
  3. Toutes les 3 ticks (15s) → try HTTP PATCH /deliveries/:id/location
     - Si throw / timeout → enqueue dans PositionQueueService
```

**Nouveau watcher** : `lib/features/deliveries/application/connectivity_watcher.dart`
- Écoute `Connectivity().onConnectivityChanged`
- Sur transition `none → wifi/mobile` et si `queueCount > 0` → `flushQueue()`
- Démarré dans `main.dart` après login (pattern miroir de `TrackingResumeService`)

**Flush logic** :
- Drain par batches de 50 max (payload raisonnable)
- `POST /tracking/position/batch` avec `{ positions: [{ deliveryId, latitude, longitude, accuracy?, recordedAt }] }`
- Succès → `markFlushed` retire ces 50, on continue tant qu'il reste
- Échec → garde la queue, log warning, attend le prochain trigger réseau

**`tracking_resume_service.dart`** : ajouter aussi un `flushQueue()` au `AppLifecycleState.resumed` (ceinture+bretelles).

**Pas de modif backend** sur cette partie — `POST /tracking/position/batch` existe déjà dans `tracking.controller.ts`.

**Dépendances** :
- `connectivity_plus` à ajouter à `pubspec.yaml` (déjà utilisé dans `lilia-app`, version `^7.1.1`)
- Aucune autre nouvelle dépendance

### 4. Backend — FCM payload + selects Prisma

**Modif `lilia-backend/apps/lilia-app/src/modules/listeners/orders.listener.ts`** :
Dans le handler qui notifie le livreur à l'assignation de mission, ajouter aux `data` FCM :
```typescript
data: {
  type: 'new_mission',
  deliveryId: delivery.id,
  orderId: order.id,
  isPreorder: String(order.isPreorder ?? false),
  scheduledFor: order.scheduledFor?.toISOString() ?? '',
}
```
(Les valeurs `data` FCM doivent être des strings.)

**Vérification selects Prisma** :
- `GET /deliveries/:id` — vérifier que `include: { order: { include: { restaurant: true } } }` ramène bien `isPreorder`, `scheduledFor`, `vendorType`, `acceptsPreorders`. Si pas le cas (champs filtrés par un `select` explicite), compléter.
- Idem pour `GET /deliveries/my-missions` et `GET /deliveries/mine`.
- `product.madeToOrder` doit être inclus dans le `include` des items.

Modifs à faire sur une branche backend dédiée `hmipoka/lil-1XX-backend-delivery-payload`, en parallèle des branches front.

## Edge cases & risques

- **App killée offline** → queue persiste dans SharedPreferences (sérialisée immédiatement à chaque enqueue) ✓
- **Position pour delivery terminée** → backend rejette 404/400, on log et drop l'item
- **Queue saturée (>1000)** → FIFO drop des plus vieilles positions (perte acceptable vs blocage)
- **iOS background limits** — `ConnectivityWatcher` peut rater des transitions en background prolongé. Mitigation : double-check `flushQueue()` au resume foreground
- **`connectivity_plus` faux positifs sur émulateurs Android** — tester sur device physique
- **Coordination backend↔mobile** — la modif FCM payload + selects Prisma doit être déployée avant ou en même temps que l'app mise à jour pour que les nouveaux champs arrivent dans le payload

## Plan de vérification manuelle

L'app n'a pas de tests auto. Checklist sur device physique :

1. Backend dev/prod up, modifs FCM payload déployées
2. Créer commande preorder via `lilia-app` (panier produit `madeToOrder` → date picker → checkout)
3. Admin assigne livreur de test à la commande
4. App delivery :
   - [ ] FCM reçu avec titre `📅 Pré-commande à récupérer le ...`
   - [ ] MissionsScreen : badge orange + heure prévue sur la carte
   - [ ] DeliveryDetailScreen : banner orange + label *"Récupérer à la boulangerie"* (selon vendorType)
   - [ ] Bouton "Accepter" disabled si on est >1h avant `scheduledFor`
   - [ ] Items `madeToOrder` : badge "Sur commande"
5. Offline tracking :
   - [ ] Couper wifi pendant tracking → positions queuées (visible via debug log `queueCount`)
   - [ ] Rallumer wifi → `POST /tracking/position/batch` envoyé, queue vidée
   - [ ] App killée puis redémarrée offline → queue restaurée depuis SharedPreferences
   - [ ] Force-stop pendant accumulation → données pas perdues au redémarrage

## Inventaire des changements

| Layer | Fichiers |
|---|---|
| `lilia_food_delivery/lib/models` | `order.dart` (extend), `vendor_type.dart` (nouveau) |
| `lilia_food_delivery/lib/features/deliveries/application` | `position_queue_service.dart` (nouveau), `connectivity_watcher.dart` (nouveau), `location_service.dart` (extend), `tracking_resume_service.dart` (extend) |
| `lilia_food_delivery/lib/features/deliveries/presentation` | `delivery_card.dart`, `delivery_detail_screen.dart` |
| `lilia_food_delivery/lib/services` | `notification_service.dart` |
| `lilia_food_delivery/lib/main.dart` | wire `ConnectivityWatcher` au login |
| `lilia_food_delivery/pubspec.yaml` | + `connectivity_plus: ^7.1.1` |
| `lilia-backend/apps/lilia-app/src/modules/listeners` | `orders.listener.ts` (FCM data payload) |
| `lilia-backend/apps/lilia-app/src/modules/deliveries` | éventuels selects Prisma manquants (à vérifier) |

## Branches Git

- `lilia_food_delivery` : `hmipoka/lil-1XX-delivery-marketplace-sync`
- `lilia-backend` : `hmipoka/lil-1XX-backend-delivery-payload`

Numéros Linear à confirmer.
