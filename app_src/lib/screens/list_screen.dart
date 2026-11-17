import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../common.dart';
import '../firestore_paths.dart';
import '../validators.dart';
import 'archive_screen.dart';
import 'settings_screen.dart';

typedef Doc = QueryDocumentSnapshot<Map<String, dynamic>>;

class ListScreen extends StatefulWidget {
  final String listId;
  const ListScreen({super.key, required this.listId});
  @override
  State<ListScreen> createState() => _ListState();
}

class _ListState extends State<ListScreen> {
  final db = FirebaseFirestore.instance;
  User get me => FirebaseAuth.instance.currentUser!;
  int tab = 0;
  bool find = false;
  String q = '', iSort = 'exp', sSort = 't';
  bool iAsc = true, sAsc = false;

  @override
  void initState() { super.initState(); _cleanup(); }

  /// Removes deleted items older than the list's retention days.
  Future<void> _cleanup() async {
    try {
      final l = await db.doc(P.list(widget.listId)).get();
      final days = (l.data()?['retentionDays'] ?? 14) as int;
      final old = await col(P.archive).where('deletedAt', isLessThan: Timestamp.fromDate(DateTime.now().subtract(Duration(days: days)))).get();
      if (old.docs.isEmpty) return;
      final b = db.batch();
      for (final d in old.docs) { b.delete(d.reference); }
      b.commit();
    } catch (_) {}
  }

  CollectionReference<Map<String, dynamic>> col(String n) => db.collection('${P.list(widget.listId)}/$n');
  void snack(String m, {SnackBarAction? action, int sec = 3}) {
    final s = ScaffoldMessenger.of(context);
    s.clearSnackBars();
    s.showSnackBar(SnackBar(content: Text(m), action: action, persist: false, duration: Duration(seconds: sec)));
  }

  Map<String, dynamic> inv(String n, int qn, String d, {Map<String, dynamic>? from}) =>
      {'name': n, 'quantity': qn, 'expiresOn': d, 'shop': from?['shop'] ?? '', 'priceFt': from?['priceFt'] ?? 0, 'assigneeUid': from?['assigneeUid'], ...createdFields()};

  void gone(Object _) => snack(itemGone);

  Future<void> edit(String coll, Doc d, String field, String label, {String kind = 'text'}) async {
    final init = field == 'expiresOn' ? showDate(d['expiresOn']) : '${d[field]}';
    final v = await form(context, label, [F('v', label, init: init, kind: kind)], check: (m) => checkField(field, m['v']!));
    if (v == null) return;
    final val = field == 'quantity' ? int.parse(v['v']!) : field == 'expiresOn' ? parseDate(v['v']!) : normName(v['v']!);
    col(coll).doc(d.id).update({field: val, ...stampFields()}).catchError(gone);
  }

  WriteBatch toArchive(Doc d, String src, String coll, {int? qty}) {
    final x = d.data(), b = db.batch();
    b.set(qty == null ? col(P.archive).doc(d.id) : col(P.archive).doc(), {'name': x['name'], 'quantity': qty ?? x['quantity'], 'expiresOn': x['expiresOn'], 'source': src, 'deletedByUid': me.uid,
      'deletedByName': me.displayName ?? '?', 'deletedAt': FieldValue.serverTimestamp(), 'shop': x['shop'] ?? '', 'priceFt': x['priceFt'] ?? 0, 'assigneeUid': x['assigneeUid']});
    if (qty == null) { b.delete(d.reference); }
    return b;
  }

  Future<void> delInv(Doc d) async {
    final x = d.data();
    final pick = await showDialog<int>(
        context: context,
        builder: (k) => AlertDialog(title: const Text('Delete item'), content: Text('${x['name']} – ${x['quantity']} db'), actions: [
              TextButton(onPressed: () => Navigator.pop(k, 0), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(k, 1), child: const Text('Delete expired product(s)')),
              FilledButton(onPressed: () => Navigator.pop(k, 2), child: const Text('Delete and add to the shopping list')),
            ]));
    if (pick == null || pick == 0 || !mounted) return;
    if (pick == 1) { moveOut(d, null, null, 'Moved to Deleted / Expired'); return; }
    final p = x['priceFt'] ?? 0;
    final v = await form(context, 'Add to the shopping list',
        [F('n', 'Name', init: x['name']), F('q', 'Quantity', init: '${x['quantity']}', kind: 'num'), F('s', 'Shop name', init: '${x['shop'] ?? ''}'), F('p', 'Unit price (Ft)', init: p == 0 ? '' : '$p', kind: 'num')],
        ok: 'Add', check: (m) => checkField('name', m['n']!) ?? checkField('quantity', m['q']!) ?? checkSP(m['s']!, m['p']!));
    if (v == null) return;
    moveOut(d, col(P.shopping).doc(), shopDoc(normName(v['n']!), int.parse(v['q']!), v['s']!, v['p']!), 'Moved to the shopping list');
  }

  void moveOut(Doc d, DocumentReference<Map<String, dynamic>>? shop, Map<String, dynamic>? shopData, String msg) {
    final x = d.data(), b = toArchive(d, 'inventory', P.inventory);
    if (shop != null) b.set(shop, shopData!);
    b.commit();
    snack(msg, sec: 5, action: SnackBarAction(label: 'Undo', onPressed: () {
      final u = db.batch();
      u.set(col(P.inventory).doc(d.id), {...x, ...stampFields()});
      u.delete(col(P.archive).doc(d.id));
      if (shop != null) u.delete(shop);
      u.commit();
    }));
  }

  Future<void> addInv() async {
    final v = await form(context, 'Add to the inventory list',
        [const F('n', 'Name'), const F('q', 'Quantity', init: '1', kind: 'num'), const F('d', 'Expiration date', kind: 'date'), const F('s', 'Every item has the same exp. date', init: '1', kind: 'check')],
        check: (m) => checkField('name', m['n']!) ?? checkField('quantity', m['q']!) ?? checkField('expiresOn', m['d']!));
    if (v == null) return;
    final n = normName(v['n']!), qn = int.parse(v['q']!), d = parseDate(v['d']!)!, b = db.batch();
    if (v['s'] == '1' || qn == 1) { b.set(col(P.inventory).doc(), inv(n, qn, d)); }
    else { for (var i = 1; i <= qn; i++) { b.set(col(P.inventory).doc(), inv('$n $i', 1, d)); } }
    b.commit();
  }

  Map<String, dynamic> shopDoc(String n, int qn, String s, String p) =>
      {'name': n, 'quantity': qn, 'assigneeUid': null, 'shop': normName(s), 'priceFt': p.isEmpty ? 0 : int.parse(p), ...createdFields()};

  Future<void> addShop() => form(context, 'Add to the shopping list',
      [const F('n', 'Name'), const F('q', 'Quantity', init: '1', kind: 'num'), const F('s', 'Shop name'), const F('p', 'Unit price (Ft)', kind: 'num')],
      cancel: 'Close', clear: {'n': '', 'q': '1', 's': '', 'p': ''},
      check: (m) => checkField('name', m['n']!) ?? checkField('quantity', m['q']!) ?? checkSP(m['s']!, m['p']!),
      onSave: (m) async { col(P.shopping).doc().set(shopDoc(normName(m['n']!), int.parse(m['q']!), m['s']!, m['p']!)); });

  Future<void> editSP(Doc d) async {
    final p = d.data()['priceFt'] ?? 0;
    final v = await form(context, 'Shop and unit price', [F('s', 'Shop name', init: '${d.data()['shop'] ?? ''}'), F('p', 'Unit price (Ft)', init: p == 0 ? '' : '$p', kind: 'num')],
        check: (m) => checkSP(m['s']!, m['p']!));
    if (v == null) return;
    d.reference.update({'shop': normName(v['s']!), 'priceFt': v['p']!.isEmpty ? 0 : int.parse(v['p']!), ...stampFields()}).catchError(gone);
  }

  Future<void> delShop(Doc d) async {
    final qn = d['quantity'] as int;
    final v = await form(context, 'Delete this item?', [F('q', 'Quantity', init: '$qn', kind: 'num')], ok: 'Delete', text: d['name'],
        check: (m) { final x = int.tryParse(m['q']!); return x == null || x < 1 || x > qn ? 'Quantity: 1–$qn.' : null; });
    if (v == null) return;
    final x = int.parse(v['q']!);
    if (x >= qn) { toArchive(d, 'shopping', P.shopping).commit(); } else { final b = toArchive(d, 'shopping', P.shopping, qty: x); b.update(d.reference, {'quantity': qn - x, ...stampFields()}); b.commit(); }
  }

  Future<void> buy(Doc d) async {
    final qn = d['quantity'] as int, src = d.data();
    final v = await form(context, 'Moving the product(s) to the inventory list',
        [F('n', 'Name', init: d['name']), F('q', 'Quantity to move', init: '$qn', kind: 'num'), const F('d', 'Expiration date', kind: 'date'), const F('s', 'All products have the same exp. date', init: '1', kind: 'check')],
        ok: 'Move',
        check: (m) { final x = int.tryParse(m['q']!); return checkField('name', m['n']!) ?? (x == null || x < 1 || x > qn ? 'Quantity: 1–$qn.' : null) ?? (m['s'] == '1' || x == 1 ? checkField('expiresOn', m['d']!) : null); });
    if (v == null) return;
    final n = normName(v['n']!), mv = int.parse(v['q']!);
    if (v['s'] == '1' || mv == 1) {
      final b = db.batch();
      b.set(col(P.inventory).doc(), inv(n, mv, parseDate(v['d']!)!, from: src));
      if (mv == qn) { b.delete(d.reference); } else { b.update(d.reference, {'quantity': qn - mv, ...stampFields()}); }
      b.commit();
      return;
    }
    var left = qn;
    for (var i = 1; i <= mv; i++) {
      if (!mounted) return;
      final p = await form(context, '$n - $i', [const F('d', 'Expiration date', kind: 'date')], check: (m) => checkField('expiresOn', m['d']!));
      if (p == null) return;
      left--;
      final b = db.batch();
      b.set(col(P.inventory).doc(), inv('$n $i', 1, parseDate(p['d']!)!, from: src));
      if (left <= 0) { b.delete(d.reference); } else { b.update(d.reference, {'quantity': left, ...stampFields()}); }
      b.commit();
    }
  }

  Widget head(List<(String, String, int)> cols, String cur, bool asc, void Function(String) tap, {double lead = 0, double trail = 40}) => Container(
      color: Colors.white10,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        SizedBox(width: lead),
        for (final c in cols) Expanded(flex: c.$3, child: InkWell(onTap: () => tap(c.$2), child: Text('${c.$1}${cur == c.$2 ? (asc ? ' ▲' : ' ▼') : ''}', style: const TextStyle(fontWeight: FontWeight.bold)))),
        SizedBox(width: trail, child: const Align(alignment: Alignment.centerRight, child: Text('−'))),
      ]));

  Widget inventory() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: col(P.inventory).snapshots(),
      builder: (c, s) {
        final rows = (s.data?.docs ?? []).where((d) => fold(d['name']).contains(fold(q))).toList();
        rows.sort((a, b) {
          final k = iSort == 'name' ? fold(a['name']).compareTo(fold(b['name'])) : iSort == 'q' ? (a['quantity'] as int).compareTo(b['quantity'] as int) : (a['expiresOn'] as String).compareTo(b['expiresOn'] as String);
          final r = k != 0 ? k : fold(a['name']).compareTo(fold(b['name']));
          return iAsc ? r : -r;
        });
        return Column(children: [
          head([('Name', 'name', 5), ('Quantity', 'q', 2), ('Expiration date', 'exp', 3)], iSort, iAsc, (k) => setState(() { if (iSort == k) { iAsc = !iAsc; } else { iSort = k; iAsc = true; } })),
          Expanded(child: ListView(children: [for (final d in rows) invRow(d)])),
        ]);
      });

  Widget invRow(Doc d) {
    final left = daysLeft(d['expiresOn']);
    return Container(
        color: left <= 0 ? const Color(0xFF6B1E1E) : left <= 3 ? const Color(0xFF5A4E00) : null,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(flex: 5, child: InkWell(onTap: () => edit(P.inventory, d, 'name', 'Name'), child: Text('${left <= 0 ? '⛔ ' : left <= 3 ? '⚠ ' : ''}${d['name']}'))),
          Expanded(flex: 2, child: InkWell(onTap: () => edit(P.inventory, d, 'quantity', 'Quantity', kind: 'num'), child: Text('${d['quantity']} db'))),
          Expanded(flex: 3, child: InkWell(onTap: () => edit(P.inventory, d, 'expiresOn', 'Expiration date', kind: 'date'), child: Text(showDate(d['expiresOn'])))),
          SizedBox(width: 40, child: IconButton(icon: const Icon(Icons.remove), onPressed: () => delInv(d))),
        ]));
  }

  Widget shopping() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: col(P.shopping).snapshots(),
      builder: (c, s) {
        final all = s.data?.docs ?? [];
        var sum = 0;
        for (final d in all) { sum += ((d.data()['priceFt'] ?? 0) as int) * (d['quantity'] as int); }
        final rows = all.where((d) => fold(d['name']).contains(fold(q))).toList();
        int t(Doc d) => (d.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch;
        rows.sort((a, b) {
          final k = sSort == 'name' ? fold(a['name']).compareTo(fold(b['name'])) : sSort == 'q' ? (a['quantity'] as int).compareTo(b['quantity'] as int) : t(a).compareTo(t(b));
          return sAsc ? k : -k;
        });
        void soon() => snack('Coming later');
        return Column(children: [
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: soon, child: const Text('Check price by GTIN'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: soon, child: const Text('Check price by name'))),
          ]),
          Card(child: Padding(padding: const EdgeInsets.all(8), child: Text.rich(TextSpan(children: [
            const TextSpan(text: 'Sum of the product(s) on this list: '),
            TextSpan(text: '${thousands(sum)} Ft', style: const TextStyle(fontWeight: FontWeight.bold)),
          ])))),
          head([('Name', 'name', 5), ('Quantity', 'q', 2)], sSort, sAsc, (k) => setState(() { if (sSort == k) { sAsc = !sAsc; } else { sSort = k; sAsc = true; } }), lead: 36, trail: 96),
          Expanded(child: ListView(children: [for (final d in rows) shopRow(d, soon)])),
        ]);
      });

  Widget shopRow(Doc d, VoidCallback soon) {
    final p = (d.data()['priceFt'] ?? 0) as int, shop = '${d.data()['shop'] ?? ''}';
    return Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white12))),
        child: Column(children: [
          Row(children: [
            SizedBox(width: 36, child: Checkbox(value: false, onChanged: (_) => buy(d))),
            Expanded(flex: 5, child: InkWell(onTap: () => edit(P.shopping, d, 'name', 'Name'), child: Text('${d['name']}'))),
            Expanded(flex: 2, child: InkWell(onTap: () => edit(P.shopping, d, 'quantity', 'Quantity', kind: 'num'), child: Text('${d['quantity']} db'))),
            SizedBox(width: 96, child: Align(alignment: Alignment.centerRight, child: IconButton(icon: const Icon(Icons.remove), onPressed: () => delShop(d)))),
          ]),
          Row(children: [
            const SizedBox(width: 36),
            Expanded(flex: 5, child: InkWell(onTap: () => editSP(d), child: Text(shop.isEmpty ? '–' : shop))),
            Expanded(flex: 2, child: InkWell(onTap: () => editSP(d), child: Text(p > 0 ? '${thousands(p)} Ft' : '–'))),
            SizedBox(width: 96, child: Align(alignment: Alignment.centerRight, child: OutlinedButton(onPressed: soon, child: const Text('Check price')))),
          ]),
        ]));
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(
            title: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(stream: db.doc(P.list(widget.listId)).snapshots(), builder: (c, s) => Text('${s.data?.data()?['friendlyName'] ?? ''}')),
            actions: [IconButton(icon: const Icon(Icons.settings), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen(listId: widget.listId))))]),
        body: SafeArea(child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(children: [
              SegmentedButton<int>(
                  segments: const [ButtonSegment(value: 0, label: Text('Inventory list')), ButtonSegment(value: 1, label: Text('Shopping list'))],
                  selected: {tab},
                  onSelectionChanged: (s) => setState(() { tab = s.first; q = ''; find = false; })),
              Row(children: [
                Expanded(child: FilledButton(onPressed: tab == 0 ? addInv : addShop, child: const Text('Add'))),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton(onPressed: () => setState(() { find = !find; q = ''; }), child: const Text('Search'))),
              ]),
              if (find) TextField(autofocus: true, onChanged: (v) => setState(() => q = v), decoration: const InputDecoration(hintText: 'Search…')),
              Expanded(child: tab == 0 ? inventory() : shopping()),
              OutlinedButton(onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => ArchiveScreen(listId: widget.listId))), child: const Text('Deleted / Expired products')),
            ]))),
      );
}
