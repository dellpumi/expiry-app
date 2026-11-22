import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../common.dart';
import '../firestore_paths.dart';
import '../net.dart';
import '../validators.dart';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
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

  Map<String, String> members = {};
  StreamSubscription? _sub, _sync, _net;
  Timer? _tm;
  DateTime? lastSync;
  bool pending = false, offline = false;
  bool get multi => members.length > 1;

  @override
  void initState() {
    super.initState();
    _cleanup();
    _sub = col('members').snapshots().listen((s) => setState(() => members = {for (final m in s.docs) m.id: '${m.data()['displayName']}'}), onError: (_) {});
    _sync = col(P.inventory).snapshots(includeMetadataChanges: true).listen((s) {
      final p = s.metadata.hasPendingWrites, fresh = !s.metadata.isFromCache && !p;
      if (mounted) setState(() { pending = p; if (fresh) lastSync = DateTime.now(); });
    }, onError: (_) {});
    isOnline().then((o) { if (mounted) setState(() => offline = !o); });
    _net = Connectivity().onConnectivityChanged.listen((dynamic r) {
      final off = r is List ? r.every((x) => x == ConnectivityResult.none) : r == ConnectivityResult.none;
      if (mounted) setState(() => offline = off);
    });
    _tm = Timer.periodic(const Duration(seconds: 30), (_) { if (mounted) setState(() {}); });
  }

  String rel(DateTime t) {
    final m = DateTime.now().difference(t).inMinutes;
    return m < 1 ? 'just now' : m < 60 ? '$m minutes ago' : '${m ~/ 60} hours ago';
  }

  Widget status() {
    final last = lastSync == null ? '' : ' · last sync ${rel(lastSync!)}';
    if (offline) return Text('No network$last', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12));
    return Text(pending ? 'Syncing' : lastSync == null ? 'Connecting…' : 'Synced ${rel(lastSync!)}', style: const TextStyle(fontSize: 12));
  }

  @override
  void dispose() { _sub?.cancel(); _sync?.cancel(); _net?.cancel(); _tm?.cancel(); super.dispose(); }

  Future<void> edWho(Doc d) async {
    final pick = await showDialog<String>(
        context: context,
        builder: (k) => SimpleDialog(title: const Text('Who buys it'), children: [
              SimpleDialogOption(onPressed: () => Navigator.pop(k, ''), child: const Text('Anyone')),
              for (final e in members.entries) SimpleDialogOption(onPressed: () => Navigator.pop(k, e.key), child: Text(e.value)),
            ]));
    if (pick == null) return;
    d.reference.update({'assigneeUid': pick.isEmpty ? null : pick, ...stampFields()}).catchError(gone);
  }

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

  WriteBatch toArchive(Doc d, String src, String coll, {int? qty, DocumentReference<Map<String, dynamic>>? ref}) {
    final x = d.data(), b = db.batch();
    b.set(ref ?? (qty == null ? col(P.archive).doc(d.id) : col(P.archive).doc()), {'name': x['name'], 'quantity': qty ?? x['quantity'], 'expiresOn': x['expiresOn'], 'source': src, 'deletedByUid': me.uid,
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
    moveOut(d, col(P.shopping).doc(), shopDoc(normName(v['n']!), int.parse(v['q']!), v['s']!, v['p']!), 'Expired trashed, new product(s) moved to the shopping list');
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

  Map<String, dynamic> shopDoc(String n, int qn, String s, String p, {String? who}) =>
      {'name': n, 'quantity': qn, 'assigneeUid': (who == null || who.isEmpty) ? null : who, 'shop': normName(s), 'priceFt': p.isEmpty ? 0 : int.parse(p), ...createdFields()};

  Future<void> addShop() => form(context, 'Add to the shopping list',
      [const F('n', 'Name'), const F('q', 'Quantity', init: '1', kind: 'num'), const F('s', 'Shop name'), const F('p', 'Unit price (Ft)', kind: 'num'), if (multi) F('w', 'Who buys it', kind: 'sel', opts: [('', 'Anyone'), for (final e in members.entries) (e.key, e.value)])],
      cancel: 'Close', clear: {'n': '', 'q': '1', 's': '', 'p': ''},
      check: (m) => checkField('name', m['n']!) ?? checkField('quantity', m['q']!) ?? checkSP(m['s']!, m['p']!),
      onSave: (m) async { col(P.shopping).doc().set(shopDoc(normName(m['n']!), int.parse(m['q']!), m['s']!, m['p']!, who: m['w'])); });

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
    final x = int.parse(v['q']!), data = d.data();
    void Function() undo;
    if (x >= qn) {
      toArchive(d, 'shopping', P.shopping).commit();
      undo = () { final u = db.batch(); u.set(col(P.shopping).doc(d.id), {...data, ...stampFields()}); u.delete(col(P.archive).doc(d.id)); u.commit(); };
    } else {
      final ar = col(P.archive).doc(), b = toArchive(d, 'shopping', P.shopping, qty: x, ref: ar);
      b.update(d.reference, {'quantity': qn - x, ...stampFields()});
      b.commit();
      undo = () { final u = db.batch(); u.update(d.reference, {'quantity': qn, ...stampFields()}); u.delete(ar); u.commit(); };
    }
    snack('Removed from the shopping list', sec: 5, action: SnackBarAction(label: 'Undo', onPressed: undo));
  }

  Future<void> buy(Doc d) async {
    final qn = d['quantity'] as int, src = d.data();
    final v = await form(context, 'Moving the product(s) to the inventory list',
        [F('n', 'Name', init: d['name']), F('q', 'Quantity to move', init: '$qn', kind: 'num'), F('d', 'Expiration date', init: '${DateTime.now().year}.', kind: 'date'), const F('s', 'All products have the same exp. date', init: '1', kind: 'check')],
        ok: 'Move',
        check: (m) { final x = int.tryParse(m['q']!); return checkField('name', m['n']!) ?? (x == null || x < 1 || x > qn ? 'Quantity: 1–$qn.' : null) ?? (m['s'] == '1' || x == 1 ? checkField('expiresOn', m['d']!) : null); });
    if (v == null) return;
    final n = normName(v['n']!), mv = int.parse(v['q']!);
    if (v['s'] == '1' || mv == 1) {
      final b = db.batch();
      b.set(col(P.inventory).doc(), inv(n, mv, parseDate(v['d']!)!, from: src));
      if (mv == qn) { b.delete(d.reference); } else { b.update(d.reference, {'quantity': qn - mv, ...stampFields()}); }
      b.commit();
      snack('Moved to the inventory list');
      return;
    }
    var left = qn;
    for (var i = 1; i <= mv; i++) {
      if (!mounted) return;
      final p = await form(context, '$n - $i', [F('d', 'Expiration date', init: '${DateTime.now().year}.', kind: 'date')], check: (m) => checkField('expiresOn', m['d']!));
      if (p == null) return;
      left--;
      final b = db.batch();
      b.set(col(P.inventory).doc(), inv('$n $i', 1, parseDate(p['d']!)!, from: src));
      if (left <= 0) { b.delete(d.reference); } else { b.update(d.reference, {'quantity': left, ...stampFields()}); }
      b.commit();
    }
    if (mounted) snack('Moved to the inventory list');
  }

  Future<void> clrShop() async {
    final rows = (await col(P.shopping).get()).docs;
    if (rows.isEmpty) { snack('The shopping list is empty.'); return; }
    if (!mounted || !await confirm(context, 'Delete all products', 'Delete all ${rows.length} product(s) from the shopping list?', ok: 'Delete all') || !mounted) return;
    final saved = [for (final d in rows) (d.id, d.data())];
    for (var i = 0; i < rows.length; i += 200) {
      final b = db.batch();
      for (final d in rows.skip(i).take(200)) {
        final x = d.data();
        b.set(col(P.archive).doc(d.id), {'name': x['name'], 'quantity': x['quantity'], 'expiresOn': null, 'source': 'shopping', 'deletedByUid': me.uid, 'deletedByName': me.displayName ?? '?',
          'deletedAt': FieldValue.serverTimestamp(), 'shop': x['shop'] ?? '', 'priceFt': x['priceFt'] ?? 0, 'assigneeUid': x['assigneeUid']});
        b.delete(d.reference);
      }
      b.commit();
    }
    snack('All products removed from the shopping list', sec: 5, action: SnackBarAction(label: 'Undo', onPressed: () {
      for (var i = 0; i < saved.length; i += 200) {
        final u = db.batch();
        for (final s in saved.skip(i).take(200)) { u.set(col(P.shopping).doc(s.$1), {...s.$2, ...stampFields()}); u.delete(col(P.archive).doc(s.$1)); }
        u.commit();
      }
    }));
  }

  Widget pc(int flex, Widget w) => Expanded(flex: flex, child: Padding(padding: const EdgeInsets.only(right: 8), child: w));

  Widget head(List<(String, String, int)> cols, String cur, bool asc, void Function(String) tap, {double lead = 0, double trail = 48, VoidCallback? onTrail}) => Container(
      color: Colors.white10,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        SizedBox(width: lead),
        for (final c in cols) pc(c.$3, InkWell(onTap: () => tap(c.$2), child: Text('${c.$1}${cur == c.$2 ? (asc ? ' ▲' : ' ▼') : ''}', style: const TextStyle(fontWeight: FontWeight.bold)))),
        SizedBox(width: trail, child: Align(alignment: Alignment.centerRight, child: SizedBox(width: 48, child: onTrail == null ? const Center(child: Icon(Icons.remove)) : IconButton(icon: const Icon(Icons.remove), onPressed: onTrail)))),
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
          head([('Name', 'name', 5), ('Qty', 'q', 2), ('Expiration date', 'exp', 3)], iSort, iAsc, (k) => setState(() { if (iSort == k) { iAsc = !iAsc; } else { iSort = k; iAsc = true; } })),
          Expanded(child: ListView(children: [for (final d in rows) invRow(d)])),
        ]);
      });

  Widget invRow(Doc d) {
    final left = daysLeft(d['expiresOn']);
    return Container(
        color: left <= 0 ? const Color(0xFF6B1E1E) : left <= 3 ? const Color(0xFF5A4E00) : null,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          pc(5, InkWell(onTap: () => edit(P.inventory, d, 'name', 'Name'), child: Text('${left <= 0 ? '⛔ ' : left <= 3 ? '⚠ ' : ''}${d['name']}'))),
          pc(2, InkWell(onTap: () => edit(P.inventory, d, 'quantity', 'Quantity', kind: 'num'), child: Text('${d['quantity']} db'))),
          pc(3, InkWell(onTap: () => edit(P.inventory, d, 'expiresOn', 'Expiration date', kind: 'date'), child: Text(showDate(d['expiresOn'])))),
          SizedBox(width: 48, child: IconButton(icon: const Icon(Icons.remove), onPressed: () => delInv(d))),
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
          final k = sSort == 'name' ? fold(a['name']).compareTo(fold(b['name'])) : sSort == 'q' ? (a['quantity'] as int).compareTo(b['quantity'] as int) : sSort == 'who' ? '${members[a.data()['assigneeUid']] ?? ''}'.compareTo('${members[b.data()['assigneeUid']] ?? ''}') : t(a).compareTo(t(b));
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
          head([('Name', 'name', 5), ('Qty', 'q', 2), if (multi) ('Who', 'who', 3)], sSort, sAsc, (k) => setState(() { if (sSort == k) { sAsc = !sAsc; } else { sSort = k; sAsc = true; } }), lead: 36, trail: 104, onTrail: clrShop),
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
            pc(5, InkWell(onTap: () => edit(P.shopping, d, 'name', 'Name'), child: Text('${d['name']}'))),
            pc(2, InkWell(onTap: () => edit(P.shopping, d, 'quantity', 'Quantity', kind: 'num'), child: Text('${d['quantity']} db'))),
            if (multi) pc(3, InkWell(onTap: () => edWho(d), child: Text(members['${d.data()['assigneeUid']}'] ?? 'Anyone'))),
            SizedBox(width: 104, child: Align(alignment: Alignment.centerRight, child: IconButton(icon: const Icon(Icons.remove), onPressed: () => delShop(d)))),
          ]),
          Row(children: [
            const SizedBox(width: 36),
            pc(5, InkWell(onTap: () => editSP(d), child: Text(shop.isEmpty ? '–' : shop))),
            pc(2, InkWell(onTap: () => editSP(d), child: Text(p > 0 ? '${thousands(p)} Ft' : '–'))),
            if (multi) const Spacer(flex: 3),
            SizedBox(width: 104, child: Align(alignment: Alignment.centerRight, child: OutlinedButton(onPressed: soon, child: const Text('Check price')))),
          ]),
        ]));
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(
            title: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(stream: db.doc(P.list(widget.listId)).snapshots(), builder: (c, s) => Text('${s.data?.data()?['friendlyName'] ?? ''}')),
            actions: [IconButton(icon: const Icon(Icons.settings), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen(listId: widget.listId))))]),
        body: SafeArea(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(children: [
              SegmentedButton<int>(
                  segments: const [ButtonSegment(value: 0, label: Text('Inventory list')), ButtonSegment(value: 1, label: Text('Shopping list'))],
                  selected: {tab},
                  onSelectionChanged: (s) => setState(() { tab = s.first; q = ''; find = false; })),
              Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: status())),
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
