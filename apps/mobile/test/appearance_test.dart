import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:refract/design_system/appearance.dart';
import 'package:refract/design_system/theme.dart';
import 'package:refract/features/settings/settings_page.dart';

void main() {
  testWidgets('appearance selection persists and can be restored', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: SettingsPage())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect((await SharedPreferences.getInstance()).getString('appearance_theme'), 'dark');
    final dark = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Dark'));
    expect(dark.selected, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: SettingsPage())));
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Dark')).selected, isTrue);
  });

  test('light and dark themes provide distinct readable surfaces', () {
    final light = RefractTheme.light();
    final dark = RefractTheme.dark();
    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.colorScheme.onSurface.computeLuminance(), lessThan(light.colorScheme.surface.computeLuminance()));
    expect(dark.colorScheme.onSurface.computeLuminance(), greaterThan(dark.colorScheme.surface.computeLuminance()));
    expect(appearanceProvider, isNotNull);
  });
}
