import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// EcoCharge visual identity: "Aero Meadow" — a 2000s Frutiger Aero take on
/// clean-energy tech. Bright sky-blue glass, glossy chrome highlights, and
/// living leaf-green accents. Bubbly, optimistic, tactile — dock-icon energy
/// orbs instead of flat material buttons, droplet ripples instead of
/// generic ink splashes.
class AppColors {
  // Base "sky" gradient the whole app sits on top of.
  static const Color skyTop = Color(0xFFDFF3FC);
  static const Color skyBottom = Color(0xFFF3FBFE);
  static const Color background = Color(0xFFEFF9FC);

  static const Color glass = Color(0xCCFFFFFF); // translucent glass panel fill
  static const Color glassHighlight = Color(0xF2FFFFFF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFE7F5FA);

  static const Color skyBlue = Color(0xFF4FC3F7); // primary — Aero glass blue
  static const Color deepAzure = Color(0xFF0A5A82); // ink / deep accent
  static const Color azureDark = Color(0xFF06405E);

  static const Color leafGreen = Color(0xFF5FBF60); // eco accent
  static const Color leafDark = Color(0xFF2F8F4E);
  static const Color leafPale = Color(0xFFE1F6E3);

  static const Color sunGlow = Color(0xFFFFCF4D); // energy/charge glow, ratings
  static const Color sunPale = Color(0xFFFFF3D6);

  static const Color chromeMist = Color(0xFFEAF6FA);
  static const Color dewWhite = Color(0xFFFFFFFF);

  static const Color textPrimary = Color(0xFF10333E);
  static const Color textSecondary = Color(0xFF4C7182);
  static const Color textMuted = Color(0xFF8FAFBB);

  static const Color success = Color(0xFF2F8F4E);
  static const Color error = Color(0xFFE6624B);
  static const Color divider = Color(0xFFCDEBF5);

  // Connector status colors
  static const Color statusAvailable = Color(0xFF2F8F4E);
  static const Color statusOccupied = Color(0xFFFFCF4D);
  static const Color statusOffline = Color(0xFFA9BFC7);

  static const LinearGradient skyGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [skyTop, skyBottom],
  );

  static const LinearGradient orbGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7FD8FA), skyBlue, Color(0xFF1E97D1)],
  );

  static const LinearGradient orbGradientGreen = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF9BE29C), leafGreen, leafDark],
  );

  static const LinearGradient chromeSheen = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x99FFFFFF), Color(0x00FFFFFF)],
  );
}

class AppTheme {
  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    final displayFont = GoogleFonts.baloo2TextTheme(base.textTheme);
    final bodyFont = GoogleFonts.nunitoSansTextTheme(base.textTheme);

    final textTheme = bodyFont
        .copyWith(
          displayLarge: displayFont.displayLarge,
          displayMedium: displayFont.displayMedium,
          displaySmall: displayFont.displaySmall,
          headlineLarge: displayFont.headlineLarge?.copyWith(fontWeight: FontWeight.w700),
          headlineMedium: displayFont.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
          headlineSmall: displayFont.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          titleLarge: displayFont.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          titleMedium: displayFont.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        )
        .apply(
          bodyColor: AppColors.textPrimary,
          displayColor: AppColors.textPrimary,
        );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.skyBlue,
        secondary: AppColors.leafGreen,
        tertiary: AppColors.sunGlow,
        surface: AppColors.surface,
        error: AppColors.error,
      ),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: AppColors.deepAzure),
        titleTextStyle: GoogleFonts.baloo2(
          color: AppColors.deepAzure,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.glass,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: BorderSide(color: AppColors.dewWhite.withValues(alpha: 0.8), width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.skyBlue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          textStyle: GoogleFonts.baloo2(fontSize: 16, fontWeight: FontWeight.w700),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.deepAzure,
          side: const BorderSide(color: AppColors.skyBlue, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          textStyle: GoogleFonts.baloo2(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.deepAzure,
          textStyle: GoogleFonts.nunitoSans(fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceMuted,
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: AppColors.skyBlue, width: 1.5),
        ),
        hintStyle: GoogleFonts.nunitoSans(color: AppColors.textMuted),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.dewWhite,
        selectedItemColor: AppColors.deepAzure,
        unselectedItemColor: AppColors.textMuted,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.divider, thickness: 1),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.chromeMist,
        labelStyle: GoogleFonts.nunitoSans(color: AppColors.deepAzure, fontWeight: FontWeight.w700),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    );
  }
}
