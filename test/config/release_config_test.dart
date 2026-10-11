import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Garde de configuration de release (DEL-004, DEL-006).
///
/// Ces tests lisent les fichiers natifs du dépôt : ils ne prouvent ni que le
/// push iOS arrive (clé APNs de la console Firebase), ni que la clé d'upload
/// Android est celle que Play attend. Ils empêchent seulement qu'une
/// configuration correcte se dégrade sans que la CI le voie.
void main() {
  String read(String path) => File(path).readAsStringSync();

  String apsEnvironment(String entitlements) {
    final match = RegExp(
      r'<key>aps-environment</key>\s*<string>([^<]+)</string>',
    ).firstMatch(read(entitlements));
    expect(match, isNotNull, reason: 'aps-environment absent de $entitlements');
    return match!.group(1)!;
  }

  group('iOS — push (DEL-004)', () {
    test('la config de distribution (Release) vise APNs production', () {
      expect(apsEnvironment('ios/Runner/RunnerRelease.entitlements'),
          'production');
    });

    test('Debug et Profile restent en sandbox, pour les essais sur appareil',
        () {
      expect(apsEnvironment('ios/Runner/Runner.entitlements'), 'development');
    });

    test('la configuration Release est bien câblée sur RunnerRelease', () {
      final pbx = read('ios/Runner.xcodeproj/project.pbxproj');
      final wired = RegExp(
        r'CODE_SIGN_ENTITLEMENTS = Runner/RunnerRelease\.entitlements;',
      ).allMatches(pbx);
      expect(wired, hasLength(1));
    });

    test('le mode arrière-plan des notifications est déclaré', () {
      expect(read('ios/Runner/Info.plist'), contains('remote-notification'));
    });
  });

  group('Android — signature (DEL-006)', () {
    test('keystore et mots de passe ne peuvent pas être versionnés', () {
      final root = read('.gitignore');
      final android = read('android/.gitignore');
      expect(root, contains('*.jks'));
      expect(root, contains('*.keystore'));
      expect('$root\n$android', contains('key.properties'));
    });

    test('le build release est signé par la config release, pas par la clé '
        'de debug', () {
      // Lignes commentées exclues : seule la configuration active compte.
      final gradle = read('android/app/build.gradle.kts')
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(
        gradle,
        contains('signingConfig = signingConfigs.getByName("release")'),
      );
      expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
    });
  });
}
