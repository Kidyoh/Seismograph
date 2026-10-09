import 'package:flutter/material.dart';

import 'home_page.dart';
import 'monitor_controller.dart';

class SeismographApp extends StatelessWidget {
  const SeismographApp({super.key, required this.controller});

  final MonitorController controller;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFFE0592A);
    return MaterialApp(
      title: 'Seismograph',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
      ),
      // Mostly used at night, next to the bed.
      themeMode: ThemeMode.dark,
      home: HomePage(controller: controller),
    );
  }
}
