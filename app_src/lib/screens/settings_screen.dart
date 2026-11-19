import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../common.dart';
import '../firestore_paths.dart';
import '../net.dart';
import '../strings.dart';
import '../validators.dart';
import 'auth_screens.dart';
import 'editors_screen.dart';

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

  Future<void> wipeList(String id) async {
    final base = P.list(id);
    for (final sub in [P.inventory, P.shopping, P.archive, P.invites]) {
      final qs = await db.collection('$base/$sub').get();
      for (var i = 0; i < qs.docs.length; i += 400) {
        final b = db.batch();
        for (final d in qs.docs.skip(i).take(400)) { b.delete(d.reference); }
        await b.commit();
      }
    }
    final ms = await db.collection('$base/${P.members}').get();
    for (final m in ms.docs) { if (m.id != me.uid) await m.reference.delete(); }
    final b = db.batch();
    b.delete(db.doc('$base/${P.members}/${me.uid}'));
    b.delete(db.doc(base));
    await b.commit();
  }

  Future<void> shareOff(String id) async {
    if (!await confirm(context, 'Sharing', 'Turning sharing off removes all editors and cancels pending invitations. The items stay.')) return;
    final ms = await db.collection('${P.list(id)}/${P.members}').get(), iv = await db.collection('${P.list(id)}/${P.invites}').get();
    final b = db.batch();
    for (final m in ms.docs) { if (m.id != me.uid) b.delete(m.reference); }
    for (final i in iv.docs) { b.delete(i.reference); }
    b.update(db.doc(P.list(id)), {'sharingEnabled': false, 'updatedAt': FieldValue.serverTimestamp()});
    await b.commit();
  }

  Future<void> leave(String id) async {
    if (!await requireOnline(context) || !await confirm(context, 'Leave list', 'Leave this list? You lose access to its items.', ok: 'Leave')) return;
    final nav = Navigator.of(context);
    await db.doc(P.member(id, me.uid)).delete();
    nav.popUntil((r) => r.isFirst);
  }

  Future<void> delList(String id) async {
    if (!await requireOnline(context) || !await confirm(context, 'Delete list', 'Delete this list for everyone? All its items are lost.', ok: 'Delete')) return;
    final nav = Navigator.of(context);
    try { await wipeList(id); } catch (_) { snack(S.generic); return; }
    nav.popUntil((r) => r.isFirst);
  }

  Future<void> delAccount() async {
    if (!await requireOnline(context) || !await confirm(context, 'Delete account', 'Delete your account? Lists you own are deleted for everyone.', ok: 'Continue')) return;
    final v = await form(context, 'Password', [const F('p', 'Enter your password to continue.', kind: 'pw')], ok: 'Delete');
    if (v == null) return;
    final nav = Navigator.of(context);
    try {
      await me.reauthenticateWithCredential(EmailAuthProvider.credential(email: me.email!, password: v['p']!));
      final ms = await db.collectionGroup(P.members).where('uid', isEqualTo: me.uid).get();
      for (final m in ms.docs) { if (m.data()['role'] == 'owner') { await wipeList(m.data()['listId']); } else { await m.reference.delete(); } }
      await db.doc(P.user(me.uid)).delete();
      try { await db.doc('userEmails/${me.email!.toLowerCase()}').delete(); } catch (_) {}
      await me.delete();
      nav.popUntil((r) => r.isFirst);
    } on FirebaseAuthException { snack('Wrong password.'); } catch (_) { snack(S.generic); }
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
                  if (l != null && own)
                    ListTile(
                        title: const Text('Can the lists be shared?'),
                        subtitle: Text(l['sharingEnabled'] == true ? 'Yes (tap to turn off)' : 'No (tap to turn on)'),
                        onTap: () async {
                          if (!await requireOnline(c)) return;
                          if (l['sharingEnabled'] == true) { await shareOff(id!); } else { db.doc(P.list(id!)).update({'sharingEnabled': true, 'updatedAt': FieldValue.serverTimestamp()}); }
                        }),
                  if (l != null && l['sharingEnabled'] == true)
                    ListTile(title: const Text('Editors of the list (tap to open)'), onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => EditorsScreen(listId: id!)))),
                  ListTile(title: const Text('Change password'), onTap: chPw),
                  ListTile(title: const Text('Change display name'), subtitle: Text(me.displayName ?? ''), onTap: chName),
                  ListTile(title: const Text('Logout'), onTap: () => askLogout(c)),
                  if (l != null && !own) ListTile(title: const Text('Leave list'), onTap: () => leave(id!)),
                  if (l != null && own) ListTile(title: const Text('Delete list'), onTap: () => delList(id!)),
                  ListTile(title: const Text('Delete account'), onTap: delAccount),
                ]);
              })),
    );
  }
}
