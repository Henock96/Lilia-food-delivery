import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Demande au livreur le code de remise que le client lit dans son
/// application (Master Audit v1, F-06).
///
/// Rend le code saisi (4 chiffres), ou `null` si le livreur renonce. La
/// vérification elle-même est faite par le serveur : cette boîte ne contrôle
/// que la forme, pour éviter un aller-retour réseau sur une faute de frappe.
Future<String?> showHandoverCodeDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const HandoverCodeDialog(),
  );
}

class HandoverCodeDialog extends StatefulWidget {
  const HandoverCodeDialog({super.key});

  @override
  State<HandoverCodeDialog> createState() => _HandoverCodeDialogState();
}

class _HandoverCodeDialogState extends State<HandoverCodeDialog> {
  final _controller = TextEditingController();

  bool get _complete => RegExp(r'^\d{4}$').hasMatch(_controller.text);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_complete) Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Code de remise'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Demandez au client le code à 4 chiffres affiché dans son '
            'application Lilia Food, puis saisissez-le.',
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('handover-code-field'),
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 4,
            style: const TextStyle(fontSize: 28, letterSpacing: 12),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              counterText: '',
              hintText: '••••',
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('handover-code-submit'),
          onPressed: _complete ? _submit : null,
          child: const Text('Valider la livraison'),
        ),
      ],
    );
  }
}
