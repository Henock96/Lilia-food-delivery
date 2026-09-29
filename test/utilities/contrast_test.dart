// Contrastes WCAG AA de l'app livreur (Phase 3 UI/UX, 29/09/2026).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilia_food_delivery/utilities/app_theme.dart';

double contrastRatio(Color a, Color b) {
  double lum(Color c) {
    double ch(double v) => v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  final la = lum(a), lb = lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

const _blanc = Color(0xFFFFFFFF);

void main() {
  test('boutons : blanc sur primary ≥ 4,5:1', () {
    expect(contrastRatio(_blanc, AppColors.primary), greaterThanOrEqualTo(4.5));
  });

  test('onPrimary du thème réellement appliqué ≥ 4,5:1', () {
    final cs = AppTheme.theme.colorScheme;
    expect(contrastRatio(cs.onPrimary, cs.primary), greaterThanOrEqualTo(4.5));
  });

  test('textes secondaires sur les deux fonds', () {
    for (final fg in [AppColors.textMed, AppColors.textLight]) {
      for (final bg in [AppColors.cardBg, AppColors.surface]) {
        expect(
          contrastRatio(fg, bg),
          greaterThanOrEqualTo(4.5),
          reason: '$fg sur $bg',
        );
      }
    }
  });

  test('succès / erreur : lisibles en texte et sous du blanc', () {
    for (final c in [AppColors.success, AppColors.error, AppColors.primary]) {
      expect(contrastRatio(c, AppColors.cardBg), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(_blanc, c), greaterThanOrEqualTo(4.5));
    }
  });
}
