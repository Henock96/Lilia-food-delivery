import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../utilities/app_theme.dart';
import '../../../../models/delivery_failure.dart';
import '../../application/deliveries_controller.dart';
import '../../data/delivery_repository.dart';

/// « Problème » sur une course en cours (F3-05).
///
/// Rend `true` quand un échec a été déclaré (l'écran de course se ferme).
/// Le livreur **déclare** ; c'est l'administration qui décide qui en répond,
/// donc s'il est payé pour la course.
Future<bool> showDeliveryIssueSheet(
  BuildContext context, {
  required String deliveryId,
  required String? clientPhone,
}) async {
  final declared = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        _IssueSheet(deliveryId: deliveryId, clientPhone: clientPhone),
  );
  return declared ?? false;
}

class _IssueSheet extends ConsumerStatefulWidget {
  final String deliveryId;
  final String? clientPhone;
  const _IssueSheet({required this.deliveryId, required this.clientPhone});

  @override
  ConsumerState<_IssueSheet> createState() => _IssueSheetState();
}

class _IssueSheetState extends ConsumerState<_IssueSheet> {
  DeliveryFailureReason? _reason;
  UnreachableProtocol? _protocol;
  Timer? _timer;
  bool _busy = false;
  String? _error;
  final _note = TextEditingController();

  @override
  void dispose() {
    _timer?.cancel();
    _note.dispose();
    super.dispose();
  }

  DeliveryRepository get _repo => ref.read(deliveryRepositoryProvider);

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setProtocol(UnreachableProtocol p) {
    setState(() => _protocol = p);
    _timer?.cancel();
    if (p.waitRemainingSeconds > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return t.cancel();
        setState(() => _protocol = _protocol?.tick());
        if ((_protocol?.waitRemainingSeconds ?? 0) == 0) t.cancel();
      });
    }
  }

  Future<void> _choose(DeliveryFailureReason reason) async {
    setState(() => _reason = reason);
    if (reason == DeliveryFailureReason.customerUnreachable) {
      // Démarre (ou reprend) le protocole : SMS au client, minuteur.
      await _run(
        () async =>
            _setProtocol(await _repo.startUnreachable(widget.deliveryId)),
      );
    }
  }

  Future<void> _call() async {
    final phone = widget.clientPhone;
    if (phone == null) return;
    await _run(() async {
      // Journalisé AVANT de composer : l'appel part vers une autre app, et on
      // ne sait pas quand (ni si) le livreur reviendra.
      _setProtocol(await _repo.logCall(widget.deliveryId));
      // `launchUrl` directement : `canLaunchUrl('tel:')` répond « non » sans
      // déclaration de requêtes, alors que l'appel fonctionne (ACTION_VIEW).
      await launchUrl(Uri.parse('tel:$phone'));
    });
  }

  Future<void> _declare() async {
    final reason = _reason;
    if (reason == null) return;
    await _run(() async {
      await ref
          .read(deliveryDetailControllerProvider(widget.deliveryId).notifier)
          .declareFailure(reason, note: _note.text);
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final reason = _reason;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              reason == null ? 'Quel est le problème ?' : reason.label,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (reason == null)
              for (final r in DeliveryFailureReason.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(r.label),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : () => _choose(r),
                )
            else ...[
              if (reason == DeliveryFailureReason.customerUnreachable)
                _ProtocolView(
                  protocol: _protocol,
                  canCall: widget.clientPhone != null,
                  busy: _busy,
                  onCall: _call,
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Précisions (facultatif)',
                  border: OutlineInputBorder(),
                ),
              ),
              const Text(
                'L’administration décide ensuite qui répond de l’échec — '
                'et donc si la course vous est payée.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.error,
                  ),
                  onPressed:
                      _busy ||
                          (reason ==
                                  DeliveryFailureReason.customerUnreachable &&
                              !(_protocol?.canDeclare ?? false))
                      ? null
                      : _declare,
                  child: const Text('Déclarer l’échec'),
                ),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _reason = null;
                        _error = null;
                      }),
                child: const Text('Choisir un autre problème'),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProtocolView extends StatelessWidget {
  final UnreachableProtocol? protocol;
  final bool canCall;
  final bool busy;
  final VoidCallback onCall;

  const _ProtocolView({
    required this.protocol,
    required this.canCall,
    required this.busy,
    required this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    final p = protocol;
    if (p == null) return const LinearProgressIndicator();
    final minutes = p.waitRemainingSeconds ~/ 60;
    final seconds = (p.waitRemainingSeconds % 60).toString().padLeft(2, '0');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          p.smsSent
              ? '✓ Un SMS a prévenu le client que vous êtes devant chez lui.'
              : 'Le SMS au client n’a pas pu partir : appelez-le.',
        ),
        const SizedBox(height: 8),
        Text(
          'Appels : ${p.callAttempts} / ${UnreachableProtocol.minCallAttempts} minimum',
        ),
        Text(
          p.waitRemainingSeconds > 0
              ? 'Attendez encore $minutes:$seconds avant de déclarer.'
              : 'Attente écoulée.',
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: canCall && !busy ? onCall : null,
          icon: const Icon(Icons.phone),
          label: Text(canCall ? 'Appeler le client' : 'Numéro indisponible'),
        ),
      ],
    );
  }
}
