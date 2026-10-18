import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:nex_client/platform/theme_presets.dart';

void main() {
  test(
    'shared palette IDs, motifs, surfaces and base colors match the portable contract',
    () {
      final contract =
          jsonDecode(
                File('../../contracts/nex-portable-v1.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      final expected = (contract['palettes'] as List)
          .cast<Map<String, dynamic>>();
      expect(nexThemePresets.map((p) => p.id), expected.map((p) => p['id']));
      String? hex(Color? color) => color == null
          ? null
          : '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
      for (final preset in nexThemePresets) {
        final spec = expected.singleWhere((p) => p['id'] == preset.id);
        expect(hex(preset.seed), spec['seed'], reason: preset.id);
        expect(hex(preset.light), spec['light'], reason: preset.id);
        expect(hex(preset.dark), spec['dark'], reason: preset.id);
        expect(
          nexThemeTexture(preset.id).name,
          spec['texture'],
          reason: preset.id,
        );
      }
      final colors = <String, Color>{
        'bgPrimaryLight': NexColors.bgPrimaryLight,
        'bgCardLight': NexColors.bgCardLight,
        'bgElevatedLight': NexColors.bgElevatedLight,
        'textPrimaryLight': NexColors.textPrimaryLight,
        'textSecondaryLight': NexColors.textSecondaryLight,
        'borderLight': NexColors.borderLight,
        'borderSoftLight': NexColors.borderSoftLight,
        'bgPrimaryDark': NexColors.bgPrimaryDark,
        'bgCardDark': NexColors.bgCardDark,
        'bgElevatedDark': NexColors.bgElevatedDark,
        'textPrimaryDark': NexColors.textPrimaryDark,
        'textSecondaryDark': NexColors.textSecondaryDark,
        'borderDark': NexColors.borderDark,
        'borderSoftDark': NexColors.borderSoftDark,
        'bgPrimaryLightComfort': NexColors.bgPrimaryLightComfort,
        'bgCardLightComfort': NexColors.bgCardLightComfort,
        'bgElevatedLightComfort': NexColors.bgElevatedLightComfort,
        'textPrimaryLightComfort': NexColors.textPrimaryLightComfort,
        'textSecondaryLightComfort': NexColors.textSecondaryLightComfort,
        'borderLightComfort': NexColors.borderLightComfort,
        'borderSoftLightComfort': NexColors.borderSoftLightComfort,
        'bgPrimaryDarkComfort': NexColors.bgPrimaryDarkComfort,
        'bgCardDarkComfort': NexColors.bgCardDarkComfort,
        'bgElevatedDarkComfort': NexColors.bgElevatedDarkComfort,
        'textPrimaryDarkComfort': NexColors.textPrimaryDarkComfort,
        'textSecondaryDarkComfort': NexColors.textSecondaryDarkComfort,
        'borderDarkComfort': NexColors.borderDarkComfort,
        'borderSoftDarkComfort': NexColors.borderSoftDarkComfort,
        'accentLight': NexColors.accentLight,
        'accentStrongLight': NexColors.accentStrongLight,
        'accentDark': NexColors.accentDark,
        'accentStrongDark': NexColors.accentStrongDark,
        'danger': NexColors.danger,
        'error': NexColors.error,
        'errorDark': NexColors.errorDark,
        'swipeAddTag': NexColors.swipeAddTag,
        'swipePin': NexColors.swipePin,
        'swipeRemind': NexColors.swipeRemind,
        'swipeShare': NexColors.swipeShare,
        'swipeAsk': NexColors.swipeAsk,
      };
      expect(
        colors.map((key, value) => MapEntry(key, hex(value))),
        contract['colors'],
      );
    },
  );
}
