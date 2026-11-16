import 'strings.dart';

final _email = RegExp(r'^[A-Za-z0-9.+_-]+@[A-Za-z0-9.+_-]+\.[A-Za-z0-9.+_-]+$');
String? checkEmail(String s) => (s.isEmpty || s.length > 50 || !_email.hasMatch(s)) ? S.ve : null;
String? checkPassword(String s) =>
    RegExp(r'^[\x21-\x7e]{8,15}$').hasMatch(s) && RegExp(r'[A-Z]').hasMatch(s) && RegExp(r'[!-/:-@\[-`{-~]').hasMatch(s)
        ? null
        : S.vp;
String normName(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');
