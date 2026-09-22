import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Swapnio "Give / Get" palette: vermilion is what you teach, violet is what
/// you learn, lime is reserved for wins and live moments.
@immutable
class SwapnioColors extends ThemeExtension<SwapnioColors> {
  final Color bg;
  final Color surface;
  final Color surfaceLow;
  final Color ink;
  final Color text;
  final Color textMuted;
  final Color border;
  final Color give;
  final Color get;
  final Color win;
  final Color onWin;
  final Color cta;
  final Color onCta;
  final Color success;

  const SwapnioColors({
    required this.bg,
    required this.surface,
    required this.surfaceLow,
    required this.ink,
    required this.text,
    required this.textMuted,
    required this.border,
    required this.give,
    required this.get,
    required this.win,
    required this.onWin,
    required this.cta,
    required this.onCta,
    required this.success,
  });

  static const light = SwapnioColors(
    bg: Color(0xFFF3F0E8),
    surface: Color(0xFFFFFFFF),
    surfaceLow: Color(0xFFEAE6DC),
    ink: Color(0xFF17142B),
    text: Color(0xFF17142B),
    textMuted: Color(0xFF6E6A7C),
    border: Color(0xFFDDD8CC),
    give: Color(0xFFFF5A36),
    get: Color(0xFF6C5CE7),
    win: Color(0xFFD4F25A),
    onWin: Color(0xFF17142B),
    cta: Color(0xFF17142B),
    onCta: Color(0xFFFFFFFF),
    success: Color(0xFF2F9E6A),
  );

  static const dark = SwapnioColors(
    bg: Color(0xFF0E0C17),
    surface: Color(0xFF1A1726),
    surfaceLow: Color(0xFF262236),
    ink: Color(0xFF2B2645),
    text: Color(0xFFF3F0E8),
    textMuted: Color(0xFF9A96AB),
    border: Color(0xFF2E2A40),
    give: Color(0xFFFF6B4A),
    get: Color(0xFF8B7DFF),
    win: Color(0xFFD4F25A),
    onWin: Color(0xFF17142B),
    cta: Color(0xFFF3F0E8),
    onCta: Color(0xFF17142B),
    success: Color(0xFF4CC38A),
  );

  @override
  SwapnioColors copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceLow,
    Color? ink,
    Color? text,
    Color? textMuted,
    Color? border,
    Color? give,
    Color? get,
    Color? win,
    Color? onWin,
    Color? cta,
    Color? onCta,
    Color? success,
  }) =>
      SwapnioColors(
        bg: bg ?? this.bg,
        surface: surface ?? this.surface,
        surfaceLow: surfaceLow ?? this.surfaceLow,
        ink: ink ?? this.ink,
        text: text ?? this.text,
        textMuted: textMuted ?? this.textMuted,
        border: border ?? this.border,
        give: give ?? this.give,
        get: get ?? this.get,
        win: win ?? this.win,
        onWin: onWin ?? this.onWin,
        cta: cta ?? this.cta,
        onCta: onCta ?? this.onCta,
        success: success ?? this.success,
      );

  @override
  SwapnioColors lerp(ThemeExtension<SwapnioColors>? other, double t) {
    if (other is! SwapnioColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return SwapnioColors(
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      surfaceLow: l(surfaceLow, other.surfaceLow),
      ink: l(ink, other.ink),
      text: l(text, other.text),
      textMuted: l(textMuted, other.textMuted),
      border: l(border, other.border),
      give: l(give, other.give),
      get: l(get, other.get),
      win: l(win, other.win),
      onWin: l(onWin, other.onWin),
      cta: l(cta, other.cta),
      onCta: l(onCta, other.onCta),
      success: l(success, other.success),
    );
  }
}

extension SwapnioContext on BuildContext {
  SwapnioColors get sw =>
      Theme.of(this).extension<SwapnioColors>() ?? SwapnioColors.light;
}

class AppTheme {
  AppTheme._();

  // Static aliases kept for screens that predate the theme extension. They
  // resolve to the light palette; theme-aware code should use `context.sw`.
  static const Color primaryColor = Color(0xFFFF5A36);
  static const Color giveColor = Color(0xFFFF5A36);
  static const Color getColor = Color(0xFF6C5CE7);
  static const Color winColor = Color(0xFFD4F25A);
  static const Color inkColor = Color(0xFF17142B);
  static const Color backgroundLight = Color(0xFFF3F0E8);
  static const Color backgroundDarker = Color(0xFFEAE6DC);
  static const Color tertiaryColor = Color(0xFF6C5CE7);
  static const Color warmBorder = Color(0x99DDD8CC);
  static const Color darkTextColor = Color(0xFF17142B);
  static const Color warmMutedText = Color(0xFF6E6A7C);
  static const Color darkBackground = Color(0xFF0E0C17);
  static const Color darkSurface = Color(0xFF1A1726);
  static const Color darkText = Color(0xFFF3F0E8);
  static const Color darkBorder = Color(0xFF2E2A40);

  static TextStyle display({
    double fontSize = 28,
    Color? color,
    FontWeight fontWeight = FontWeight.w700,
    double? height,
  }) =>
      GoogleFonts.fraunces(
        fontSize: fontSize,
        color: color,
        fontWeight: fontWeight,
        height: height,
      );

  static TextStyle label({
    double fontSize = 11,
    Color? color,
    FontWeight fontWeight = FontWeight.w800,
  }) =>
      GoogleFonts.manrope(
        fontSize: fontSize,
        color: color,
        fontWeight: fontWeight,
        letterSpacing: 1.2,
      );

  static ThemeData _build(SwapnioColors c, Brightness b) {
    final base = b == Brightness.dark ? ThemeData.dark() : ThemeData.light();
    final radius = BorderRadius.circular(16);
    TextStyle disp(FontWeight w) => GoogleFonts.fraunces(color: c.text, fontWeight: w);
    return ThemeData(
      useMaterial3: true,
      brightness: b,
      primaryColor: c.give,
      scaffoldBackgroundColor: c.bg,
      extensions: [c],
      colorScheme: (b == Brightness.dark
              ? const ColorScheme.dark()
              : const ColorScheme.light())
          .copyWith(
        primary: c.give,
        onPrimary: Colors.white,
        secondary: c.get,
        onSecondary: Colors.white,
        tertiary: c.win,
        onTertiary: c.onWin,
        error: const Color(0xFFD64545),
        surface: c.surface,
        onSurface: c.text,
        surfaceContainerLowest: c.surface,
        surfaceContainerLow: c.surfaceLow,
        surfaceContainer: c.surfaceLow,
        surfaceContainerHigh: c.surfaceLow,
        outline: c.border,
        outlineVariant: c.border,
      ),
      textTheme: GoogleFonts.manropeTextTheme(base.textTheme)
          .apply(bodyColor: c.text, displayColor: c.text)
          .copyWith(
            displayLarge: disp(FontWeight.w700),
            displayMedium: disp(FontWeight.w700),
            displaySmall: disp(FontWeight.w700),
            headlineLarge: disp(FontWeight.w700),
            headlineMedium: disp(FontWeight.w700),
            headlineSmall: disp(FontWeight.w600),
            titleLarge: disp(FontWeight.w600),
            titleMedium: disp(FontWeight.w600),
          ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.bg,
        foregroundColor: c.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        titleTextStyle: GoogleFonts.fraunces(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: c.text,
        ),
        iconTheme: IconThemeData(color: c.text),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.cta,
          foregroundColor: c.onCta,
          textStyle: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(borderRadius: radius),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          elevation: 0,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.cta,
          foregroundColor: c.onCta,
          textStyle: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(borderRadius: radius),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.text,
          backgroundColor: c.surface,
          side: BorderSide(color: c.border, width: 1),
          textStyle: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: radius),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.give,
          textStyle: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c.border)),
        enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c.border)),
        focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c.get, width: 2)),
        hintStyle: GoogleFonts.manrope(color: c.textMuted),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surface,
        selectedColor: c.give,
        side: BorderSide(color: c.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        labelStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: c.text),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.cta,
        contentTextStyle: GoogleFonts.manrope(color: c.onCta, fontWeight: FontWeight.w600),
        actionTextColor: b == Brightness.dark ? c.give : c.win,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.give,
        linearTrackColor: c.surfaceLow,
      ),
      iconTheme: IconThemeData(color: c.text),
      dividerTheme: DividerThemeData(color: c.border, thickness: 1),
      tabBarTheme: TabBarThemeData(
        labelColor: c.text,
        unselectedLabelColor: c.textMuted,
        labelStyle: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w800),
        unselectedLabelStyle: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600),
        indicatorColor: c.give,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        dividerHeight: 0,
      ),
    );
  }

  static final ThemeData lightTheme = _build(SwapnioColors.light, Brightness.light);
  static final ThemeData darkTheme = _build(SwapnioColors.dark, Brightness.dark);

  static final List<BoxShadow> softShadow = [
    BoxShadow(
      color: const Color(0xFF17142B).withValues(alpha: 0.05),
      blurRadius: 18,
      offset: const Offset(0, 4),
    ),
  ];
}
