import 'package:flutter/material.dart';
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
      home: const ShiftFormScreen(),
    );
  }
}
