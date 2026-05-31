import 'package:flutter/material.dart';
import '../../../../models/delivery.dart';
import '../../../../models/vendor_type.dart';
import '../../../../utilities/app_theme.dart';

class DeliveryCard extends StatelessWidget {
  final Delivery delivery;
  final VoidCallback? onTap;
  final VoidCallback? onAccept;

  const DeliveryCard({
    super.key,
    required this.delivery,
    this.onTap,
    this.onAccept,
  });

  Color _statusColor() => switch (delivery.status) {
    DeliveryStatus.assigner => AppColors.warning,
    DeliveryStatus.en_transit => AppColors.primary,
    DeliveryStatus.livrer => AppColors.success,
    DeliveryStatus.echec => AppColors.error,
    _ => AppColors.textLight,
  };

  @override
  Widget build(BuildContext context) {
    final order = delivery.order;
    final restaurant = order?.restaurant;
    return Stack(
      children: [
      Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.delivery_dining,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          restaurant?.nom ?? 'Restaurant',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        if (restaurant != null &&
                            restaurant.vendorType != VendorType.RESTAURANT) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                restaurant.vendorType.emoji,
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                restaurant.vendorType.label,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (restaurant?.adresse != null)
                          Text(
                            restaurant!.adresse!,
                            style: const TextStyle(
                              color: AppColors.textMed,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _statusColor().withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      delivery.status.label,
                      style: TextStyle(
                        color: _statusColor(),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (order != null) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color: AppColors.textMed,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        order.adresse?.formatted ?? 'Adresse non définie',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textMed,
                        ),
                      ),
                    ),
                  ],
                ),
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
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      Icons.shopping_bag_outlined,
                      size: 16,
                      color: AppColors.textMed,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${order.items.length} article${order.items.length > 1 ? 's' : ''}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textMed,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${order.total} XAF',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                  ],
                ),
              ],
              if (onAccept != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onAccept,
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Accepter la mission'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      ), // Card
      if (order != null && order.isPreorder)
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
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
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
      ], // Stack children
    ); // Stack
  }
}
