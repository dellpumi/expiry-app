/// Web: no local notifications.
class Reminders {
  static void start(String uid) {}
  static void stop() {}
  static Future<List<String>> getTimes() async => ['10:00', '16:45'];
  static Future<void> setTime(int i, String v) async {}
}
