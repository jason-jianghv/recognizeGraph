import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shitu_app/screens/home_shell.dart';
import 'package:shitu_app/screens/splash_screen.dart';
import 'package:shitu_app/state/session_state.dart';
import 'package:shitu_app/state/voice_preference_state.dart';
import 'package:shitu_app/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ShituApp());
}

class ShituApp extends StatelessWidget {
  const ShituApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) {
            final s = SessionState();
            s.restore();
            return s;
          },
        ),
        ChangeNotifierProvider(
          create: (_) {
            final v = VoicePreferenceState();
            v.restore();
            return v;
          },
        ),
      ],
      child: MaterialApp(
        title: '识图',
        debugShowCheckedModeBanner: false,
        theme: buildShituTheme(),
        home: const _Root(),
      ),
    );
  }
}

class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  bool _showSplash = true;

  @override
  Widget build(BuildContext context) {
    if (_showSplash) {
      return SplashScreen(
        onFinished: () => setState(() => _showSplash = false),
      );
    }
    return const HomeShell();
  }
}
