import 'package:flutter/material.dart';

import 'home_page.dart';
import 'monitor_controller.dart';
import 'theme.dart';

class SeismographApp extends StatelessWidget {
  const SeismographApp({super.key, required this.controller});

  final MonitorController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Seismograph',
        debugShowCheckedModeBanner: false,
        // Always dark: it lives next to the bed at night.
        theme: buildTheme(),
        home: HomePage(controller: controller),
      );
}
