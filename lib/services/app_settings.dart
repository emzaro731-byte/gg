import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  static const _notificationsKey = 'notifications_enabled';
  static const _dataSaverKey = 'data_saver_enabled';
  static const _privateKey = 'private_mode_enabled';

  static Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  static Future<bool> notifications() async => (await _prefs()).getBool(_notificationsKey) ?? true;
  static Future<bool> dataSaver() async => (await _prefs()).getBool(_dataSaverKey) ?? false;
  static Future<bool> privateMode() async => (await _prefs()).getBool(_privateKey) ?? true;

  static Future<void> setNotifications(bool value) async => (await _prefs()).setBool(_notificationsKey, value);
  static Future<void> setDataSaver(bool value) async => (await _prefs()).setBool(_dataSaverKey, value);
  static Future<void> setPrivateMode(bool value) async => (await _prefs()).setBool(_privateKey, value);
}
