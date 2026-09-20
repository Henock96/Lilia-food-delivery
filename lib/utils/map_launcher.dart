import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Ouverture d'un itinéraire dans l'application de guidage du téléphone.
///
/// ## Pourquoi ce fichier existe
///
/// L'écran de livraison affichait la destination — adresse, repères, point sur
/// une carte encastrée — mais ne permettait pas de **lancer le guidage**. Le
/// livreur lisait « Rue Bayonne, Moungali » puis rouvrait Google Maps à la
/// main pour retaper l'adresse. La carte encastrée sert à situer, pas à
/// conduire.
///
/// ## Deux façons de viser, dans cet ordre
///
/// 1. **Par coordonnées**, quand la commande en porte. C'est le cas nominal :
///    le client a posé son point, ou le serveur a résolu le centroïde de son
///    quartier.
/// 2. **Par texte**, sinon. Une destination `UNKNOWN` n'a aucune coordonnée,
///    mais elle a une adresse lisible. Laisser le bouton inactif dans ce cas
///    reviendrait à rendre le trajet plus difficile précisément quand il l'est
///    déjà — mieux vaut ouvrir une recherche que ne rien ouvrir.
///
/// ## Android 11+
///
/// `canLaunchUrl` ne renvoie `true` que si l'`AndroidManifest` déclare les
/// schémas visés dans `<queries>`. Sans cette déclaration, tous les appels
/// ci-dessous échouent **en silence** et le bouton paraît cassé. Le manifeste
/// de cette application les déclare — ne pas les retirer.
class MapLauncher {
  MapLauncher._();

  /// Ouvre le guidage vers une destination.
  ///
  /// [latitude] / [longitude] : position de la destination, `null` si le
  /// serveur n'a pas su la résoudre. [address] sert alors de repli, et de
  /// libellé du point dans tous les cas.
  ///
  /// Renvoie `false` si aucune application n'a pu être ouverte — l'appelant
  /// doit alors le dire au livreur plutôt que de laisser le tap sans effet.
  static Future<bool> openNavigation({
    double? latitude,
    double? longitude,
    String? address,
  }) async {
    final hasCoordinates = latitude != null && longitude != null;
    if (!hasCoordinates && (address == null || address.trim().isEmpty)) {
      return false;
    }

    final label = (address == null || address.trim().isEmpty)
        ? 'Destination'
        : address.trim();

    for (final uri in _candidates(
      latitude: latitude,
      longitude: longitude,
      label: label,
    )) {
      if (await _tryLaunch(uri)) return true;
    }
    return false;
  }

  /// Les cibles à essayer, de la plus précise à la plus universelle.
  ///
  /// L'ordre compte : `google.navigation:` démarre le guidage tourne-à-tourne
  /// directement, `geo:` ouvre la carte sur le point, l'URL web ouvre le
  /// navigateur. Le premier qui répond gagne.
  static List<Uri> _candidates({
    required double? latitude,
    required double? longitude,
    required String label,
  }) {
    final encodedLabel = Uri.encodeComponent(label);
    final uris = <Uri>[];

    if (latitude != null && longitude != null) {
      final point = '$latitude,$longitude';

      if (!kIsWeb && Platform.isAndroid) {
        uris.add(Uri.parse('google.navigation:q=$point&mode=d'));
        uris.add(Uri.parse('geo:$point?q=$point($encodedLabel)'));
      }
      if (!kIsWeb && Platform.isIOS) {
        uris.add(
          Uri.parse('comgooglemaps://?daddr=$point&directionsmode=driving'),
        );
        // Apple Plans est préinstallé sur tout iPhone : c'est le seul repli
        // natif dont la présence est garantie.
        uris.add(Uri.parse('maps://?daddr=$point&dirflg=d'));
      }
      uris.add(
        Uri.parse(
          'https://www.google.com/maps/dir/?api=1&destination=$point',
        ),
      );
      return uris;
    }

    // Aucune coordonnée : on vise le texte. Le guidage n'est pas garanti —
    // Google peut ne pas reconnaître l'adresse à Brazzaville — mais la
    // recherche s'ouvre pré-remplie, ce qui économise la saisie.
    if (!kIsWeb && Platform.isAndroid) {
      uris.add(Uri.parse('geo:0,0?q=$encodedLabel'));
    }
    if (!kIsWeb && Platform.isIOS) {
      uris.add(Uri.parse('comgooglemaps://?daddr=$encodedLabel'));
      uris.add(Uri.parse('maps://?daddr=$encodedLabel'));
    }
    uris.add(
      Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$encodedLabel',
      ),
    );
    return uris;
  }

  /// Tente une cible. Une exception de plateforme n'est pas une erreur ici :
  /// elle veut dire « pas d'application pour ça », et on passe à la suivante.
  static Future<bool> _tryLaunch(Uri uri) async {
    try {
      if (!await canLaunchUrl(uri)) return false;
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('MapLauncher — échec sur $uri : $e');
      return false;
    }
  }
}
