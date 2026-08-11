import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shitu_app/theme/tokens.dart';

ThemeData buildShituTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppTokens.primary,
      primary: AppTokens.primary,
      surface: AppTokens.bgSurface,
      error: AppTokens.danger,
    ),
    scaffoldBackgroundColor: AppTokens.bgPage,
  );

  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: AppTokens.bgSurface,
      foregroundColor: AppTokens.textPrimary,
      elevation: 0,
      centerTitle: true,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      titleTextStyle: TextStyle(
        color: AppTokens.primary,
        fontSize: 28,
        fontWeight: FontWeight.w700,
      ),
    ),
    textTheme: base.textTheme.apply(
      bodyColor: AppTokens.textPrimary,
      displayColor: AppTokens.textPrimary,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTokens.primary,
        foregroundColor: AppTokens.textOnPrimary,
        minimumSize: const Size(54, 54),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        ),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
    ),
  );
}
