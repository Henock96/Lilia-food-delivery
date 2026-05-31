# Delivery App Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Aligner l'app livreur `lilia_food_delivery` sur les nouveaux champs backend (`isPreorder`, `scheduledFor`, `vendorType`, `madeToOrder`) et ajouter la robustesse offline via batch GPS sync.

**Architecture:** Étendre les modèles Flutter pour exposer les nouveaux champs JSON, adapter l'UI (badges preorder, labels vendor-aware, bouton "Accepter" conditionnel), créer un service de queue persistante des positions GPS avec flush automatique au retour réseau, et compléter les `select` Prisma + payload FCM côté backend pour que les données arrivent jusqu'au mobile.

**Tech Stack:** Flutter 3.41 + Riverpod 3.3 (codegen), `connectivity_plus`, `shared_preferences`, `socket_io_client`, `intl`. Backend NestJS + Prisma.

**Spec source:** `docs/superpowers/specs/2026-05-31-delivery-app-sync-design.md`

---

## Pré-requis : branches Git

Cette feature touche deux repos. Crée les branches **avant** Task 1.

```bash
# Backend
cd /Users/henokmipoks/Desktop/code/lilia-backend
git checkout dev && git pull
git checkout -b hmipoka/delivery-marketplace-backend-payload

# Delivery app
cd /Users/henokmipoks/Desktop/code/lilia_food_delivery
git checkout dev && git pull
git checkout -b hmipoka/delivery-marketplace-sync
```

Si un numéro Linear est attribué, renomme : `git branch -m hmipoka/lil-XXX-delivery-marketplace-sync`.

---

## Phase A — Backend prerequisites

Ces modifs doivent shipper **avant** que l'app Flutter mise à jour n'arrive en prod (sinon les nouveaux champs seront `null` dans les payloads).

### Task A1: Étendre les selects Prisma restaurant dans deliveries.service.ts

**Files:**
- Modify: `lilia-backend/apps/lilia-app/src/modules/deliveries/deliveries.service.ts`

Le `select: { id, nom, adresse, phone }` actuel omet `vendorType` et `acceptsPreorders`. Trois occurrences à patcher (`findAll`, `findAllForDeliverer`, `findOne`).

- [ ] **Step 1: Patcher findAllForDeliverer (ligne ~155-161)**

Remplacer :
```typescript
restaurant: {
  select: {
    id: true,
    nom: true,
    adresse: true,
    phone: true,
  },
},
```

Par :
```typescript
restaurant: {
  select: {
    id: true,
    nom: true,
    adresse: true,
    phone: true,
    vendorType: true,
    acceptsPreorders: true,
    preorderLeadHours: true,
  },
},
```

- [ ] **Step 2: Patcher findOne (ligne ~192-199)**

Même remplacement à la 2e occurrence du bloc `restaurant: { select: ... }`.

- [ ] **Step 3: Patcher findAll (ligne ~84 — premier bloc de la fonction)**

Si la 3e occurrence existe (vérifier avec `grep -n "restaurant: {" lilia-backend/apps/lilia-app/src/modules/deliveries/deliveries.service.ts`), appliquer le même patch. Pour `my-missions` route — vérifier `findActiveMissionsForDeliverer` (cherche "my-missions" dans le controller, suis la trace).

- [ ] **Step 4: Build backend pour vérifier les types**

Run: `cd /Users/henokmipoks/Desktop/code/lilia-backend && npm run build 2>&1 | tail -10`
Expected: build success, pas de TS errors. Si erreur Prisma sur `vendorType` → run `npx prisma generate` d'abord.

- [ ] **Step 5: Commit**

```bash
cd /Users/henokmipoks/Desktop/code/lilia-backend
git add apps/lilia-app/src/modules/deliveries/deliveries.service.ts
git commit -m "$(cat <<'EOF'
feat(deliveries): expose vendorType + preorder fields dans les selects restaurant

Les endpoints /deliveries/mine, /deliveries/:id, /deliveries/my-missions
omettaient vendorType, acceptsPreorders et preorderLeadHours sur le restaurant.
Ajout au select pour que l'app livreur puisse adapter ses labels et badges.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

### Task A2: Enrichir le payload FCM d'assignation livreur

**Files:**
- Modify: `lilia-backend/apps/lilia-app/src/modules/deliveries/deliveries.service.ts:427-432`

Le notif `'Nouvelle mission'` envoyée dans `assignDelivererToOrder` n'inclut pas `isPreorder` ni `scheduledFor`. Sans eux, l'app livreur ne peut pas adapter le titre du push.

- [ ] **Step 1: Modifier l'appel sendPushNotification**

Remplacer :
```typescript
await this.notificationsService.sendPushNotification(
  deliverer.id,
  'Nouvelle mission',
  `Commande à récupérer chez ${delivery.order.restaurant.nom}`,
  { type: 'delivery_assigned', deliveryId: updated.id, orderId: delivery.orderId },
);
```

Par :
```typescript
const isPreorder = delivery.order.isPreorder ?? false;
const scheduledFor = delivery.order.scheduledFor;

await this.notificationsService.sendPushNotification(
  deliverer.id,
  isPreorder && scheduledFor
    ? '📅 Pré-commande à récupérer le ' + this.formatScheduledForFr(scheduledFor)
    : '🚚 Nouvelle mission',
  `Commande à récupérer chez ${delivery.order.restaurant.nom}`,
  {
    type: 'delivery_assigned',
    deliveryId: updated.id,
    orderId: delivery.orderId,
    isPreorder: String(isPreorder),
    scheduledFor: scheduledFor?.toISOString() ?? '',
  },
);
```

- [ ] **Step 2: Ajouter le helper formatScheduledForFr (méthode privée de la classe)**

Ajouter en fin de classe `DeliveriesService` (juste avant la fermeture `}`) :
```typescript
private formatScheduledForFr(d: Date): string {
  // "Jeudi 30 mai à 14:30" — pas de dépendance lib, format simple manuel
  const days = ['dimanche', 'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi'];
  const months = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin',
                  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];
  const dayName = days[d.getDay()].charAt(0).toUpperCase() + days[d.getDay()].slice(1);
  const hh = d.getHours().toString().padStart(2, '0');
  const mm = d.getMinutes().toString().padStart(2, '0');
  return `${dayName} ${d.getDate()} ${months[d.getMonth()]} à ${hh}:${mm}`;
}
```

- [ ] **Step 3: Vérifier que delivery.order inclut bien isPreorder/scheduledFor**

Le `findUnique` qui charge `delivery` dans `assignDelivererToOrder` (cherche `await this.prisma.delivery.findUnique` proche de la ligne 366) doit faire `include: { order: { include: { restaurant: true } } }`. `isPreorder` et `scheduledFor` étant des scalaires sur Order, ils arrivent par défaut. Lire le code pour confirmer — si `select: { ... }` explicite, ajouter `isPreorder: true, scheduledFor: true`.

- [ ] **Step 4: Build backend**

Run: `cd /Users/henokmipoks/Desktop/code/lilia-backend && npm run build 2>&1 | tail -5`
Expected: success.

- [ ] **Step 5: Commit**

```bash
cd /Users/henokmipoks/Desktop/code/lilia-backend
git add apps/lilia-app/src/modules/deliveries/deliveries.service.ts
git commit -m "$(cat <<'EOF'
feat(deliveries): payload FCM enrichi avec isPreorder + scheduledFor

L'app livreur peut maintenant afficher un titre adapté pour les push
preorder ("📅 Pré-commande à récupérer le Jeudi 30 mai à 14:30") au
lieu du générique "Nouvelle mission".

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

### Task A3: Push backend branch

- [ ] **Step 1: Push**

```bash
cd /Users/henokmipoks/Desktop/code/lilia-backend
git push -u origin hmipoka/delivery-marketplace-backend-payload
```

Expected: branche poussée, GitHub propose URL de PR. Garder l'URL pour plus tard.

---

## Phase B — Flutter foundation : data models

### Task B1: Créer lib/models/vendor_type.dart

**Files:**
- Create: `lilia_food_delivery/lib/models/vendor_type.dart`

Port direct du modèle déjà présent dans `lilia-app`. Inclut `VendorType`, `ProductType`, `StockMode` même si seulement `VendorType` est utilisé pour l'instant — cohérence inter-app.

- [ ] **Step 1: Créer le fichier avec le contenu suivant**

```dart
// ignore_for_file: constant_identifier_names

/// Marketplace multi-vendeurs (LIL-117).
///
/// Aligné sur les enums Prisma backend. RESTAURANT reste le comportement
/// historique ; les autres types ont une UX adaptée côté client.

enum VendorType {
  RESTAURANT,
  HOME_COOK,
  BAKERY,
  BEVERAGE_SHOP,
  GROCERY;

  String get label {
    switch (this) {
      case VendorType.RESTAURANT:
        return 'Restaurant';
      case VendorType.HOME_COOK:
        return 'Cuisine maison';
      case VendorType.BAKERY:
        return 'Boulangerie';
      case VendorType.BEVERAGE_SHOP:
        return 'Boissons';
      case VendorType.GROCERY:
        return 'Épicerie';
    }
  }

  String get shortLabel {
    switch (this) {
      case VendorType.RESTAURANT:
        return 'Resto';
      case VendorType.HOME_COOK:
        return 'Maison';
      case VendorType.BAKERY:
        return 'Boulanger';
      case VendorType.BEVERAGE_SHOP:
        return 'Boissons';
      case VendorType.GROCERY:
        return 'Épicerie';
    }
  }

  String get emoji {
    switch (this) {
      case VendorType.RESTAURANT:
        return '🍽️';
      case VendorType.HOME_COOK:
        return '🥧';
      case VendorType.BAKERY:
        return '🥐';
      case VendorType.BEVERAGE_SHOP:
        return '🥤';
      case VendorType.GROCERY:
        return '🛒';
    }
  }

  /// Libellé du lieu de récupération pour l'app livreur — adapte
  /// "Récupérer au restaurant" / "à la boulangerie" / etc.
  String get pickupLocationLabel {
    switch (this) {
      case VendorType.RESTAURANT:
        return 'au restaurant';
      case VendorType.HOME_COOK:
        return 'chez le vendeur';
      case VendorType.BAKERY:
        return 'à la boulangerie';
      case VendorType.BEVERAGE_SHOP:
        return 'au point de vente';
      case VendorType.GROCERY:
        return 'à la boutique';
    }
  }

  static VendorType fromString(String? value) {
    return VendorType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => VendorType.RESTAURANT,
    );
  }
}
```

- [ ] **Step 2: flutter analyze**

Run: `cd /Users/henokmipoks/Desktop/code/lilia_food_delivery && flutter analyze lib/models/vendor_type.dart 2>&1 | tail -5`
Expected: `No issues found!`

### Task B2: Étendre les modèles Order, Restaurant, OrderItem

**Files:**
- Modify: `lilia_food_delivery/lib/models/order.dart`

- [ ] **Step 1: Ajouter l'import en haut du fichier**

Au début du fichier, juste avant la 1ère classe :
```dart
import 'package:intl/intl.dart';
import 'package:lilia_food_delivery/models/vendor_type.dart';
```

- [ ] **Step 2: Étendre DeliveryRestaurant**

Remplacer la classe `DeliveryRestaurant` entière par :
```dart
class DeliveryRestaurant {
  final String? id;
  final String nom;
  final String? adresse;
  final String? phone;
  final VendorType vendorType;

  const DeliveryRestaurant({
    this.id,
    required this.nom,
    this.adresse,
    this.phone,
    this.vendorType = VendorType.RESTAURANT,
  });

  factory DeliveryRestaurant.fromJson(Map<String, dynamic> json) =>
      DeliveryRestaurant(
        id: _nullableString(json['id']),
        nom: _stringValue(json['nom'], 'Restaurant'),
        adresse: _nullableString(json['adresse']),
        phone: _nullableString(json['phone']),
        vendorType: VendorType.fromString(json['vendorType'] as String?),
      );
}
```

- [ ] **Step 3: Étendre OrderItem**

Remplacer la classe `OrderItem` entière par :
```dart
class OrderItem {
  final String id;
  final String productNom;
  final int quantity;
  final int unitPrice;
  final bool madeToOrder;

  const OrderItem({
    required this.id,
    required this.productNom,
    required this.quantity,
    required this.unitPrice,
    this.madeToOrder = false,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
        id: _stringValue(json['id']),
        productNom: _productName(json['product']),
        quantity: _intValue(json['quantite']),
        unitPrice: _intValue(json['prix']),
        madeToOrder: (json['product'] is Map<String, dynamic>)
            ? ((json['product'] as Map<String, dynamic>)['madeToOrder'] as bool? ?? false)
            : false,
      );
}
```

- [ ] **Step 4: Étendre DeliveryOrder**

Remplacer la classe `DeliveryOrder` entière par :
```dart
class DeliveryOrder {
  final String id;
  final int total;
  final int subTotal;
  final int deliveryFee;
  final DeliveryRestaurant? restaurant;
  final List<OrderItem> items;
  final DeliveryAddress? adresse;
  final double? clientLatitude;
  final double? clientLongitude;
  final String? clientNom;
  final String? clientPhone;
  final String? contactPhone;
  final bool isPreorder;
  final DateTime? scheduledFor;

  const DeliveryOrder({
    required this.id,
    required this.total,
    required this.subTotal,
    required this.deliveryFee,
    this.restaurant,
    required this.items,
    this.adresse,
    this.clientLatitude,
    this.clientLongitude,
    this.clientNom,
    this.clientPhone,
    this.contactPhone,
    this.isPreorder = false,
    this.scheduledFor,
  });

  /// Meilleur numéro pour appeler : contactPhone > phone du profil
  String? get effectivePhone => contactPhone ?? clientPhone;

  /// "Jeudi 30 mai à 14:30" — null si pas de scheduledFor
  String? get scheduledForFormatted {
    if (scheduledFor == null) return null;
    final local = scheduledFor!.toLocal();
    final dayFormat = DateFormat('EEEE d MMMM', 'fr_FR');
    final timeFormat = DateFormat('HH:mm');
    final day = dayFormat.format(local);
    return '${day[0].toUpperCase()}${day.substring(1)} à ${timeFormat.format(local)}';
  }

  /// Vrai si pas une preorder, OU si on est à moins d'1h de scheduledFor.
  /// Sert à griser le bouton "Accepter" si on tente de récupérer trop tôt.
  bool get isReadyToPickup {
    if (!isPreorder || scheduledFor == null) return true;
    return scheduledFor!.subtract(const Duration(hours: 1))
        .isBefore(DateTime.now());
  }

  factory DeliveryOrder.fromJson(Map<String, dynamic> json) {
    final rawUser = json['user'];
    final user = rawUser is Map<String, dynamic> ? rawUser : null;
    final deliveryAddressStr = _nullableString(json['deliveryAddress']);
    DeliveryAddress? adresse;
    if (json['adresse'] is Map<String, dynamic>) {
      adresse = DeliveryAddress.fromJson(
        json['adresse'] as Map<String, dynamic>,
      );
    } else if (json['adresse'] is String &&
        (json['adresse'] as String).isNotEmpty) {
      adresse = DeliveryAddress(details: json['adresse'] as String);
    } else if (deliveryAddressStr != null && deliveryAddressStr.isNotEmpty) {
      adresse = DeliveryAddress(details: deliveryAddressStr);
    }
    return DeliveryOrder(
      id: _stringValue(json['id']),
      total: _intValue(json['total']),
      subTotal: _intValue(json['subTotal']),
      deliveryFee: _intValue(json['deliveryFee']),
      restaurant: json['restaurant'] != null &&
              json['restaurant'] is Map<String, dynamic>
          ? DeliveryRestaurant.fromJson(
              json['restaurant'] as Map<String, dynamic>,
            )
          : null,
      items: (json['items'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(OrderItem.fromJson)
          .toList(),
      adresse: adresse,
      clientLatitude: _doubleValue(json['deliveryLatitude']),
      clientLongitude: _doubleValue(json['deliveryLongitude']),
      clientNom: _nullableString(user?['nom']),
      clientPhone: _nullableString(user?['phone']),
      contactPhone: _nullableString(json['contactPhone']),
      isPreorder: json['isPreorder'] as bool? ?? false,
      scheduledFor: DateTime.tryParse(json['scheduledFor']?.toString() ?? ''),
    );
  }
}
```

- [ ] **Step 5: Vérifier qu'intl est dans pubspec.yaml**

Run: `grep "^  intl:" /Users/henokmipoks/Desktop/code/lilia_food_delivery/pubspec.yaml`
Expected: ligne `  intl: ^0.20.2` (ou similaire). Si absent → ajouter sous `dependencies:` puis `flutter pub get`.

- [ ] **Step 6: Vérifier que initializeDateFormatting('fr_FR') est appelé au boot**

Run: `grep -rn "initializeDateFormatting" /Users/henokmipoks/Desktop/code/lilia_food_delivery/lib`
Expected: au moins une occurrence dans `main.dart` ou un boot helper. Si absent → ajouter dans `main.dart` avant `runApp` :
```dart
import 'package:intl/date_symbol_data_local.dart';
// ...
await initializeDateFormatting('fr_FR', null);
```

- [ ] **Step 7: flutter analyze**

Run: `cd /Users/henokmipoks/Desktop/code/lilia_food_delivery && flutter analyze lib/models/ 2>&1 | tail -10`
Expected: `No issues found!` (ou éventuels infos préexistants sans erreur).

### Task B3: Commit Phase B

- [ ] **Step 1: Commit**

```bash
cd /Users/henokmipoks/Desktop/code/lilia_food_delivery
# Add the core model files
git add lib/models/vendor_type.dart lib/models/order.dart
# Add pubspec/main.dart only if Step 5/6 above modified them (intl was missing)
git diff --cached --name-only | grep -q pubspec.yaml || git add pubspec.yaml pubspec.lock 2>/dev/null || true
git diff --cached --name-only | grep -q "main.dart" || git add lib/main.dart 2>/dev/null || true
git commit -m "$(cat <<'EOF'
feat(models): expose isPreorder, scheduledFor, vendorType, madeToOrder

Étend DeliveryOrder, DeliveryRestaurant, OrderItem pour parser les nouveaux
champs backend (LIL-117 marketplace + LIL-122 preorder). Ajoute helpers
scheduledForFormatted (fr_FR) et isReadyToPickup pour gérer la fenêtre
de récupération preorder (>1h avant scheduledFor = bouton disabled).

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Phase C — UI surface

### Task C1: Adapter delivery_card.dart

**Files:**
- Modify: `lilia_food_delivery/lib/features/deliveries/presentation/widgets/delivery_card.dart`

Le widget actuel affiche restaurant + adresse + montant. On lui ajoute :
- Badge orange "🕒 Pré-commande" en haut à droite si `order.isPreorder`
- Ligne secondaire sous le restaurant : `${vendorType.emoji} ${vendorType.label}` si `vendorType != RESTAURANT`
- Ligne `scheduledForFormatted` en gras sous l'adresse si preorder

- [ ] **Step 1: Lire le fichier actuel pour repérer la structure**

Run: `cat /Users/henokmipoks/Desktop/code/lilia_food_delivery/lib/features/deliveries/presentation/widgets/delivery_card.dart`

Le sub-agent doit :
- Identifier la colonne qui contient nom du restaurant + adresse
- Identifier où on a la place pour un badge en haut à droite (probablement un `Stack` ou un `Row` avec `mainAxisAlignment.spaceBetween`)

- [ ] **Step 2: Wrapper l'ensemble dans un Stack si pas déjà fait, et ajouter le badge preorder**

Le badge doit être au-dessus de tout, positionné en haut à droite avec ~6-8px de padding intérieur. Code :
```dart
Positioned(
  top: 8,
  right: 8,
  child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.orange.shade100,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.orange.shade400),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: const [
        Icon(Icons.schedule, size: 12, color: Colors.deepOrange),
        SizedBox(width: 4),
        Text(
          'Pré-commande',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.deepOrange,
          ),
        ),
      ],
    ),
  ),
),
```
Wrapper conditionnel : `if (order.isPreorder) Positioned(...)` (utilisation valide dans une liste `Stack.children`).

- [ ] **Step 3: Ajouter la ligne vendor type sous le nom du restaurant**

Juste après le `Text(restaurant.nom)` existant, ajouter :
```dart
if (order.restaurant?.vendorType != null &&
    order.restaurant!.vendorType != VendorType.RESTAURANT) ...[
  const SizedBox(height: 2),
  Row(
    children: [
      Text(
        order.restaurant!.vendorType.emoji,
        style: const TextStyle(fontSize: 12),
      ),
      const SizedBox(width: 4),
      Text(
        order.restaurant!.vendorType.label,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  ),
],
```

N'oublie pas l'import : `import 'package:lilia_food_delivery/models/vendor_type.dart';`

- [ ] **Step 4: Ajouter la ligne scheduledFor sous l'adresse si preorder**

Repère la section qui affiche `adresse?.formatted`. Juste après, ajouter :
```dart
if (order.isPreorder && order.scheduledForFormatted != null) ...[
  const SizedBox(height: 4),
  Row(
    children: [
      const Icon(Icons.event, size: 14, color: Colors.deepOrange),
      const SizedBox(width: 4),
      Text(
        order.scheduledForFormatted!,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.deepOrange,
        ),
      ),
    ],
  ),
],
```

- [ ] **Step 5: flutter analyze sur le fichier**

Run: `cd /Users/henokmipoks/Desktop/code/lilia_food_delivery && flutter analyze lib/features/deliveries/presentation/widgets/delivery_card.dart 2>&1 | tail -5`
Expected: `No issues found!`

### Task C2: Adapter delivery_detail_screen.dart

**Files:**
- Modify: `lilia_food_delivery/lib/features/deliveries/presentation/screens/delivery_detail_screen.dart`

4 modifs à faire dans cet écran :
1. Banner preorder en haut (sous AppBar) si `order.isPreorder`
2. Section "Récupération" : titre adapté via `vendorType.pickupLocationLabel`
3. Bouton "Accepter la mission" disabled + tooltip si `!order.isReadyToPickup`
4. Items : badge "Sur commande" si `item.madeToOrder`

- [ ] **Step 1: Lire le fichier pour comprendre la structure**

Run: `wc -l /Users/henokmipoks/Desktop/code/lilia_food_delivery/lib/features/deliveries/presentation/screens/delivery_detail_screen.dart`

Le sub-agent doit ensuite lire le fichier et repérer :
- Le `Scaffold.body` (où ajouter le banner en haut)
- La section qui affiche les infos du restaurant (où adapter le titre)
- Le bouton "Accepter" (généralement un ElevatedButton avec `onPressed: () => ...accept`)
- La liste des items (`ListView.builder` ou `items.map(...)` quelque part)

- [ ] **Step 2: Ajouter le banner preorder en haut du body**

Au début du body (juste après l'ouverture du `Column` ou `ListView` principal) :
```dart
if (order.isPreorder && order.scheduledFor != null) ...[
  Container(
    width: double.infinity,
    color: Colors.orange.shade50,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(
      children: [
        const Icon(Icons.schedule, color: Colors.deepOrange, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pré-commande pour ${order.scheduledForFormatted}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.deepOrange,
                  fontSize: 14,
                ),
              ),
              Text(
                'Ne pas récupérer avant ${_formatHourMinus1h(order.scheduledFor!)}',
                style: const TextStyle(fontSize: 12, color: Colors.deepOrange),
              ),
            ],
          ),
        ),
      ],
    ),
  ),
  const SizedBox(height: 16),
],
```

Et ajouter en fin de classe `State<...>` (méthode privée) :
```dart
String _formatHourMinus1h(DateTime scheduledFor) {
  final t = scheduledFor.subtract(const Duration(hours: 1)).toLocal();
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
```

- [ ] **Step 3: Adapter le titre de la section Récupération**

Repérer le titre actuel (probablement `Text('Restaurant')` ou similaire dans la section qui affiche `restaurant.nom`/`adresse`). Remplacer par :
```dart
Text(
  'Récupérer ${order.restaurant?.vendorType.pickupLocationLabel ?? 'au restaurant'}',
  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
),
```

(Import `vendor_type.dart` si pas déjà fait.)

- [ ] **Step 4: Conditionner le bouton "Accepter la mission"**

Repérer le bouton existant. Wrapper avec `Tooltip` et passer `onPressed: null` si pas prêt :
```dart
Tooltip(
  message: order.isReadyToPickup
      ? ''
      : 'Trop tôt — pré-commande pour ${order.scheduledForFormatted}',
  child: ElevatedButton(
    onPressed: order.isReadyToPickup
        ? () => /* logique accept existante */
        : null,
    child: const Text('Accepter la mission'),
  ),
),
```

- [ ] **Step 5: Ajouter le badge "Sur commande" sur les items**

Dans le widget qui affiche un item (cherche `OrderItem` ou `item.productNom`), juste à droite ou en dessous du nom :
```dart
Row(
  children: [
    Expanded(child: Text(item.productNom)),
    if (item.madeToOrder)
      Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'Sur commande',
          style: TextStyle(fontSize: 10, color: Colors.black54),
        ),
      ),
  ],
),
```

- [ ] **Step 6: flutter analyze sur le fichier**

Run: `cd /Users/henokmipoks/Desktop/code/lilia_food_delivery && flutter analyze lib/features/deliveries/presentation/screens/delivery_detail_screen.dart 2>&1 | tail -5`
Expected: `No issues found!`

### Task C3: Adapter notification_service.dart pour le titre FCM

**Files:**
- Modify: `lilia_food_delivery/lib/services/notification_service.dart`

- [ ] **Step 1: Lire la méthode qui handle l'arrivée d'un push (foreground/background)**

Run: `grep -n "onMessage\|RemoteMessage\|notification.*title" /Users/henokmipoks/Desktop/code/lilia_food_delivery/lib/services/notification_service.dart | head -10`

Repérer la méthode qui prend un `RemoteMessage` et construit la notif locale (généralement via `flutter_local_notifications`).

- [ ] **Step 2: Au point où le titre est extrait du payload, ajouter la branche preorder**

Si le titre vient de `message.notification?.title` côté serveur, on a déjà le bon titre (modif Task A2). Si le titre est construit côté Flutter à partir du `data`, ajouter :
```dart
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
  const days = ['Dimanche', 'Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi'];
  const months = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin',
                  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '${days[local.weekday % 7]} ${local.day} ${months[local.month - 1]} à $hh:$mm';
}
```

Et remplacer le titre passé à `flutterLocalNotificationsPlugin.show(..., title, ...)` (ou équivalent) par `_buildNotifTitle(message)`.

**Note** : si le backend (Task A2) envoie déjà le bon titre dans `message.notification?.title`, alors le fallback côté Flutter est juste défensif — c'est OK de garder la logique.

- [ ] **Step 3: flutter analyze**

Run: `cd /Users/henokmipoks/Desktop/code/lilia_food_delivery && flutter analyze lib/services/notification_service.dart 2>&1 | tail -5`
Expected: `No issues found!`

### Task C4: Commit Phase C

- [ ] **Step 1: flutter analyze global pour s'assurer que rien n'est cassé**

Run: `cd /Users/henokmipoks/Desktop/code/lilia_food_delivery && flutter analyze lib/ 2>&1 | tail -10`
Expected: 0 erreurs (infos/warnings préexistants acceptés).

- [ ] **Step 2: Commit**

```bash
cd /Users/henokmipoks/Desktop/code/lilia_food_delivery
git add lib/features/deliveries/presentation/widgets/delivery_card.dart \
        lib/features/deliveries/presentation/screens/delivery_detail_screen.dart \
        lib/services/notification_service.dart
git commit -m "$(cat <<'EOF'
feat(ui): badges preorder + labels vendor-aware + bouton accept conditionnel

- delivery_card : badge "Pré-commande" + heure prévue + ligne vendor type
- delivery_detail_screen : banner orange preorder, titre section adapté
  (pickupLocationLabel), bouton "Accepter" disabled >1h avant scheduledFor,
  badge "Sur commande" sur items madeToOrder
- notification_service : titre FCM "📅 Pré-commande à récupérer le ..."
  quand le payload contient isPreorder=true

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Phase D — Tracking offline batch

### Task D1: Ajouter connectivity_plus au pubspec

**Files:**
- Modify: `lilia_food_delivery/pubspec.yaml`

- [ ] **Step 1: Ajouter la dépendance sous `dependencies:`**

```yaml
  connectivity_plus: ^7.1.1
```

(Insérer en ordre alphabétique pour rester propre.)

- [ ] **Step 2: flutter pub get**

Run: `cd /Users/henokmipoks/Desktop/code/lilia_food_delivery && flutter pub get 2>&1 | tail -5`
Expected: `Got dependencies!`

### Task D2: Créer PositionQueueService

**Files:**
- Create: `lilia_food_delivery/lib/features/deliveries/application/position_queue_service.dart`

- [ ] **Step 1: Créer le fichier avec le contenu suivant**

```dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'position_queue_service.g.dart';

const _kPrefsKey = 'tracking_position_queue';
const _kMaxQueueSize = 1000;

/// Position GPS en attente de sync — sérialisable en JSON.
class QueuedPosition {
  final String deliveryId;
  final double latitude;
  final double longitude;
  final double? accuracy;
  final DateTime recordedAt;

  const QueuedPosition({
    required this.deliveryId,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    required this.recordedAt,
  });

  Map<String, dynamic> toJson() => {
        'deliveryId': deliveryId,
        'latitude': latitude,
        'longitude': longitude,
        if (accuracy != null) 'accuracy': accuracy,
        'recordedAt': recordedAt.toIso8601String(),
      };

  factory QueuedPosition.fromJson(Map<String, dynamic> json) => QueuedPosition(
        deliveryId: json['deliveryId'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        accuracy: (json['accuracy'] as num?)?.toDouble(),
        recordedAt: DateTime.parse(json['recordedAt'] as String),
      );
}

/// File persistante de positions GPS — utilisée quand le réseau est down.
/// Drainée par ConnectivityWatcher quand le réseau revient.
class PositionQueueService {
  PositionQueueService(this._prefs);

  final SharedPreferences _prefs;

  /// Nombre de positions actuellement en attente.
  int get queuedCount => _readRaw().length;

  /// Ajoute une position à la file. FIFO eviction si on dépasse _kMaxQueueSize.
  Future<void> enqueue(QueuedPosition p) async {
    final raw = _readRaw();
    raw.add(jsonEncode(p.toJson()));
    while (raw.length > _kMaxQueueSize) {
      raw.removeAt(0);
    }
    await _prefs.setStringList(_kPrefsKey, raw);
    debugPrint('📍 PositionQueue: enqueued, total=${raw.length}');
  }

  /// Lit (sans retirer) jusqu'à [max] positions en tête de file.
  Future<List<QueuedPosition>> drainBatch(int max) async {
    final raw = _readRaw();
    final slice = raw.take(max).toList();
    return slice
        .map((s) => QueuedPosition.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  /// Retire de la file les positions [flushed] (typiquement après un POST réussi).
  /// Identifie par count : on retire les N premières.
  Future<void> markFlushed(int count) async {
    final raw = _readRaw();
    if (count >= raw.length) {
      await _prefs.remove(_kPrefsKey);
    } else {
      await _prefs.setStringList(_kPrefsKey, raw.sublist(count));
    }
    debugPrint('📍 PositionQueue: flushed $count, remaining=${queuedCount}');
  }

  List<String> _readRaw() => _prefs.getStringList(_kPrefsKey) ?? [];
}

@Riverpod(keepAlive: true)
Future<PositionQueueService> positionQueueService(Ref ref) async {
  final prefs = await SharedPreferences.getInstance();
  return PositionQueueService(prefs);
}
```

- [ ] **Step 2: Générer les .g.dart**

Run: `cd /Users/henokmipoks/Desktop/code/lilia_food_delivery && dart run build_runner build --delete-conflicting-outputs 2>&1 | tail -10`
Expected: `Succeeded`. Le fichier `position_queue_service.g.dart` doit être créé.

- [ ] **Step 3: flutter analyze**

Run: `flutter analyze lib/features/deliveries/application/position_queue_service.dart 2>&1 | tail -5`
Expected: `No issues found!`

### Task D3: Ajouter une méthode batch au DeliveryRepository

**Files:**
- Modify: `lilia_food_delivery/lib/features/deliveries/data/delivery_repository.dart`

- [ ] **Step 1: Ajouter la méthode sendPositionsBatch**

À la fin de la classe `DeliveryRepository` (avant la fermeture `}`), ajouter :
```dart
/// Envoie un batch de positions GPS accumulées offline.
/// Backend : POST /tracking/position/batch — body `{ positions: [...] }`.
/// Retourne true si succès (2xx), false sinon (la queue n'est pas vidée).
Future<bool> sendPositionsBatch(List<Map<String, dynamic>> positions) async {
  if (positions.isEmpty) return true;
  try {
    final token = await _getIdToken();
    if (token == null) return false;
    final response = await _httpClient
        .post(
          Uri.parse('${AppConstants.baseUrl}/tracking/position/batch'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'positions': positions}),
        )
        .timeout(const Duration(seconds: 30));
    return response.statusCode >= 200 && response.statusCode < 300;
  } catch (e) {
    debugPrint('⚠️ sendPositionsBatch failed: $e');
    return false;
  }
}
```

(Imports à vérifier : `dart:convert`, `package:flutter/foundation.dart` pour `debugPrint`.)

- [ ] **Step 2: flutter analyze**

Run: `flutter analyze lib/features/deliveries/data/delivery_repository.dart 2>&1 | tail -5`
Expected: `No issues found!`

### Task D4: Créer ConnectivityWatcher

**Files:**
- Create: `lilia_food_delivery/lib/features/deliveries/application/connectivity_watcher.dart`

- [ ] **Step 1: Créer le fichier**

```dart
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:lilia_food_delivery/features/deliveries/application/position_queue_service.dart';
import 'package:lilia_food_delivery/features/deliveries/data/delivery_repository.dart';

part 'connectivity_watcher.g.dart';

/// Observe les transitions réseau et flush la file des positions GPS
/// dès que la connexion revient (none → wifi/mobile).
class ConnectivityWatcher {
  ConnectivityWatcher(this._ref);

  final Ref _ref;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _wasOffline = false;

  void start() {
    _sub?.cancel();
    _sub = Connectivity().onConnectivityChanged.listen(_onChange);
    debugPrint('📡 ConnectivityWatcher started');
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  void _onChange(List<ConnectivityResult> results) {
    final isOnline = results.any(
      (r) => r == ConnectivityResult.wifi || r == ConnectivityResult.mobile,
    );
    if (_wasOffline && isOnline) {
      debugPrint('📡 Réseau revenu → flush position queue');
      unawaited(flushQueue());
    }
    _wasOffline = !isOnline;
  }

  /// Flush en boucle par batches de 50 tant qu'il reste des positions
  /// ET que le serveur répond OK. Public pour pouvoir être appelé depuis
  /// TrackingResumeService au resume foreground (ceinture+bretelles).
  Future<void> flushQueue() async {
    final queue = await _ref.read(positionQueueServiceProvider.future);
    final repo = _ref.read(deliveryRepositoryProvider);

    while (queue.queuedCount > 0) {
      final batch = await queue.drainBatch(50);
      if (batch.isEmpty) break;
      final ok = await repo.sendPositionsBatch(
        batch.map((p) => p.toJson()).toList(),
      );
      if (!ok) {
        debugPrint('📡 Batch send failed, will retry next trigger');
        break;
      }
      await queue.markFlushed(batch.length);
    }
  }
}

@Riverpod(keepAlive: true)
ConnectivityWatcher connectivityWatcher(Ref ref) {
  final w = ConnectivityWatcher(ref);
  ref.onDispose(w.stop);
  return w;
}
```

- [ ] **Step 2: Générer les .g.dart**

Run: `cd /Users/henokmipoks/Desktop/code/lilia_food_delivery && dart run build_runner build --delete-conflicting-outputs 2>&1 | tail -10`
Expected: success, fichier `connectivity_watcher.g.dart` créé.

- [ ] **Step 3: flutter analyze**

Run: `flutter analyze lib/features/deliveries/application/connectivity_watcher.dart 2>&1 | tail -5`
Expected: `No issues found!`

### Task D5: Modifier location_service.dart pour enqueue on failure

**Files:**
- Modify: `lilia_food_delivery/lib/features/deliveries/application/location_service.dart`

- [ ] **Step 1: Lire la méthode _sendLocation actuelle**

Run: `grep -n "_sendLocation\|updateLocation\|PATCH.*location" /Users/henokmipoks/Desktop/code/lilia_food_delivery/lib/features/deliveries/application/location_service.dart`

Le sub-agent doit comprendre :
- Quand `_repo.updateLocation` est appelé
- Comment les erreurs sont gérées actuellement (try/catch ?)
- Quels champs (deliveryId, lat, lng, accuracy) sont disponibles

- [ ] **Step 2: Wrapper l'appel PATCH dans try/catch et enqueue sur failure**

À l'endroit où `_repo.updateLocation(deliveryId, lat, lng, accuracy)` est appelé, remplacer par :
```dart
try {
  await _repo.updateLocation(deliveryId, lat, lng, accuracy);
} catch (e) {
  debugPrint('⚠️ HTTP PATCH location failed, queueing: $e');
  final queue = await _ref.read(positionQueueServiceProvider.future);
  await queue.enqueue(QueuedPosition(
    deliveryId: deliveryId,
    latitude: lat,
    longitude: lng,
    accuracy: accuracy,
    recordedAt: DateTime.now().toUtc(),
  ));
}
```

Vérifier que `_ref` est disponible dans la classe (si pas, l'injecter via le constructeur ou via Provider). Imports nécessaires :
```dart
import 'package:lilia_food_delivery/features/deliveries/application/position_queue_service.dart';
```

- [ ] **Step 3: flutter analyze**

Run: `flutter analyze lib/features/deliveries/application/location_service.dart 2>&1 | tail -5`
Expected: `No issues found!`

### Task D6: Modifier tracking_resume_service.dart pour flusher au resume

**Files:**
- Modify: `lilia_food_delivery/lib/features/deliveries/application/tracking_resume_service.dart`

- [ ] **Step 1: Ajouter le flush dans le handler resume**

Dans la méthode `didChangeAppLifecycleState(AppLifecycleState.resumed)`, après les checks existants (fetch my-missions, etc.), ajouter au début :
```dart
// Ceinture + bretelles : flush la queue offline au cas où le
// ConnectivityWatcher aurait raté une transition réseau pendant
// que l'app était en pause.
try {
  await _ref.read(connectivityWatcherProvider).flushQueue();
} catch (e) {
  debugPrint('⚠️ Resume flush failed: $e');
}
```

Imports :
```dart
import 'package:lilia_food_delivery/features/deliveries/application/connectivity_watcher.dart';
```

- [ ] **Step 2: flutter analyze**

Run: `flutter analyze lib/features/deliveries/application/tracking_resume_service.dart 2>&1 | tail -5`
Expected: `No issues found!`

### Task D7: Démarrer ConnectivityWatcher au login dans main.dart

**Files:**
- Modify: `lilia_food_delivery/lib/main.dart`

- [ ] **Step 1: Repérer où TrackingResumeService est démarré au login**

Run: `grep -n "TrackingResumeService\|trackingResumeService\|onAuthStateChanged" /Users/henokmipoks/Desktop/code/lilia_food_delivery/lib/main.dart`

C'est dans un listener Firebase auth qui démarre les services quand l'user se connecte.

- [ ] **Step 2: Démarrer ConnectivityWatcher juste à côté**

Au même endroit que le démarrage de `TrackingResumeService` (au login), ajouter :
```dart
ref.read(connectivityWatcherProvider).start();
```

Au logout (dans le handler `user == null`), ajouter :
```dart
ref.read(connectivityWatcherProvider).stop();
```

Imports :
```dart
import 'package:lilia_food_delivery/features/deliveries/application/connectivity_watcher.dart';
```

- [ ] **Step 3: flutter analyze main.dart**

Run: `flutter analyze lib/main.dart 2>&1 | tail -5`
Expected: `No issues found!`

### Task D8: Commit Phase D

- [ ] **Step 1: flutter analyze global**

Run: `cd /Users/henokmipoks/Desktop/code/lilia_food_delivery && flutter analyze lib/ 2>&1 | tail -10`
Expected: 0 erreurs.

- [ ] **Step 2: Commit**

```bash
cd /Users/henokmipoks/Desktop/code/lilia_food_delivery
git add pubspec.yaml pubspec.lock \
        lib/features/deliveries/application/position_queue_service.dart \
        lib/features/deliveries/application/position_queue_service.g.dart \
        lib/features/deliveries/application/connectivity_watcher.dart \
        lib/features/deliveries/application/connectivity_watcher.g.dart \
        lib/features/deliveries/application/location_service.dart \
        lib/features/deliveries/application/tracking_resume_service.dart \
        lib/features/deliveries/data/delivery_repository.dart \
        lib/main.dart
git commit -m "$(cat <<'EOF'
feat(tracking): queue persistante GPS + flush auto au retour réseau

Ajoute un PositionQueueService (SharedPreferences, FIFO 1000 max) qui
absorbe les positions GPS quand HTTP PATCH /deliveries/:id/location
échoue. ConnectivityWatcher écoute connectivity_plus et déclenche
flushQueue() (POST /tracking/position/batch par batches de 50) dès
qu'on repasse offline → online. TrackingResumeService déclenche aussi
un flush au resume foreground (ceinture+bretelles).

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Phase E — Manual verification

L'app n'a pas de suite de tests. Vérification manuelle sur device physique.

### Task E1: Smoke test build

- [ ] **Step 1: Build Android debug**

Run: `cd /Users/henokmipoks/Desktop/code/lilia_food_delivery && flutter build apk --debug 2>&1 | tail -10`
Expected: `Built build/app/outputs/flutter-apk/app-debug.apk`

- [ ] **Step 2: Installer sur device + lancer**

Run: `flutter install` puis ouvrir l'app, se logger comme livreur test.
Expected: app démarre sans crash, MissionsScreen visible.

### Task E2: Checklist preorder UI (nécessite backend déployé + commande preorder créée)

**Pré-requis** : la branche backend `hmipoka/delivery-marketplace-backend-payload` doit être déployée (ou tournée en local). Une commande preorder doit exister en DB.

Création d'une commande preorder de test :
1. Sur `lilia-app` (mobile client), choisir un produit `madeToOrder=true` (ex: pâtisserie chez un HOME_COOK ou BAKERY)
2. Aller au panier → checkout → choisir date/heure (24h+)
3. Valider
4. Sur `lilia-food-admin`, ouvrir la commande → assigner livreur de test

- [ ] **Step 1: FCM titre adapté**

Vérifier que la notification reçue affiche `📅 Pré-commande à récupérer le [date]`.
Si rien ne s'affiche / titre générique → vérifier que la backend branch est bien déployée, et que `data.isPreorder='true'` arrive dans le payload (debug log).

- [ ] **Step 2: MissionsScreen — carte preorder**

Ouvrir MissionsScreen. La carte de la mission doit afficher :
- Badge orange `🕒 Pré-commande` en haut à droite
- Ligne avec emoji + vendor type (ex: `🥐 Boulangerie`)
- Heure prévue en orange gras sous l'adresse

- [ ] **Step 3: DeliveryDetailScreen — banner + section + bouton**

Tap sur la mission. Vérifier :
- Banner orange en haut : "Pré-commande pour [date] — ne pas récupérer avant HH:mm"
- Titre section : "Récupérer à la boulangerie" (ou label adapté au vendorType)
- Bouton "Accepter la mission" disabled + tooltip si on est >1h avant
- Items `madeToOrder` affichent badge "Sur commande"

- [ ] **Step 4: Bouton "Accepter" se débloque à T-1h**

Soit attendre, soit côté backend modifier `scheduledFor` à `now + 30min` pour vérifier le comportement. Le bouton doit redevenir cliquable.

### Task E3: Checklist tracking offline batch

- [ ] **Step 1: Tracking online normal**

Accepter une mission "normale" (non preorder). Vérifier que la position est envoyée (logs `PATCH /deliveries/:id/location` toutes les 15s).

- [ ] **Step 2: Couper le réseau pendant tracking**

Activer mode avion (ou wifi off + 4G off). Continuer à bouger. Attendre 1-2 min. Logs attendus :
```
⚠️ HTTP PATCH location failed, queueing: ...
📍 PositionQueue: enqueued, total=N
```

- [ ] **Step 3: Rallumer le réseau**

Réactiver wifi/4G. Logs attendus :
```
📡 Réseau revenu → flush position queue
📍 PositionQueue: flushed N, remaining=0
```
Côté backend (logs Render ou local), vérifier l'arrivée des `POST /tracking/position/batch`.

- [ ] **Step 4: Persistance offline**

Couper réseau, accumuler 10+ positions, **forcer kill** l'app (swipe out / force-stop). Relancer l'app, **toujours offline**. Vérifier dans les logs au boot que `queuedCount > 0` (la queue a survécu). Rebrancher réseau → flush doit envoyer les positions.

### Task E4: Push branches & créer PRs

- [ ] **Step 1: Push branche delivery**

```bash
cd /Users/henokmipoks/Desktop/code/lilia_food_delivery
git push -u origin hmipoka/delivery-marketplace-sync
```

- [ ] **Step 2: Push branche backend (déjà fait Task A3, vérifier)**

```bash
cd /Users/henokmipoks/Desktop/code/lilia-backend
git push -u origin hmipoka/delivery-marketplace-backend-payload 2>&1 | tail -3
```

- [ ] **Step 3: Créer les 2 PRs sur GitHub**

URLs proposées par `git push -u`. Lier les PRs entre elles dans la description (backend doit shipper avant delivery, mentionner la dépendance).

---

## Récap commits attendus

| Phase | Commit |
|---|---|
| A1 | `feat(deliveries): expose vendorType + preorder fields dans les selects restaurant` |
| A2 | `feat(deliveries): payload FCM enrichi avec isPreorder + scheduledFor` |
| B3 | `feat(models): expose isPreorder, scheduledFor, vendorType, madeToOrder` |
| C4 | `feat(ui): badges preorder + labels vendor-aware + bouton accept conditionnel` |
| D8 | `feat(tracking): queue persistante GPS + flush auto au retour réseau` |

5 commits, 2 PRs (1 backend, 1 delivery), 1 vérif manuelle.
