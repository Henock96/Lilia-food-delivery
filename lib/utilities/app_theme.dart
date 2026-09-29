import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Couleurs de l'app livreur.
///
/// Phase 3 UI/UX (29/09/2026) — contrastes WCAG AA, calculés : l'app se lit
/// en plein soleil, sur la route.
/// - `primary` #FF6B00 + blanc = 2,86:1 sur **tous** les boutons ; aligné sur
///   l'orange d'action de l'app client (`orange600` #C8421A, 4,94:1) ;
/// - `textLight` #9E9E9E = 2,68:1 sur blanc → #6E6E6E ;
/// - `success` / `error` Material (2,78 et 3,68:1 sous du blanc) → teintes
///   foncées ≥ 4,5:1, lisibles en texte comme en fond.
/// Garde : `test/utilities/contrast_test.dart`.
class AppColors {
  static const primary = Color(0xFFC8421A);
  static const primaryDark = Color(0xFF9E3012);
  static const surface = Color(0xFFF8F8F8);
  static const cardBg = Color(0xFFFFFFFF);
  static const textDark = Color(0xFF1A1A1A);
  static const textMed = Color(0xFF6B6B6B);
  static const textLight = Color(0xFF6E6E6E);
  static const success = Color(0xFF2E7D32);
  static const warning = Color(0xFFFFC107);
  static const error = Color(0xFFC62828);
  static const border = Color(0xFFEEEEEE);
}

class AppTheme {
  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
    ),
    textTheme: GoogleFonts.poppinsTextTheme(),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.cardBg,
      foregroundColor: AppColors.textDark,
      elevation: 0,
      centerTitle: true,
    ),
    scaffoldBackgroundColor: AppColors.surface,
    cardTheme: const CardThemeData(
      color: AppColors.cardBg,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: AppColors.border),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
    ),
  );
}
