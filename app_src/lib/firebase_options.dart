import 'package:firebase_core/firebase_core.dart';

/// Paste the four values from the Firebase console (see GUIDE.md, part 2, step 9).
class DefaultFirebaseOptions {
  static const currentPlatform = FirebaseOptions(
    apiKey: 'PASTE_current_key_HERE',
    appId: 'PASTE_mobilesdk_app_id_HERE',
    messagingSenderId: 'PASTE_project_number_HERE',
    projectId: 'PASTE_project_id_HERE',
  );
}
