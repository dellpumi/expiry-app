import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../common.dart';
import '../firestore_paths.dart';
import '../net.dart';
import '../strings.dart';
import '../validators.dart';

typedef _D = QueryDocumentSnapshot<Map<String, dynamic>>;

class EditorsScreen extends StatefulWidget {
  final String listId;
  const EditorsScreen({super.key, required this.listId});
  @override
  State<EditorsScreen> createState() => _EdState();
}

class _EdState extends State<EditorsScreen> {
  final db = FirebaseFirestore.instance;
  User get me => FirebaseAuth.instance.currentUser!;
  bool rm = false;
  final mark = <String>{};
  String get id => widget.listId;
  void snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), persist: false, duration: const Duration(seconds: 6)));

  Future<void> add(String listName, List<_D> mem, List<_D> inv) async {
    if (!await requireOnline(context)) return;
    final v = await form(context, 'Add editor', [const F('e', 'E-mail address')], check: (m) => checkEmail(m['e']!.trim().toLowerCase()));
    if (v == null) return;
    final e = v['e']!.trim().toLowerCase();
    if (e == me.email!.toLowerCase()) return snack('You are the owner.');
    if (mem.any((m) => '${m.data()['email']}' == e) || inv.any((i) => i.id == e)) return snack('Already a member or invited.');
    try {
      if (!(await db.doc('userEmails/$e').get()).exists) {
        if (!mounted) return;
        await showDialog(context: context, builder: (k) => AlertDialog(title: const Text('No account yet'), content: Text('$e has no account yet. The person must first register in the app and verify the e-mail address. Then invite them again.'), actions: [TextButton(onPressed: () => Navigator.pop(k), child: const Text('OK'))]));
        return;
      }
    } catch (_) { return snack(S.generic); }
    db.doc('${P.list(id)}/${P.invites}/$e').set({'email': e, 'listId': id, 'listName': listName, 'ownerName': me.displayName ?? '?', 'invitedByUid': me.uid,
      'createdAt': FieldValue.serverTimestamp(), 'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 14)))}).catchError((_) => snack(S.generic));
    if (!mounted) return;
    final send = await confirm(context, 'Invitation saved', 'The invitation now waits in the app of $e. No e-mail is sent automatically. Send them an e-mail now to tell them?', ok: 'Send e-mail');
    if (!send) return;
    final subj = 'Invitation to the list "$listName"';
    final body = 'Hello! I invited you to my shared list "$listName" in the Expiry tracker & shopping list app. Open the app, log in with exactly this e-mail address ($e) and tap Accept on the invitation. The invitation is valid for 14 days.';
    try { await launchUrl(Uri.parse('mailto:$e?subject=${Uri.encodeComponent(subj)}&body=${Uri.encodeComponent(body)}'), mode: LaunchMode.externalApplication); } catch (_) { snack(S.generic); }
  }

  Future<void> saveRemove() async {
    if (!await requireOnline(context)) return;
    final b = db.batch();
    for (final k in mark) {
      if (k.startsWith('m:')) { b.delete(db.doc(P.member(id, k.substring(2)))); } else { b.delete(db.doc('${P.list(id)}/${P.invites}/${k.substring(2)}')); }
    }
    await b.commit();
    setState(() { rm = false; mark.clear(); });
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Text('Editors of the list')),
        body: SafeArea(
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: db.doc(P.list(id)).snapshots(),
                builder: (c, ls) {
                  final l = ls.data?.data();
                  if (l == null) return const SizedBox();
                  final own = l['ownerUid'] == me.uid;
                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: db.collection('${P.list(id)}/${P.members}').snapshots(),
                      builder: (c, ms) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: own ? db.collection('${P.list(id)}/${P.invites}').snapshots() : const Stream<QuerySnapshot<Map<String, dynamic>>>.empty(),
                          builder: (c, iv) {
                            final mem = ms.data?.docs ?? <_D>[];
                            final inv = (iv.data?.docs ?? <_D>[]).where((i) => (i.data()['expiresAt'] as Timestamp).toDate().isAfter(DateTime.now())).toList();
                            final owner = mem.where((m) => m.data()['role'] == 'owner'), eds = mem.where((m) => m.data()['role'] != 'owner').toList();
                            Widget row(String t, String key) => ListTile(
                                title: Text(t, style: TextStyle(decoration: mark.contains(key) ? TextDecoration.lineThrough : null)),
                                onTap: rm && key.isNotEmpty ? () => setState(() { mark.contains(key) ? mark.remove(key) : mark.add(key); }) : null);
                            return ListView(children: [
                              if (own)
                                Row(children: [
                                  Expanded(child: Padding(padding: const EdgeInsets.all(8), child: FilledButton(onPressed: () => add('${l['friendlyName']}', mem, inv), child: const Text('Add')))),
                                  Expanded(child: Padding(padding: const EdgeInsets.all(8), child: OutlinedButton(onPressed: () => setState(() { rm = !rm; mark.clear(); }), child: Text(rm ? 'Cancel' : 'Remove')))),
                                ]),
                              if (rm) const Padding(padding: EdgeInsets.all(8), child: Text('Tap rows to mark them for removal.')),
                              for (final o in owner) row('${o.data()['displayName']} (owner${o.id == me.uid ? ', You' : ''})', ''),
                              if (eds.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No editor(s)')),
                              for (final e in eds) row('${e.data()['email']} – ${e.data()['displayName']}${e.id == me.uid ? ' (You)' : ''}', 'm:${e.id}'),
                              for (final i in inv) row('${i.id} (pending)', 'i:${i.id}'),
                              if (rm) Padding(padding: const EdgeInsets.all(8), child: FilledButton(onPressed: mark.isEmpty ? null : saveRemove, child: const Text('Save'))),
                            ]);
                          }));
                })),
      );
}
