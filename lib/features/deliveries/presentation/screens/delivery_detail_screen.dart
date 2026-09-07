import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:lilia_food_delivery/models/location_precision.dart';
import 'package:lilia_food_delivery/models/order.dart';
import 'package:lilia_food_delivery/utils/map_launcher.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../models/delivery.dart';
import '../../../../utilities/app_theme.dart';
import '../../application/deliveries_controller.dart';
import '../../application/location_service.dart';

String _formatHourMinus1h(DateTime scheduledFor) {
  final t = scheduledFor.subtract(const Duration(hours: 1)).toLocal();
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class DeliveryDetailScreen extends ConsumerWidget {
  final String deliveryId;
  const DeliveryDetailScreen({super.key, required this.deliveryId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deliveryAsync = ref.watch(
      deliveryDetailControllerProvider(deliveryId),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Détail livraison')),
      body: deliveryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (delivery) =>
            _DeliveryDetailBody(delivery: delivery, deliveryId: deliveryId),
      ),
    );
  }
}

class _DeliveryDetailBody extends ConsumerWidget {
  final Delivery delivery;
  final String deliveryId;
  const _DeliveryDetailBody({required this.delivery, required this.deliveryId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = delivery.order;
    final restaurant = order?.restaurant;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Preorder banner
          if (order != null && order.isPreorder && order.scheduledFor != null) ...[
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
                          style: const TextStyle(
                              fontSize: 12, color: Colors.deepOrange),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Status badge
          _StatusBanner(status: delivery.status),
          const SizedBox(height: 16),

          // Carte en temps réel quand EN_TRANSIT
          if (delivery.status == DeliveryStatus.en_transit) ...[
            _DriverMapCard(delivery: delivery, deliveryId: deliveryId),
            const SizedBox(height: 12),
          ],

          // Restaurant info
          if (restaurant != null) ...[
            _InfoCard(
              title: 'Récupérer ${restaurant.vendorType.pickupLocationLabel}',
              icon: Icons.restaurant,
              children: [
                _InfoRow(label: 'Nom', value: restaurant.nom),
                if (restaurant.adresse != null)
                  _InfoRow(label: 'Adresse', value: restaurant.adresse!),
                if (restaurant.phone != null)
                  _PhoneRow(label: 'Téléphone', phone: restaurant.phone!),
                // Première jambe de la course. Elle n'était guidable par
                // aucun bouton : le livreur lisait l'adresse du comptoir puis
                // la retapait à la main dans Google Maps.
                if (restaurant.hasPosition || restaurant.adresse != null)
                  _NavigateButton(
                    latitude: restaurant.latitude,
                    longitude: restaurant.longitude,
                    address: restaurant.adresse,
                    label: restaurant.hasPosition
                        ? 'Naviguer vers ${restaurant.vendorType.pickupLocationLabel}'
                        : "Rechercher l'adresse sur la carte",
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // Client info
          if (order != null) ...[
            _ClientCard(order: order),
            const SizedBox(height: 12),
          ],

          // Order items
          if (order != null && order.items.isNotEmpty) ...[
            _InfoCard(
              title: 'Articles (${order.items.length})',
              icon: Icons.shopping_bag_outlined,
              children: order.items
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(child: Text(item.productNom,
                                    style: const TextStyle(fontSize: 13))),
                                if (item.madeToOrder)
                                  Container(
                                    margin: const EdgeInsets.only(left: 8),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'Sur commande',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.black54),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            '×${item.quantity}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
          ],

          // Pricing
          if (order != null) ...[
            _InfoCard(
              title: 'Montant',
              icon: Icons.payments_outlined,
              children: [
                _InfoRow(label: 'Sous-total', value: '${order.subTotal} XAF'),
                _InfoRow(
                  label: 'Frais de livraison',
                  value: '${order.deliveryFee} XAF',
                ),
                _InfoRow(
                  label: 'Total',
                  value: '${order.total} XAF',
                  bold: true,
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],

          // Actions
          if (delivery.status == DeliveryStatus.assigner) ...[
            Tooltip(
              message: (order != null && order.isReadyToPickup)
                  ? ''
                  : 'Trop tôt — pré-commande pour ${order?.scheduledForFormatted}',
              child: ElevatedButton.icon(
                onPressed: (order == null || order.isReadyToPickup)
                    ? () async {
                        await ref
                            .read(
                              deliveryDetailControllerProvider(deliveryId)
                                  .notifier,
                            )
                            .acceptDelivery();
                        ref.invalidate(
                          deliveryDetailControllerProvider(deliveryId),
                        );
                        if (context.mounted) context.pop();
                      }
                    : null,
                icon: const Icon(Icons.check),
                label: const Text('Accepter la mission'),
              ),
            ),
            const SizedBox(height: 8),
            // Refuser explicitement plutôt qu'ignorer : sans ce bouton, la
            // mission restait assignée indéfiniment et le vendeur attendait
            // une réponse qui ne venait pas.
            OutlinedButton.icon(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Refuser cette mission ?'),
                    content: const Text(
                      'Elle sera proposée à un autre livreur et le vendeur '
                      'en sera informé.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => ctx.pop(false),
                        child: const Text('Annuler'),
                      ),
                      TextButton(
                        onPressed: () => ctx.pop(true),
                        child: const Text(
                          'Refuser',
                          style: TextStyle(color: AppColors.error),
                        ),
                      ),
                    ],
                  ),
                );
                if (confirmed != true || !context.mounted) return;

                try {
                  await ref
                      .read(
                        deliveryDetailControllerProvider(deliveryId).notifier,
                      )
                      .declineDelivery();
                  if (context.mounted) context.pop();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Refus impossible : $e'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.close),
              label: const Text('Refuser'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
              ),
            ),
          ],
          // Mission acceptée : le livreur va au restaurant. Tant qu'il n'a pas
          // confirmé la récupération, la commande n'est PAS annoncée « en
          // route » au client — c'est tout l'objet de cette étape.
          if (delivery.status == DeliveryStatus.accepter) ...[
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.storefront, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Rendez-vous au restaurant pour récupérer la commande.',
                    ),
                  ),
                ],
              ),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                try {
                  final locationIssue = await ref
                      .read(
                        deliveryDetailControllerProvider(deliveryId).notifier,
                      )
                      .confirmPickup();
                  ref.invalidate(deliveryDetailControllerProvider(deliveryId));

                  // La récupération a réussi ; seule la localisation manque.
                  // On le dit, sans bloquer la course.
                  if (locationIssue != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(locationIssue.message),
                        backgroundColor: AppColors.warning,
                        duration: const Duration(seconds: 6),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Récupération impossible : $e'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.shopping_bag),
              label: const Text('J\'ai récupéré la commande'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
              ),
            ),
          ],
          if (delivery.status == DeliveryStatus.en_transit) ...[
            ElevatedButton.icon(
              onPressed: () async {
                await ref
                    .read(deliveryDetailControllerProvider(deliveryId).notifier)
                    .markDelivered();
                if (context.mounted) context.pop();
              },
              icon: const Icon(Icons.check_circle),
              label: const Text('Marquer comme livrée'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Signaler un échec'),
                    content: const Text(
                      'Confirmer que la livraison a échoué ?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => ctx.pop(false),
                        child: const Text('Annuler'),
                      ),
                      TextButton(
                        onPressed: () => ctx.pop(true),
                        child: const Text(
                          'Confirmer',
                          style: TextStyle(color: AppColors.error),
                        ),
                      ),
                    ],
                  ),
                );
                if (confirm == true && context.mounted) {
                  await ref
                      .read(
                        deliveryDetailControllerProvider(deliveryId).notifier,
                      )
                      .markFailed();
                  if (context.mounted) context.pop();
                }
              },
              icon: const Icon(Icons.cancel_outlined, color: AppColors.error),
              label: const Text(
                'Signaler un échec',
                style: TextStyle(color: AppColors.error),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Carte avec position GPS temps réel du livreur + destination client (vue livreur)
class _DriverMapCard extends ConsumerStatefulWidget {
  final Delivery delivery;
  final String deliveryId;
  const _DriverMapCard({required this.delivery, required this.deliveryId});

  @override
  ConsumerState<_DriverMapCard> createState() => _DriverMapCardState();
}

/// Comportement de la caméra pendant une course.
///
/// La version précédente n'avait pas de mode : chaque point GPS appelait
/// `animateCamera`, avec un filtre de 10 m sur la carte encartée et de 5 m en
/// plein écran. À scooter, cela recentrait la carte plusieurs fois par seconde
/// — le livreur ne pouvait ni regarder la destination, ni dézoomer, ni faire
/// quoi que ce soit. C'était le symptôme numéro un de « Maps ne marche pas ».
enum _CameraMode {
  /// La caméra suit le livreur. État initial.
  following,

  /// Le livreur a pris la main : la caméra ne bouge plus toute seule.
  exploring,
}

class _DriverMapCardState extends ConsumerState<_DriverMapCard> {
  GoogleMapController? _mapController;
  StreamSubscription<Position>? _positionSub;
  LatLng? _livePosition;
  _CameraMode _cameraMode = _CameraMode.following;

  /// Vrai le temps d'un mouvement de caméra déclenché par le code.
  bool _selfDrivenCameraMove = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final svc = ref.read(locationServiceProvider);
      if (!svc.isTracking) {
        // `requestPermissionDetailed` et non `requestPermission` : un refus
        // rendu en simple booléen laissait la carte s'afficher, vide, sans que
        // le livreur sache que sa position ne partait pas — et le client
        // voyait un marqueur figé pendant toute la course.
        final permission = await svc.requestPermissionDetailed();
        if (permission.granted) {
          svc.startTracking(
            deliveryId: widget.deliveryId,
            orderId: widget.delivery.orderId,
          );
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(permission.message),
              backgroundColor: AppColors.warning,
              duration: const Duration(seconds: 6),
            ),
          );
        }
      }
      _startPositionStream();
    });
  }

  Future<void> _startPositionStream() async {
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }

    _positionSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          ),
        ).listen((pos) {
          if (!mounted) return;
          setState(() => _livePosition = LatLng(pos.latitude, pos.longitude));
          // Le GPS continue de tourner dans les deux modes ; seule la caméra
          // change de comportement. En EXPLORING on ne la touche pas.
          if (_cameraMode == _CameraMode.following) {
            // Le drapeau est indispensable : sans lui, `onCameraMoveStarted`
            // prend ce recentrage pour un geste du livreur et bascule en
            // EXPLORING dès le premier point GPS — le suivi automatique ne
            // fonctionne alors jamais sur cette carte.
            _selfDrivenCameraMove = true;
            _mapController?.animateCamera(
              CameraUpdate.newLatLng(_livePosition!),
            );
          }
        });
  }

  /// Le livreur a déplacé la carte : on lâche la caméra.
  ///
  /// `onCameraMoveStarted` ne distingue pas un geste d'un `animateCamera`
  /// programmatique. On s'appuie donc sur un drapeau posé juste avant chaque
  /// animation : sans lui, notre propre recentrage déclencherait le passage en
  /// EXPLORING au premier point GPS reçu, et le suivi ne fonctionnerait jamais.
  void _onCameraMoveStarted() {
    if (_selfDrivenCameraMove) {
      _selfDrivenCameraMove = false;
      return;
    }
    if (_cameraMode == _CameraMode.following) {
      setState(() => _cameraMode = _CameraMode.exploring);
    }
  }

  void _recenter() {
    final target = _effectivePosition;
    if (target == null) return;
    setState(() => _cameraMode = _CameraMode.following);
    _selfDrivenCameraMove = true;
    _mapController?.animateCamera(CameraUpdate.newLatLng(target));
  }

  void _fitBoth(LatLng driver) {
    if (_mapController == null) return;
    final client = _clientPos;
    if (client == null) {
      _selfDrivenCameraMove = true;
      _mapController!.animateCamera(CameraUpdate.newLatLng(driver));
      return;
    }
    _selfDrivenCameraMove = true;
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(
            [driver.latitude, client.latitude].reduce((a, b) => a < b ? a : b) -
                0.005,
            [
                  driver.longitude,
                  client.longitude,
                ].reduce((a, b) => a < b ? a : b) -
                0.005,
          ),
          northeast: LatLng(
            [driver.latitude, client.latitude].reduce((a, b) => a > b ? a : b) +
                0.005,
            [
                  driver.longitude,
                  client.longitude,
                ].reduce((a, b) => a > b ? a : b) +
                0.005,
          ),
        ),
        60,
      ),
    );
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  LatLng? get _effectivePosition {
    if (_livePosition != null) return _livePosition;
    if (widget.delivery.lastLatitude != null &&
        widget.delivery.lastLongitude != null) {
      return LatLng(
        widget.delivery.lastLatitude!,
        widget.delivery.lastLongitude!,
      );
    }
    return null;
  }

  LatLng? get _clientPos {
    final order = widget.delivery.order;
    if (order?.clientLatitude != null && order?.clientLongitude != null) {
      return LatLng(order!.clientLatitude!, order.clientLongitude!);
    }
    return null;
  }

  Set<Marker> _buildMarkers(LatLng driverPos) {
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('driver'),
        position: driverPos,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: const InfoWindow(
          title: 'Vous',
          snippet: 'Position actuelle',
        ),
      ),
    };
    final client = _clientPos;
    if (client != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('client'),
          position: client,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: InfoWindow(
            title: 'Client',
            snippet: widget.delivery.order?.adresse?.formatted ?? '',
          ),
        ),
      );
    }
    return markers;
  }

  Set<Polyline> _buildPolylines(LatLng driverPos) {
    final client = _clientPos;
    if (client == null) return {};
    return {
      Polyline(
        polylineId: const PolylineId('route'),
        points: [driverPos, client],
        color: const Color(0xFF1565C0),
        width: 4,
        patterns: [PatternItem.dash(20), PatternItem.gap(10)],
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final pos = _effectivePosition;
    final dest = widget.delivery.order?.adresse?.formatted;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            child: Row(
              children: [
                const Icon(
                  Icons.my_location,
                  color: AppColors.primary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Suivi en direct',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ),
                _LiveBadge(),
                IconButton(
                  icon: const Icon(
                    Icons.fullscreen,
                    size: 22,
                    color: AppColors.textMed,
                  ),
                  tooltip: 'Plein écran',
                  onPressed: () =>
                      context.push('/deliveries/${widget.deliveryId}/map'),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 320,
            child: pos != null
                ? Stack(
                    children: [
                      GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: pos,
                          zoom: 14,
                        ),
                        onMapCreated: (c) {
                          _mapController = c;
                          Future.delayed(
                            const Duration(milliseconds: 300),
                            () => _fitBoth(pos),
                          );
                        },
                        onCameraMoveStarted: _onCameraMoveStarted,
                        markers: _buildMarkers(pos),
                        polylines: _buildPolylines(pos),
                        myLocationEnabled: true,
                        // Le bouton natif recentre sans passer par nous : il
                        // laisserait la caméra en EXPLORING tout en la
                        // déplaçant, donc deux sources de vérité. On expose le
                        // nôtre à la place.
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: true,
                        mapToolbarEnabled: false,
                      ),
                      if (_cameraMode == _CameraMode.exploring)
                        Positioned(
                          right: 12,
                          bottom: 12,
                          child: _RecenterButton(onPressed: _recenter),
                        ),
                    ],
                  )
                : const _NoGpsPlaceholder(),
          ),
          _DestinationPanel(order: widget.delivery.order, address: dest),
        ],
      ),
    );
  }
}

class _NoGpsPlaceholder extends StatelessWidget {
  const _NoGpsPlaceholder();

  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFFF5F5F5),
    child: const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_searching, size: 40, color: AppColors.textLight),
          SizedBox(height: 8),
          Text(
            'Acquisition du signal GPS...',
            style: TextStyle(color: AppColors.textMed, fontSize: 13),
          ),
        ],
      ),
    ),
  );
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.success.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: AppColors.success,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        const Text(
          'LIVE',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.success,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

/// Écran plein écran pour la carte livreur
class FullscreenDriverMapScreen extends ConsumerStatefulWidget {
  final String deliveryId;
  const FullscreenDriverMapScreen({super.key, required this.deliveryId});

  @override
  ConsumerState<FullscreenDriverMapScreen> createState() =>
      _FullscreenDriverMapScreenState();
}

class _FullscreenDriverMapScreenState
    extends ConsumerState<FullscreenDriverMapScreen> {
  GoogleMapController? _mapController;
  StreamSubscription<Position>? _positionSub;
  LatLng? _livePosition;
  _CameraMode _cameraMode = _CameraMode.following;
  bool _selfDrivenCameraMove = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startPositionStream());
  }

  Future<void> _startPositionStream() async {
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }

    _positionSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          ),
        ).listen((pos) {
          if (!mounted) return;
          setState(() => _livePosition = LatLng(pos.latitude, pos.longitude));
          if (_cameraMode == _CameraMode.following) {
            _selfDrivenCameraMove = true;
            _mapController?.animateCamera(
              CameraUpdate.newLatLng(_livePosition!),
            );
          }
        });
  }

  void _onCameraMoveStarted() {
    if (_selfDrivenCameraMove) {
      _selfDrivenCameraMove = false;
      return;
    }
    if (_cameraMode == _CameraMode.following) {
      setState(() => _cameraMode = _CameraMode.exploring);
    }
  }

  void _recenter() {
    final target = _livePosition;
    if (target == null) return;
    setState(() => _cameraMode = _CameraMode.following);
    _selfDrivenCameraMove = true;
    _mapController?.animateCamera(CameraUpdate.newLatLng(target));
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deliveryAsync = ref.watch(
      deliveryDetailControllerProvider(widget.deliveryId),
    );
    final pos = _livePosition;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
            ),
            child: const Icon(
              Icons.arrow_back,
              color: Colors.black87,
              size: 20,
            ),
          ),
          onPressed: () => context.pop(),
        ),
      ),
      body: deliveryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (delivery) {
          // Dernière position connue du livreur, ou rien. Le repli codé en
          // dur sur Brazzaville a disparu : il posait un marqueur « Vous » au
          // centre-ville quand aucune position n'était connue, ce qui est
          // faux et se voyait comme vrai.
          final driverPos = pos ??
              (delivery.lastLatitude != null && delivery.lastLongitude != null
                  ? LatLng(delivery.lastLatitude!, delivery.lastLongitude!)
                  : null);
          final clientPos = delivery.order?.clientLatitude != null &&
                  delivery.order?.clientLongitude != null
              ? LatLng(
                  delivery.order!.clientLatitude!,
                  delivery.order!.clientLongitude!,
                )
              : null;
          // Cadrage : livreur > client > centre-ville. Le dernier n'est qu'un
          // cadrage, aucun marqueur n'y est posé.
          final mapPos =
              driverPos ?? clientPos ?? const LatLng(-4.26778, 15.2753);
          final dest = delivery.order?.adresse?.formatted;

          return Stack(
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(target: mapPos, zoom: 14),
                onCameraMoveStarted: _onCameraMoveStarted,
                onMapCreated: (c) {
                  _mapController = c;
                  if (clientPos != null && driverPos != null) {
                    Future.delayed(const Duration(milliseconds: 400), () {
                      _selfDrivenCameraMove = true;
                      _mapController?.animateCamera(
                        CameraUpdate.newLatLngBounds(
                          LatLngBounds(
                            southwest: LatLng(
                              [
                                    mapPos.latitude,
                                    clientPos.latitude,
                                  ].reduce((a, b) => a < b ? a : b) -
                                  0.005,
                              [
                                    mapPos.longitude,
                                    clientPos.longitude,
                                  ].reduce((a, b) => a < b ? a : b) -
                                  0.005,
                            ),
                            northeast: LatLng(
                              [
                                    mapPos.latitude,
                                    clientPos.latitude,
                                  ].reduce((a, b) => a > b ? a : b) +
                                  0.005,
                              [
                                    mapPos.longitude,
                                    clientPos.longitude,
                                  ].reduce((a, b) => a > b ? a : b) +
                                  0.005,
                            ),
                          ),
                          80,
                        ),
                      );
                    });
                  }
                },
                markers: {
                  if (driverPos != null)
                    Marker(
                      markerId: const MarkerId('driver'),
                      position: driverPos,
                      icon: BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueOrange,
                      ),
                      infoWindow: const InfoWindow(title: 'Vous'),
                    ),
                  if (clientPos != null)
                    Marker(
                      markerId: const MarkerId('client'),
                      position: clientPos,
                      icon: BitmapDescriptor.defaultMarkerWithHue(
                        // Le bleu franc reste réservé à une position exacte ;
                        // un centroïde de quartier prend une teinte distincte.
                        delivery.order!.clientLocationPrecision ==
                                LocationPrecision.exact
                            ? BitmapDescriptor.hueBlue
                            : BitmapDescriptor.hueAzure,
                      ),
                      infoWindow: InfoWindow(
                        title: 'Client',
                        snippet: delivery.order!.clientLocationPrecision ==
                                LocationPrecision.exact
                            ? (delivery.order?.adresse?.formatted ?? '')
                            : 'Position approximative — appelez',
                      ),
                    ),
                },
                polylines: (clientPos != null && driverPos != null)
                    ? {
                        Polyline(
                          polylineId: const PolylineId('route'),
                          points: [driverPos, clientPos],
                          color: const Color(0xFF1565C0),
                          width: 5,
                          patterns: [PatternItem.dash(20), PatternItem.gap(10)],
                        ),
                      }
                    : {},
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: true,
                mapToolbarEnabled: false,
              ),
              if (_cameraMode == _CameraMode.exploring && _livePosition != null)
                Positioned(
                  right: 12,
                  top: 100,
                  child: _RecenterButton(onPressed: _recenter),
                ),
              // Panel infos en bas
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 12,
                        offset: Offset(0, -2),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.delivery_dining,
                              color: AppColors.primary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'En transit',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          _LiveBadge(),
                        ],
                      ),
                      if (dest != null && dest.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on,
                              color: AppColors.primary,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                dest,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textMed,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Carte client ─────────────────────────────────────────────────────────────

class _ClientCard extends StatelessWidget {
  final DeliveryOrder order;
  const _ClientCard({required this.order});

  Future<void> _call(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _sms(String phone) async {
    final uri = Uri.parse('sms:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final name = order.clientNom ?? 'Client';
    final phone = order.effectivePhone;
    final adresse = order.adresse;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // En-tête
            Row(
              children: [
                const Icon(
                  Icons.person_outline,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Client',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Nom
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'C',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      if (phone != null)
                        Text(
                          phone,
                          style: const TextStyle(
                            color: AppColors.textMed,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
                // Boutons appel / SMS
                if (phone != null) ...[
                  IconButton(
                    onPressed: () => _call(phone),
                    icon: const Icon(Icons.call, size: 22),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.success.withValues(alpha: 0.1),
                      foregroundColor: AppColors.success,
                    ),
                    tooltip: 'Appeler',
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    onPressed: () => _sms(phone),
                    icon: const Icon(Icons.sms, size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                      foregroundColor: AppColors.primary,
                    ),
                    tooltip: 'SMS',
                  ),
                ],
              ],
            ),

            // Adresse de livraison
            if (adresse != null && adresse.formatted.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.location_on,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      adresse.formatted,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textMed,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            // Repères du client.
            //
            // Ils n'apparaissaient que dans le panneau de la carte de suivi,
            // c'est-à-dire uniquement en EN_TRANSIT. Or « portail bleu face à
            // la pharmacie » est ce qui permet au livreur de juger le trajet
            // **avant** d'accepter la course, et c'est souvent la seule
            // information qui situe réellement une porte à Brazzaville.
            if (order.clientLandmark != null &&
                order.clientLandmark!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 18,
                    color: AppColors.textMed,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      order.clientLandmark!,
                      style: const TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: AppColors.textMed,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Helper widgets
class _StatusBanner extends StatelessWidget {
  final DeliveryStatus status;
  const _StatusBanner({required this.status});

  Color get _color => switch (status) {
    DeliveryStatus.assigner => AppColors.warning,
    DeliveryStatus.accepter => AppColors.warning,
    DeliveryStatus.en_transit => AppColors.primary,
    DeliveryStatus.livrer => AppColors.success,
    DeliveryStatus.echec => AppColors.error,
    _ => AppColors.textLight,
  };

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(
      color: _color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _color.withValues(alpha: 0.3)),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.circle, size: 10, color: _color),
        const SizedBox(width: 8),
        Text(
          status.label,
          style: TextStyle(
            color: _color,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ],
    ),
  );
}

class _InfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const _InfoCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _InfoRow({required this.label, required this.value, this.bold = false});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(color: AppColors.textMed, fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ],
    ),
  );
}

class _PhoneRow extends StatelessWidget {
  final String label;
  final String phone;
  const _PhoneRow({required this.label, required this.phone});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(color: AppColors.textMed, fontSize: 13),
          ),
        ),
        Expanded(child: Text(phone, style: const TextStyle(fontSize: 13))),
        GestureDetector(
          onTap: () => launchUrl(Uri.parse('tel:$phone')),
          child: const Icon(Icons.phone, size: 18, color: AppColors.primary),
        ),
      ],
    ),
  );
}

/// Bouton « recentrer », visible uniquement quand le livreur a repris la main
/// sur la caméra.
///
/// Il n'apparaît pas en mode `following` : un bouton qui ne ferait rien
/// apprendrait au livreur à l'ignorer, et il serait alors inutile le jour où
/// il compte.
class _RecenterButton extends StatelessWidget {
  const _RecenterButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: const Padding(
          padding: EdgeInsets.all(10),
          child: Icon(
            Icons.my_location,
            size: 22,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}

/// Où livrer, et à quel point on peut s'y fier.
///
/// Le livreur avait auparavant une ligne « Destination : {texte} » et rien
/// d'autre. Deux informations lui manquaient, et ce sont les deux qui
/// comptent à Brazzaville :
///
///  * **la fiabilité du point** — un centroïde de quartier et une porte posée
///    à la main s'affichaient exactement pareil sur la carte ;
///  * **les repères du client** — « portail bleu face à la pharmacie » situe
///    souvent mieux qu'un nom de rue.
class _DestinationPanel extends StatelessWidget {
  const _DestinationPanel({required this.order, required this.address});

  final DeliveryOrder? order;
  final String? address;

  @override
  Widget build(BuildContext context) {
    if (order == null) return const SizedBox.shrink();
    final precision = order!.clientLocationPrecision;
    final landmark = order!.clientLandmark;
    final hasAddress = address != null && address!.isNotEmpty;

    // Le guidage part d'un point si on en a un, sinon du texte de l'adresse.
    // Une destination sans ni l'un ni l'autre n'est pas navigable.
    final canNavigate = precision.hasPosition || hasAddress;

    if (!hasAddress && landmark == null && !canNavigate) {
      return const SizedBox.shrink();
    }

    final warn = precision != LocationPrecision.exact;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.location_on,
                color: AppColors.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Text(
                'Destination : ',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              Expanded(
                child: Text(
                  hasAddress ? address! : 'Adresse non renseignée',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textMed,
                  ),
                ),
              ),
            ],
          ),
          if (landmark != null && landmark.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 16, color: AppColors.textMed),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    landmark,
                    style: const TextStyle(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textMed,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (warn) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.gps_not_fixed,
                    size: 15,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      precision.label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (canNavigate) ...[
            const SizedBox(height: 10),
            _NavigateButton(
              latitude: order!.clientLatitude,
              longitude: order!.clientLongitude,
              address: address,
              label: precision.hasPosition
                  ? 'Naviguer vers la destination'
                  : "Rechercher l'adresse sur la carte",
            ),
          ],
        ],
      ),
    );
  }
}

/// Bouton d'ouverture du guidage GPS.
///
/// La cible est **toujours** une destination de la course — le comptoir du
/// vendeur ou la porte du client — jamais la position courante du livreur, ni
/// celle du client au moment où il a commandé. Les coordonnées du client sont
/// résolues côté serveur depuis l'adresse choisie, puis figées sur la
/// commande : c'est ce qui garantit qu'on guide vers « où on me livre » et non
/// vers « où j'étais en payant ».
class _NavigateButton extends StatelessWidget {
  const _NavigateButton({
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.label,
  });

  final double? latitude;
  final double? longitude;
  final String? address;
  final String label;

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final opened = await MapLauncher.openNavigation(
      latitude: latitude,
      longitude: longitude,
      address: address,
    );
    if (opened) return;
    // Un tap sans effet ferait passer une absence d'application de guidage
    // pour une panne de Lilia Food.
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          "Aucune application de navigation n'a pu être ouverte. "
          'Installez Google Maps, ou appelez votre contact.',
        ),
        duration: Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: OutlinedButton.icon(
      onPressed: () => _open(context),
      icon: const Icon(Icons.directions, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary),
        minimumSize: const Size.fromHeight(44),
      ),
    ),
  );
}
