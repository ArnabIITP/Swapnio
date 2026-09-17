import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  // Sahara - Warm Minimalism Palette
  static const Color primaryColor = Color(0xFFC2652A); // Burnt sienna
  static const Color backgroundLight = Color(0xFFFAF5EE); // Warm linen
  static const Color backgroundDarker = Color(0xFFF6F0E8); // surface_container_low
  static const Color tertiaryColor = Color(0xFF8C3C3C); // Dusty rose
  static const Color warmBorder = Color(0x99D8D0C8); // #d8d0c8 at 60% opacity
  static const Color darkTextColor = Color(0xFF3A302A); // warm dark gray
  static const Color warmMutedText = Color(0xFF9A9088);
  // Dark (night) palette - Sahara in the dark
  static const Color darkBackground = Color(0xFF2A211D);
  static const Color darkSurface = Color(0xFF3A2E28);
  static const Color darkText = Color(0xFFF2E9DF);
  static const Color darkBorder = Color(0x66D8D0C8);

  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    primaryColor: primaryColor,
    scaffoldBackgroundColor: backgroundLight,
    
    colorScheme: const ColorScheme.light(
      primary: primaryColor,
      onPrimary: Colors.white,
      secondary: tertiaryColor,
      onSecondary: Colors.white,
      error: Color(0xFFC0392B),
      surface: Colors.white,
      onSurface: darkTextColor,
    ),

    // Typography
    textTheme: GoogleFonts.manropeTextTheme(ThemeData.light().textTheme).apply(
      bodyColor: darkTextColor,
      displayColor: darkTextColor,
    ).copyWith(
      displayLarge: GoogleFonts.ebGaramond(color: darkTextColor, fontWeight: FontWeight.bold),
      displayMedium: GoogleFonts.ebGaramond(color: darkTextColor, fontWeight: FontWeight.bold),
      displaySmall: GoogleFonts.ebGaramond(color: darkTextColor, fontWeight: FontWeight.bold),
      headlineLarge: GoogleFonts.ebGaramond(color: darkTextColor, fontWeight: FontWeight.bold),
      headlineMedium: GoogleFonts.ebGaramond(color: darkTextColor, fontWeight: FontWeight.bold),
      headlineSmall: GoogleFonts.ebGaramond(color: darkTextColor, fontWeight: FontWeight.w600),
      titleLarge: GoogleFonts.ebGaramond(color: darkTextColor, fontWeight: FontWeight.w600),
      titleMedium: GoogleFonts.ebGaramond(color: darkTextColor, fontWeight: FontWeight.w600),
    ),

    appBarTheme: AppBarTheme(
      backgroundColor: backgroundLight,
      foregroundColor: darkTextColor,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: GoogleFonts.ebGaramond(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: darkTextColor,
        letterSpacing: 0,
      ),
      iconTheme: const IconThemeData(color: primaryColor),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        textStyle: GoogleFonts.manrope(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        elevation: 0,
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryColor,
        side: const BorderSide(color: warmBorder, width: 1.5),
        textStyle: GoogleFonts.manrope(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryColor,
        textStyle: GoogleFonts.manrope(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: warmBorder, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: warmBorder, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: primaryColor, width: 2),
      ),
      hintStyle: GoogleFonts.manrope(
        color: const Color(0xFF9A9088),
      ),
    ),

    iconTheme: const IconThemeData(
      color: primaryColor,
    ),

    tabBarTheme: TabBarThemeData(
      labelColor: primaryColor,
      unselectedLabelColor: warmMutedText,
      labelStyle: GoogleFonts.manrope(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: GoogleFonts.manrope(
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      indicatorColor: primaryColor,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: Colors.transparent,
      dividerHeight: 0,
    ),
  );
  
  // Sahara - Dark theme
  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    primaryColor: primaryColor,
    scaffoldBackgroundColor: darkBackground,

    colorScheme: const ColorScheme.dark(
      primary: Color(0xFFD9864F),
      onPrimary: Colors.black,
      secondary: Color(0xFFB86A6A),
      onSecondary: Colors.white,
      error: Color(0xFFC0392B),
      surface: darkSurface,
      onSurface: darkText,
    ),

    // Typography
    textTheme: GoogleFonts.manropeTextTheme(ThemeData.light().textTheme).apply(
      bodyColor: darkText,
      displayColor: darkText,
    ).copyWith(
      displayLarge: GoogleFonts.ebGaramond(color: darkText, fontWeight: FontWeight.bold),
      displayMedium: GoogleFonts.ebGaramond(color: darkText, fontWeight: FontWeight.bold),
      displaySmall: GoogleFonts.ebGaramond(color: darkText, fontWeight: FontWeight.bold),
      headlineLarge: GoogleFonts.ebGaramond(color: darkText, fontWeight: FontWeight.bold),
      headlineMedium: GoogleFonts.ebGaramond(color: darkText, fontWeight: FontWeight.bold),
      headlineSmall: GoogleFonts.ebGaramond(color: darkText, fontWeight: FontWeight.w600),
      titleLarge: GoogleFonts.ebGaramond(color: darkText, fontWeight: FontWeight.w600),
      titleMedium: GoogleFonts.ebGaramond(color: darkText, fontWeight: FontWeight.w600),
    ),

    appBarTheme: AppBarTheme(
      backgroundColor: darkBackground,
      foregroundColor: darkText,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: GoogleFonts.ebGaramond(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: darkText,
        letterSpacing: 0,
      ),
      iconTheme: const IconThemeData(color: primaryColor),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: Colors.black,
        textStyle: GoogleFonts.manrope(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        elevation: 0,
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryColor,
        side: const BorderSide(color: darkBorder, width: 1.5),
        textStyle: GoogleFonts.manrope(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryColor,
        textStyle: GoogleFonts.manrope(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: darkBorder, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: darkBorder, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: primaryColor, width: 2),
      ),
      hintStyle: GoogleFonts.manrope(
        color: warmMutedText,
      ),
    ),

    iconTheme: const IconThemeData(
      color: primaryColor,
    ),

    tabBarTheme: TabBarThemeData(
      labelColor: Color(0xFFD9864F),
      unselectedLabelColor: warmMutedText,
      labelStyle: GoogleFonts.manrope(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: GoogleFonts.manrope(
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      indicatorColor: Color(0xFFD9864F),
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: Colors.transparent,
      dividerHeight: 0,
    ),
  );

  // Custom soft shadow typically used in containers
  static final List<BoxShadow> softShadow = [
    BoxShadow(
      color: const Color(0xFF3A302A).withValues(alpha: 0.04), // rgba(58, 48, 42, 0.04)
      blurRadius: 16,
      spreadRadius: 0,
      offset: const Offset(0, 2),
    ),
  ];
}
