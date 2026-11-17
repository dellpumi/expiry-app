import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../common.dart';
import '../firestore_paths.dart';
import '../validators.dart';

typedef _Doc = QueryDocumentSnapshot<Map<String, dynamic>>;

class ArchiveScreen extends StatelessWidget {
  final String listId;
  const ArchiveScreen({super.key, required this.listId});

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
        appBar: AppBar(title: const Text('Deleted / Expired')),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('${P.list(listId)}/archive').snapshots(),
            builder: (c, s) {
              final rows = (s.data?.docs ?? []).toList();
              rows.sort((a, b) => '${b.data()['expiresOn'] ?? ''}'.compareTo('${a.data()['expiresOn'] ?? ''}'));
              return ListView(children: [
                for (final d in rows)
                  ListTile(
                    title: Text('${d['name']}  ·  ${d['quantity']} db'),
                    subtitle: Text('${d.data()['expiresOn'] == null ? '' : '${showDate(d['expiresOn'])}  ·  '}Deleted by ${d['deletedByName']}'),
                    trailing: IconButton(icon: const Icon(Icons.add), onPressed: () => _restore(c, d)),
                  ),
              ]);
            }),
      );
}
