import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../firestore_paths.dart';
import '../strings.dart';
import '../validators.dart';
import 'auth_screens.dart';

class HubScreen extends StatefulWidget {
  const HubScreen({super.key});
  @override
  State<HubScreen> createState() => _HubState();
}

class _HubState extends State<HubScreen> {
  final _db = FirebaseFirestore.instance;
  User get _me => FirebaseAuth.instance.currentUser!;

  @override
  void initState() { super.initState(); ensureUserDoc(_me); }

  void _soon(String what) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$what: next build phase')));

  Future<void> _create() async {
    final ctl = TextEditingController();
    final name = await showDialog<String>(
        context: context,
        builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(
              title: const Text('Create a list'),
              content: TextField(controller: ctl, decoration: const InputDecoration(labelText: "Your list's name")),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
                FilledButton(onPressed: () { final n = normName(ctl.text); if (n.isEmpty || n.length > 35) { ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text(S.vl))); return; } Navigator.pop(c, n); }, child: const Text('Save and load')),
              ],
            )));
    if (name == null) return;
    final ref = _db.collection(P.lists).doc();
    final b = _db.batch();
    b.set(ref, {'friendlyName': name, 'ownerUid': _me.uid, 'sharingEnabled': false, 'retentionDays': 14, 'createdAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp()});
    b.set(ref.collection(P.members).doc(_me.uid), {'uid': _me.uid, 'listId': ref.id, 'role': 'owner', 'displayName': _me.displayName ?? '', 'email': _me.email!.toLowerCase(), 'joinedAt': FieldValue.serverTimestamp()});
    await b.commit();
    _soon('Open the new list (S8)');
  }

  Widget _col(String title, List<QueryDocumentSnapshot<Map<String, dynamic>>> rows) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          for (final r in rows)
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _db.doc(P.list(r.data()['listId'] as String)).snapshots(),
              builder: (c, s) => s.data?.data() == null ? const SizedBox() : Card(child: ListTile(title: Text(s.data!.data()!['friendlyName'] as String), onTap: () => _soon('List screen (S8)'))),
            ),
        ]),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Hello, ${_me.displayName ?? ''}'), actions: [IconButton(icon: const Icon(Icons.settings), onPressed: () => _soon('Settings (S17)'))]),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          FilledButton(onPressed: _create, child: const Text('Create a new list')),
          const SizedBox(height: 16),
          const Text('Open a list for editing', style: TextStyle(fontSize: 18)),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _db.collectionGroup(P.members).where('uid', isEqualTo: _me.uid).snapshots(),
            builder: (c, s) {
              final docs = s.data?.docs ?? [];
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _col('Your own lists', docs.where((d) => d.data()['role'] == 'owner').toList()),
                const SizedBox(width: 8),
                _col('Lists shared with you', docs.where((d) => d.data()['role'] != 'owner').toList()),
              ]);
            },
          ),
          const SizedBox(height: 40),
          OutlinedButton(onPressed: () => askLogout(context), child: const Text('Log out')),
        ]),
      );
}
