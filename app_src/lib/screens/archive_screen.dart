import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../common.dart';
import '../firestore_paths.dart';
import '../validators.dart';

typedef _Doc = QueryDocumentSnapshot<Map<String, dynamic>>;

class ArchiveScreen extends StatefulWidget {
  final String listId;
  const ArchiveScreen({super.key, required this.listId});
  @override
  State<ArchiveScreen> createState() => _ArcState();
}

class _ArcState extends State<ArchiveScreen> {
  String get listId => widget.listId;
  bool find = false;
  String q = '';

  Future<void> _restore(BuildContext c, _Doc d) async {
    final db = FirebaseFirestore.instance, base = P.list(listId), x = d.data();
    final pick = await showDialog<int>(
        context: c,
        builder: (k) => AlertDialog(title: const Text('Put product(s) back to'), actions: [
              TextButton(onPressed: () => Navigator.pop(k, 0), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(k, 1), child: const Text('Add to the inventory list')),
              FilledButton(onPressed: () => Navigator.pop(k, 2), child: const Text('Add to the shopping list')),
            ]));
    if (pick == null || pick == 0 || !c.mounted) return;
    final b = db.batch();
    if (pick == 1) {
      var date = x['expiresOn'] as String?;
      if (date == null) {
        final v = await form(c, 'Expiration date', [const F('d', 'Expiration date', kind: 'date')], check: (m) => checkField('expiresOn', m['d']!));
        if (v == null) return;
        date = parseDate(v['d']!);
      }
      b.set(db.collection('$base/inventory').doc(d.id), {'name': x['name'], 'quantity': x['quantity'], 'expiresOn': date, 'shop': x['shop'] ?? '', 'priceFt': x['priceFt'] ?? 0, 'assigneeUid': null, ...createdFields()});
    } else {
      final p = x['priceFt'] ?? 0;
      final v = await form(c, 'Add to the shopping list',
          [F('n', 'Name', init: x['name']), F('q', 'Quantity', init: '${x['quantity']}', kind: 'num'), F('s', 'Shop name', init: '${x['shop'] ?? ''}'), F('p', 'Unit price (Ft)', init: p == 0 ? '' : '$p', kind: 'num')],
          ok: 'Add', check: (m) => checkField('name', m['n']!) ?? checkField('quantity', m['q']!) ?? checkSP(m['s']!, m['p']!));
      if (v == null) return;
      b.set(db.collection('$base/shopping').doc(d.id), {'name': normName(v['n']!), 'quantity': int.parse(v['q']!), 'assigneeUid': null, 'shop': normName(v['s']!), 'priceFt': v['p']!.isEmpty ? 0 : int.parse(v['p']!), ...createdFields()});
    }
    b.delete(d.reference);
    b.commit();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Text('Deleted / Expired'), actions: [IconButton(icon: const Icon(Icons.search), onPressed: () => setState(() { find = !find; q = ''; }))]),
        body: SafeArea(
            child: Column(children: [
          if (find) Padding(padding: const EdgeInsets.all(8), child: TextField(autofocus: true, onChanged: (v) => setState(() => q = v), decoration: const InputDecoration(hintText: 'Search…'))),
          Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance.collection('${P.list(listId)}/members').snapshots(),
                  builder: (c, ms) {
                    // current names by uid: a renamed person shows with the new name on old rows too
                    final names = {for (final m in ms.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[]) '${m.data()['uid']}': '${m.data()['displayName']}'};
                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance.collection('${P.list(listId)}/archive').snapshots(),
                        builder: (c, s) {
                          final rows = (s.data?.docs ?? []).where((d) => fold('${d['name']}').contains(fold(q))).toList();
                          rows.sort((a, b) => '${b.data()['expiresOn'] ?? ''}'.compareTo('${a.data()['expiresOn'] ?? ''}'));
                          return ListView(children: [
                            for (final d in rows)
                              ListTile(
                                title: Text('${d['name']}  ·  ${d['quantity']} db'),
                                subtitle: Text('${d.data()['expiresOn'] == null ? '' : 'Exp. date: ${showDate(d['expiresOn'])}  ·  '}Deleted by ${names[d['deletedByUid']] ?? d['deletedByName']}'),
                                trailing: IconButton(icon: const Icon(Icons.add), onPressed: () => _restore(c, d)),
                              ),
                          ]);
                        });
                  })),
        ])),
      );
}
