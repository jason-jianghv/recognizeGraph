import 'package:flutter/foundation.dart';

class SessionState extends ChangeNotifier {
  bool loggedIn = false;
  String nickname = '小小探索家';

  void login(String name) {
    loggedIn = true;
    if (name.trim().isNotEmpty) {
      nickname = name.trim();
    }
    notifyListeners();
  }

  void logout() {
    loggedIn = false;
    nickname = '小小探索家';
    notifyListeners();
  }
}
