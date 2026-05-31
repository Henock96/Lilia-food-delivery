import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:lilia_food_delivery/models/order.dart';
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

class _DriverMapCardState extends ConsumerState<_DriverMapCard> {
  GoogleMapController? _mapController;
  StreamSubscription<Position>? _positionSub;
  LatLng? _livePosition;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final svc = ref.read(locationServiceProvider);
      if (!svc.isTracking) {
        final granted = await svc.requestPermission();
        if (granted) {
          svc.startTracking(
            deliveryId: widget.deliveryId,
            orderId: widget.delivery.orderId,
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
          _mapController?.animateCamera(CameraUpdate.newLatLng(_livePosition!));
        });
  }

  void _fitBoth(LatLng driver) {
    if (_mapController == null) return;
    final client = _clientPos;
    if (client == null) {
      _mapController!.animateCamera(CameraUpdate.newLatLng(driver));
      return;
    }
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
                ? GoogleMap(
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
                    markers: _buildMarkers(pos),
                    polylines: _buildPolylines(pos),
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                    zoomControlsEnabled: true,
                    mapToolbarEnabled: false,
                  )
                : const _NoGpsPlaceholder(),
          ),
          if (dest != null && dest.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
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
                      dest,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textMed,
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
          _mapController?.animateCamera(CameraUpdate.newLatLng(_livePosition!));
        });
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
          final fallback = delivery.lastLatitude != null
              ? LatLng(delivery.lastLatitude!, delivery.lastLongitude!)
              : const LatLng(-4.26778, 15.2753);
          final mapPos = pos ?? fallback;
          final dest = delivery.order?.adresse?.formatted;

          return Stack(
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(target: mapPos, zoom: 14),
                onMapCreated: (c) {
                  _mapController = c;
                  if (delivery.order?.clientLatitude != null) {
                    final clientPos = LatLng(
                      delivery.order!.clientLatitude!,
                      delivery.order!.clientLongitude!,
                    );
                    Future.delayed(const Duration(milliseconds: 400), () {
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
                  Marker(
                    markerId: const MarkerId('driver'),
                    position: mapPos,
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueOrange,
                    ),
                    infoWindow: const InfoWindow(title: 'Vous'),
                  ),
                  if (delivery.order?.clientLatitude != null)
                    Marker(
                      markerId: const MarkerId('client'),
                      position: LatLng(
                        delivery.order!.clientLatitude!,
                        delivery.order!.clientLongitude!,
                      ),
                      icon: BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueBlue,
                      ),
                      infoWindow: InfoWindow(
                        title: 'Client',
                        snippet: delivery.order?.adresse?.formatted ?? '',
                      ),
                    ),
                },
                polylines: delivery.order?.clientLatitude != null
                    ? {
                        Polyline(
                          polylineId: const PolylineId('route'),
                          points: [
                            mapPos,
                            LatLng(
                              delivery.order!.clientLatitude!,
                              delivery.order!.clientLongitude!,
                            ),
                          ],
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
