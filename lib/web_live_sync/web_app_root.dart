import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'pharoah_web_manager.dart';
import 'web_portal_gateway.dart';

class WebAppRoot extends StatelessWidget {
  const WebAppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PharoahWebManager(),
      child: MaterialApp(
        title: 'Pharoah ERP Web',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFF0F172A),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF0D47A1),
            brightness: Brightness.dark,
          ),
        ),
        home: const WebPortalGateway(),
      ),
    );
  }
}
