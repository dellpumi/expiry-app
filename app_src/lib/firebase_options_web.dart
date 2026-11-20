import 'package:firebase_core/firebase_core.dart';

/// Values of the Firebase WEB app (see PHASE5B.md, step 1). Used only by the web build.
class WebFirebaseOptions {
  static const options = FirebaseOptions(
    apiKey: 'PASTE_WEB_apiKey_HERE',
    appId: 'PASTE_WEB_appId_HERE',
    messagingSenderId: 'PASTE_WEB_messagingSenderId_HERE',
    projectId: 'PASTE_WEB_projectId_HERE',
    authDomain: 'PASTE_WEB_authDomain_HERE',
  );
}
