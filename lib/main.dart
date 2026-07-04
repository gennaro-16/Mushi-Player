import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'screens/player_screen.dart';
import 'screens/splash_screen.dart';
import 'services/music_service_bridge.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppTheme.ink,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  }
  await MusicServiceBridge.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mushi Player',
      theme: AppTheme.build(),
      home: const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool showSplash = true;
  //--------------------------------------
  //show splash for 3 seconds then remove it to show the player screen
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => showSplash = false);
    });
  }

  //-------------------------------------------------------------
  // Initialize the database and create the favorites table if it doesn't exist
  @override
  void dispose() {
    MusicServiceBridge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.ink,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 650),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: showSplash
            ? const SplashContent(key: ValueKey('splash'))
            : const PlayerContent(key: ValueKey('player')),
      ),
    );
  }
}
