import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

final fontScale = ValueNotifier<double>(1.0);
Future<void> loadPrefs() async => fontScale.value = (await SharedPreferences.getInstance()).getDouble('font') ?? 1.0;
Future<void> setFont(double v) async {
  fontScale.value = v;
  (await SharedPreferences.getInstance()).setDouble('font', v);
}
