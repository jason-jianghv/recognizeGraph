import 'package:flutter/material.dart';
import 'package:shitu_app/navigation/app_routes.dart';
import 'package:shitu_app/screens/camera_screen.dart';
import 'package:shitu_app/screens/explore_screen.dart';
import 'package:shitu_app/screens/space_screen.dart';
import 'package:shitu_app/widgets/bottom_bar.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          ExploreScreen(),
          SpaceScreen(),
        ],
      ),
      bottomNavigationBar: ShituBottomBar(
        index: _index,
        onSelect: (i) => setState(() => _index = i),
        onCamera: () {
          Navigator.of(context).push(slideUpRoute(const CameraScreen()));
        },
      ),
      extendBody: true,
    );
  }
}
