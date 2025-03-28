import 'package:flutter/material.dart';
import 'package:nipaplay/utils/globals.dart';
import 'package:nipaplay/utils/theme_helper.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'package:window_manager/window_manager.dart';
import 'utils/theme_provider.dart'; // 导入获取亮暗模式的文件

const double windowWidth = 1167.0;
const double windowHeight = 600.0;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 判断是否为桌面平台
  if (isDesktop) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      title: "NipaPlay",
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setSize(const Size(windowWidth, windowHeight));
      await windowManager
          .setMinimumSize(const Size(windowWidth / 2, windowHeight / 2));
      await windowManager.show();
      await windowManager.setHasShadow(true);
      await windowManager.setAlignment(Alignment.center);
    });
  }

  runApp(
    ChangeNotifierProvider(
      create: (context) => ThemeProvider(),
      child: const NipaPlayApp(),
    ),
  );
}

class NipaPlayApp extends StatefulWidget {
  const NipaPlayApp({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _NipaPlayAppState createState() => _NipaPlayAppState();
}
class _NipaPlayAppState extends State<NipaPlayApp> {
  Future<void> _initPackageInfo() async {
  final info = await PackageInfo.fromPlatform();
  // 确保在正确的线程中访问UI
  setState(() {
    Appversion = info.version;
  });
}
  @override
  void initState() {
    super.initState();
    _initPackageInfo();
  }

  @override
  Widget build(BuildContext context) {
    isDarkModeValue = getCurrentThemeMode(context, modeSwitch);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NipaPlay',
      theme: ThemeData(
        primaryColor: isDarkModeValue ? Colors.white : Colors.black,
        brightness: isDarkModeValue ? Brightness.dark : Brightness.light,
      ),
      home: const Scaffold(
        body: Stack(
          children: [
            HomeScreen(),
          ],
        ),
      ),
    );
  }
}
