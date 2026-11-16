import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps a top-level screen: the first Back press shows a hint, a second one within 2 s leaves the app.
class ExitGuard extends StatefulWidget {
  final Widget child;
  const ExitGuard({super.key, required this.child});
  @override
  State<ExitGuard> createState() => _ExitGuardState();
}

class _ExitGuardState extends State<ExitGuard> {
  DateTime? _last;
  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          final now = DateTime.now();
          if (_last != null && now.difference(_last!) < const Duration(seconds: 2)) {
            SystemNavigator.pop();
          } else {
            _last = now;
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Press back again to exit'), duration: Duration(seconds: 2)));
          }
        },
        child: widget.child,
      );
}
