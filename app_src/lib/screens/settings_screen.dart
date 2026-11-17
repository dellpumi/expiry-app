import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../common.dart';
import '../firestore_paths.dart';
import '../net.dart';
import '../strings.dart';
import '../validators.dart';
import 'auth_screens.dart';

class SettingsScreen extends StatefulWidget {
  final String? listId;
  const SettingsScreen({super.key, this.listId});
  @override
  State<SettingsScreen> createState() => _SetState();
}

class _SetState extends State<SettingsScreen> {
  final db = FirebaseFirestore.instance;
  User get me => FirebaseAuth.instance.currentUser!;
  void snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), persist: false));

  Future<void> chPw() async {
    if (!await requireOnline(context)) return;
    final v = await form(context, 'Change password', [const F('o', 'Old password', kind: 'pw'), const F('n', 'New password', kind: 'pw'), const F('m', 'New password again', kind: 'pw')],
        ok: 'Change and logout', check: (m) => m['o']!.isEmpty ? S.enterPw : checkPassword(m['n']!) ?? (m['n'] != m['m'] ? S.pwMismatch : null));
    if (v == null) return;
    final nav = Navigator.of(context), sm = ScaffoldMessenger.of(context);
    try {
      await me.reauthenticateWithCredential(EmailAuthProvider.credential(email: me.email!, password: v['o']!));
      await me.updatePassword(v['n']!);
      await FirebaseAuth.instance.signOut();
      nav.popUntil((r) => r.isFirst);
      sm.showSnackBar(const SnackBar(content: Text('Password changed. Please log in again.'), persist: false));
    } on FirebaseAuthException catch (e) {
      snack(e.code == 'network-request-failed' ? S.net : 'Wrong old password.');
    }
  }

  Future<void> chName() async {
    if (!await requireOnline(context)) return;
    final v = await form(context, 'Change display name', [F('n', 'Display name', init: me.displayName ?? '')],
        check: (m) { final n = normName(m['n']!); return n.isEmpty || n.length > 15 ? S.vdn : null; });
    if (v == null) return;
    final n = normName(v['n']!);
    try {
      await me.updateDisplayName(n);
      db.doc(P.user(me.uid)).update({'displayName': n}).catchError((_) {});
      final ms = await db.collectionGroup(P.members).where('uid', isEqualTo: me.uid).get();
      for (final m in ms.docs) { m.reference.update({'displayName': n}).catchError((_) {}); }
      if (mounted) { setState(() {}); snack('Display name changed'); }
    } catch (_) { snack(S.generic); }
  }

  Future<void> rename(String id, String cur) async {
    if (!await requireOnline(context)) return;
    final v = await form(context, 'Rename list', [F('n', 'List name', init: cur)], check: (m) { final n = normName(m['n']!); return n.isEmpty || n.length > 35 ? S.vl : null; });
    if (v == null) return;
    db.doc(P.list(id)).update({'friendlyName': normName(v['n']!), 'updatedAt': FieldValue.serverTimestamp()}).catchError((_) => snack(S.generic));
  }

  Future<void> retention(String id, int cur) async {
    if (!await requireOnline(context)) return;
    final v = await form(context, 'Retention (days)', [F('d', 'Days', init: '$cur', kind: 'num')],
        check: (m) { final d = int.tryParse(m['d']!); return d == null || d < 1 || d > 30 ? 'Enter 1–30 days.' : null; });
    if (v == null) return;
    db.doc(P.list(id)).update({'retentionDays': int.parse(v['d']!), 'updatedAt': FieldValue.serverTimestamp()}).catchError((_) => snack(S.generic));
  }

  @override
  Widget build(BuildContext c) {
    final id = widget.listId;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: id == null ? const Stream<DocumentSnapshot<Map<String, dynamic>>>.empty() : db.doc(P.list(id)).snapshots(),
              builder: (c, s) {
                final l = s.data?.data(), own = l != null && l['ownerUid'] == me.uid;
                return ListView(children: [
                  if (own) ListTile(title: const Text('Rename list'), subtitle: Text('${l['friendlyName']}'), onTap: () => rename(id!, '${l['friendlyName']}')),
                  if (l != null)
                    ListTile(title: const Text('Keep deleted / expired items for:'), subtitle: Text('${l['retentionDays'] ?? 14} days${own ? '' : ' (owner only)'}'), onTap: own ? () => retention(id!, (l['retentionDays'] ?? 14) as int) : null),
                  ListTile(title: const Text('Change password'), onTap: chPw),
                  ListTile(title: const Text('Change display name'), subtitle: Text(me.displayName ?? ''), onTap: chName),
                  ListTile(title: const Text('Logout'), onTap: () => askLogout(c)),
                ]);
              })),
    );
  }
}
