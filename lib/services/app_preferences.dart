import 'package:shared_preferences/shared_preferences.dart';

class AppPreferences {
  static const _notificationsKey = 'notifications_enabled';
  static const _dataSaverKey = 'data_saver_enabled';
  static const _privateModeKey = 'private_mode_enabled';

  static Future<bool> notificationsEnabled() async => (await SharedPreferences.getInstance()).getBool(_notificationsKey) ?? true;
  static Future<bool> dataSaverEnabled() async => (await SharedPreferences.getInstance()).getBool(_dataSaverKey) ?? false;
  static Future<bool> privateModeEnabled() async => (await SharedPreferences.getInstance()).getBool(_privateModeKey) ?? true;

  static Future<void> setNotificationsEnabled(bool value) async => (await SharedPreferences.getInstance()).setBool(_notificationsKey, value);
  static Future<void> setDataSaverEnabled(bool value) async => (await SharedPreferences.getInstance()).setBool(_dataSaverKey, value);
  static Future<void> setPrivateModeEnabled(bool value) async => (await SharedPreferences.getInstance()).setBool(_privateModeKey, value);
}
