import 'package:flutter_test/flutter_test.dart';
import 'package:lilia_food_delivery/models/app_user.dart';

/// Les trois statuts du livreur, et ce que l'application en déduit.
///
/// L'écran de profil affichait « Statut compte : **Actif** » écrit en dur : un
/// livreur suspendu le voyait en vert pendant que toutes ses requêtes
/// recevaient un 403, et une liste de missions vide était indiscernable d'une
/// journée creuse. Ces tests fixent la lecture des trois champs et la règle qui
/// dit si le livreur peut réellement recevoir une course.
void main() {
  Map<String, dynamic> user({
    String? statusUser = 'ACTIVE',
    Map<String, dynamic>? profile = const {'isActive': true, 'vehicleType': 'MOTO'},
  }) => {
    'id': 'u1',
    'firebaseUid': 'fb1',
    'nom': 'Jean Mabiala',
    'email': 'jean@example.cg',
    'phone': '061234567',
    'role': 'LIVREUR',
    'driverStatus': 'AVAILABLE',
    if (statusUser != null) 'statusUser': statusUser,
    if (profile != null) 'driverProfile': profile,
  };

  group('AppUser.fromJson', () {
    test('lit le nom réel, pas le repli « Livreur »', () {
      expect(AppUser.fromJson(user()).nom, 'Jean Mabiala');
    });

    test('lit les trois statuts séparément', () {
      final u = AppUser.fromJson(user());
      expect(u.statusUser, AccountStatus.active);
      expect(u.driverProfile?.isActive, isTrue);
      expect(u.driverStatus, DriverStatus.available);
    });

    /// Une app plus récente que le serveur ne doit pas inventer un statut.
    /// `unknown` se lit « on ne sait pas » ; retomber sur `active` afficherait
    /// un compte valide sans en avoir la moindre preuve.
    test('statusUser absent ou inconnu → unknown, jamais active', () {
      expect(AppUser.fromJson(user(statusUser: null)).statusUser,
          AccountStatus.unknown);
      expect(AppUser.fromJson(user(statusUser: 'SOMETHING_NEW')).statusUser,
          AccountStatus.unknown);
    });

    test('profil absent → null, sans planter', () {
      expect(AppUser.fromJson(user(profile: null)).driverProfile, isNull);
    });

    test('lit le véhicule, la plaque et les zones', () {
      final u = AppUser.fromJson(user(profile: {
        'isActive': true,
        'vehicleType': 'VOITURE',
        'plateNumber': 'BZV-1234',
        'zones': [
          {'id': 'q1', 'nom': 'Bacongo'},
          {'id': 'q2', 'nom': 'Poto-Poto'},
        ],
      }));
      expect(u.driverProfile!.vehicleType, VehicleType.voiture);
      expect(u.driverProfile!.plateNumber, 'BZV-1234');
      expect(u.driverProfile!.zones, ['Bacongo', 'Poto-Poto']);
    });

    test('véhicule inconnu → moto (cas dominant à Brazzaville)', () {
      final u = AppUser.fromJson(
        user(profile: {'isActive': true, 'vehicleType': 'HELICOPTERE'}),
      );
      expect(u.driverProfile!.vehicleType, VehicleType.moto);
    });
  });

  group('canReceiveMissions — reprend assertAssignable côté serveur', () {
    test('compte actif + profil actif → oui', () {
      expect(AppUser.fromJson(user()).canReceiveMissions, isTrue);
    });

    test('compte suspendu → non, même avec un profil actif', () {
      expect(
        AppUser.fromJson(user(statusUser: 'BLOCKED')).canReceiveMissions,
        isFalse,
      );
    });

    test('profil inactif → non, même avec un compte actif', () {
      expect(
        AppUser.fromJson(
          user(profile: {'isActive': false, 'vehicleType': 'MOTO'}),
        ).canReceiveMissions,
        isFalse,
      );
    });

    test('aucun profil → non', () {
      expect(AppUser.fromJson(user(profile: null)).canReceiveMissions, isFalse);
    });

    /// Un livreur hors ligne garde un compte et un profil valides : il a
    /// simplement fini sa journée. Ce n'est ni une sanction ni une anomalie,
    /// et l'application ne doit pas afficher de bandeau d'alerte.
    test('hors ligne mais compte et profil actifs → oui', () {
      final json = user()..['driverStatus'] = 'OFFLINE';
      final u = AppUser.fromJson(json);
      expect(u.driverStatus, DriverStatus.offline);
      expect(u.canReceiveMissions, isTrue);
    });
  });

  group('licenseExpiringSoon', () {
    DriverProfile withExpiry(DateTime? d) => DriverProfile.fromJson({
      'isActive': true,
      'vehicleType': 'MOTO',
      if (d != null) 'licenseExpiry': d.toIso8601String(),
    });

    test('sans date → pas d’alerte', () {
      expect(withExpiry(null).licenseExpiringSoon, isFalse);
    });

    test('dans 10 jours → alerte', () {
      expect(
        withExpiry(DateTime.now().add(const Duration(days: 10)))
            .licenseExpiringSoon,
        isTrue,
      );
    });

    test('déjà expiré → alerte', () {
      expect(
        withExpiry(DateTime.now().subtract(const Duration(days: 1)))
            .licenseExpiringSoon,
        isTrue,
      );
    });

    test('dans 6 mois → pas d’alerte', () {
      expect(
        withExpiry(DateTime.now().add(const Duration(days: 180)))
            .licenseExpiringSoon,
        isFalse,
      );
    });
  });
}
