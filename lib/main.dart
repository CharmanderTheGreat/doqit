import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/notifications/notification_service.dart';
import 'core/theme/app_theme.dart';
import 'features/notes/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  runApp(const ProviderScope(child: DoqitApp()));
}

class DoqitApp extends StatelessWidget {
  const DoqitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Doqit',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const HomeScreen(),
    );
  }
}