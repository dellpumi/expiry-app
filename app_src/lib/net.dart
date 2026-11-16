import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'strings.dart';

Future<bool> isOnline() async {
  try {
    final dynamic r = await Connectivity().checkConnectivity();
    if (r is List) return r.any((x) => x != ConnectivityResult.none);
    return r != ConnectivityResult.none;
  } catch (_) {
    return true;
  }
}

/// Call before opening a function that needs the network. Shows the message and returns false when offline.
Future<bool> requireOnline(BuildContext c) async {
  if (await isOnline()) return true;
  if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text(S.net)));
  return false;
}
