import 'package:flutter/material.dart';

import 'src/service/monitor_service.dart';
import 'src/ui/app.dart';
import 'src/ui/monitor_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureMonitorService();
  final controller = MonitorController();
  runApp(SeismographApp(controller: controller));
  await controller.init();
}
