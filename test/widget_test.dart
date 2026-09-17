import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:swapnio/Screen/Auth/Startpage.dart';
import 'package:swapnio/theme.dart';

void main() {
  setUpAll(() {
    // Keep font resolution deterministic inside tests (no network fetch).
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('Starter page shows Swapnio branding', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: const StarterPage(),
    ));

    expect(find.text('Swapnio'), findsOneWidget);
    expect(find.text('Welcome to Swapnio!'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Create an account'), findsOneWidget);
  });
}