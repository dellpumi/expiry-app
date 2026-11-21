import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'prefs.dart';

/// Web: no system notifications; the "invitation accepted" notice shows as an in-app message.
class Reminders {
  static StreamSubscription? _notes;
  static void start(String uid) {
    stop();
    _notes = FirebaseFirestore.instance.collection('users/$uid/notices').snapshots().listen((q) {
      for (final d in q.docs) {
        messengerKey.currentState?.showSnackBar(SnackBar(content: Text('${d.data()['text']}'), persist: false, duration: const Duration(seconds: 10)));
        d.reference.delete();
      }
    }, onError: (_) {});
  }

  static void stop({bool clear = true}) { _notes?.cancel(); }
  static Future<List<String>> getTimes() async => ['10:00', '16:45'];
  static Future<void> setTime(int i, String v) async {}
}
