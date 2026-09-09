import 'package:shared_preferences/shared_preferences.dart';

class AppSettingsService {
  static const _notificationsKey = 'settings.notifications';
  static const _dataSaverKey = 'settings.data_saver';
  static const _privateModeKey = 'settings.private_mode';

  bool notificationsEnabled = true;
  bool dataSaverEnabled = false;
  bool privateModeEnabled = true;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    notificationsEnabled = prefs.getBool(_notificationsKey) ?? true;
    dataSaverEnabled = prefs.getBool(_dataSaverKey) ?? false;
    privateModeEnabled = prefs.getBool(_privateModeKey) ?? true;
  }

  Future<void> setNotifications(bool value) async {
    notificationsEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationsKey, value);
  }

  Future<void> setDataSaver(bool value) async {
    dataSaverEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dataSaverKey, value);
  }

  Future<void> setPrivateMode(bool value) async {
    privateModeEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_privateModeKey, value);
  }
}
