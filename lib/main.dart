import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'screens/shift_form_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ShiftPlannerApp());
}

class ShiftPlannerApp extends StatelessWidget {
  const ShiftPlannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'シフト希望表',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      locale: const Locale('ja', 'JP'),
      // Required so widgets like showDatePicker() can render Japanese
      // (and any other locale's) text/labels correctly instead of
      // silently failing to build (which looked like a stuck grey
      // overlay when the calendar icon was tapped).
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ja', 'JP'), Locale('en', 'US')],
      home: const ShiftFormScreen(),
    );
  }
}
