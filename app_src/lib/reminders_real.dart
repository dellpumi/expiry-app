import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzd;
import 'package:timezone/timezone.dart' as tz;

/// Schedules the expiry reminders on this phone and shows the "invitation accepted" notices.
class Reminders {
  static final _p = FlutterLocalNotificationsPlugin();
  static final _items = <String, List<Map<String, dynamic>>>{};
  static final _lists = <String, StreamSubscription>{};
  static StreamSubscription? _mem, _notes;
  static Timer? _deb;
  static bool _ready = false;
  static const _d = NotificationDetails(android: AndroidNotificationDetails('expiry', 'Expiry reminders', importance: Importance.high, priority: Priority.high));

  static Future<void> _init() async {
    if (_ready) return;
    tzd.initializeTimeZones();
    await _p.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    await _p.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    await _p.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestExactAlarmsPermission();
    _ready = true;
  }

  static Future<List<String>> getTimes() async {
    final sp = await SharedPreferences.getInstance();
    return [sp.getString('t1') ?? '10:00', sp.getString('t2') ?? '16:45'];
  }

  static Future<void> setTime(int i, String v) async {
    await (await SharedPreferences.getInstance()).setString('t${i + 1}', v);
    _later();
  }

  static void start(String uid) {
    stop(clear: false);
    _init().then((_) {
      final db = FirebaseFirestore.instance;
      _mem = db.collectionGroup('members').where('uid', isEqualTo: uid).snapshots().listen((s) {
        final ids = s.docs.map((d) => '${d.data()['listId']}').toSet();
        for (final k in _lists.keys.where((k) => !ids.contains(k)).toList()) { _lists.remove(k)?.cancel(); _items.remove(k); }
        for (final id in ids.where((id) => !_lists.containsKey(id))) {
          _lists[id] = db.collection('lists/$id/inventory').snapshots().listen((q) { _items[id] = q.docs.map((d) => d.data()).toList(); _later(); }, onError: (_) {});
        }
        _later();
      }, onError: (_) {});
      _notes = db.collection('users/$uid/notices').snapshots().listen((q) {
        for (final d in q.docs) {
          _p.show(d.id.hashCode & 0x7fffffff, 'Invitation accepted', '${d.data()['text']}', _d);
          d.reference.delete();
        }
      }, onError: (_) {});
    });
  }

  static void stop({bool clear = true}) {
    _mem?.cancel(); _notes?.cancel();
    for (final s in _lists.values) { s.cancel(); }
    _lists.clear(); _items.clear();
    if (clear && _ready) _p.cancelAll();
  }

  static void _later() { _deb?.cancel(); _deb = Timer(const Duration(seconds: 3), _schedule); }

  static Future<void> _schedule() async {
    if (!_ready) return;
    await _p.cancelAll();
    final times = (await getTimes()).where((x) => x != '00:00').toList(), now = DateTime.now();
    var n = 0;
    Future<void> add(DateTime at, Map<String, dynamic> i, String text) async {
      if (!at.isAfter(now) || n >= 400) return;
      n++;
      final when = tz.TZDateTime.from(at, tz.UTC), body = '"${i['name']} -- ${i['quantity']} db" $text';
      try {
        await _p.zonedSchedule(n, 'Expiry reminder', body, when, _d, androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle);
      } catch (_) {
        await _p.zonedSchedule(n, 'Expiry reminder', body, when, _d, androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle);
      }
    }
    for (final items in _items.values) {
      for (final i in items) {
        final p = '${i['expiresOn']}'.split('-').map(int.parse).toList();
        for (var k = 0; k < times.length; k++) {
          final h = int.parse(times[k].substring(0, 2)), m = int.parse(times[k].substring(3));
          DateTime at(int dayShift) => DateTime(p[0], p[1], p[2] + dayShift, h, m);
          await add(at(-1), i, 'is going to expire on ${p[1].toString().padLeft(2, '0')}.${p[2].toString().padLeft(2, '0')}');
          await add(at(0), i, 'expires today');
          if (k == 0) { for (var j = 1; j <= 3; j++) { await add(at(j), i, 'is expired'); } }
        }
      }
    }
  }
}
