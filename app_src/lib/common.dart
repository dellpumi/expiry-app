import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'validators.dart';

const itemGone = 'That item was changed or removed by someone else.';
const _f = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ö': 'o', 'ő': 'o', 'ú': 'u', 'ü': 'u', 'ű': 'u'};
String fold(String s) => s.toLowerCase().split('').map((c) => _f[c] ?? c).join();
String thousands(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ' ');

String? parseDate(String t) {
  final d = t.replaceAll(RegExp(r'\D'), '');
  int y, m, dd;
  if (d.length == 8) { y = int.parse(d.substring(0, 4)); m = int.parse(d.substring(4, 6)); dd = int.parse(d.substring(6)); }
  else if (d.length == 6) { y = int.parse(d.substring(0, 4)); m = int.parse(d.substring(4)); dd = 28; }
  else { return null; }
  if (y < 2000 || y > 2100 || m < 1 || m > 12 || dd < 1) return null;
  final dt = DateTime(y, m, dd);
  if (dt.month != m || dt.day != dd) return null;
  return '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${dd.toString().padLeft(2, '0')}';
}

String showDate(String iso) => iso.replaceAll('-', '.');
int daysLeft(String iso) {
  final p = iso.split('-').map(int.parse).toList(), n = DateTime.now();
  return DateTime.utc(p[0], p[1], p[2]).difference(DateTime.utc(n.year, n.month, n.day)).inDays;
}

class DateMask extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue o, TextEditingValue n) {
    final d = n.text.replaceAll(RegExp(r'\D'), ''), x = d.length > 8 ? d.substring(0, 8) : d;
    final t = x.length > 4 ? '${x.substring(0, 4)}.${x.length > 6 ? '${x.substring(4, 6)}.${x.substring(6)}' : x.substring(4)}' : x;
    return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
  }
}

String? checkField(String f, String v) {
  if (f == 'name') { final n = normName(v); return n.isEmpty || n.length > 80 ? 'Name: 1–80 characters.' : null; }
  if (f == 'quantity') { final q = int.tryParse(v); return q == null || q < 1 || q > 999 ? 'Quantity: 1–999.' : null; }
  return parseDate(v) == null ? 'Enter a valid expiration date.' : null;
}

String? checkSP(String s, String p) =>
    normName(s).length > 40 ? 'Shop name: up to 40 characters.' : (p.length > 7 ? 'Unit price: 0–9,999,999 Ft.' : null);

Map<String, dynamic> stampFields() => {'updatedAt': FieldValue.serverTimestamp(), 'updatedByUid': FirebaseAuth.instance.currentUser!.uid};
Map<String, dynamic> createdFields() => {...stampFields(), 'createdAt': FieldValue.serverTimestamp(), 'createdByUid': FirebaseAuth.instance.currentUser!.uid};

class F {
  final String id, label, init, kind; // kind: text | num | date | check
  const F(this.id, this.label, {this.init = '', this.kind = 'text'});
}

/// One reusable dialog. Returns the values, or null on cancel. With onSave the dialog stays open and clears the fields in [clear].
Future<Map<String, String>?> form(BuildContext c, String title, List<F> fs,
    {String ok = 'Save', String cancel = 'Cancel', String? text, String? Function(Map<String, String>)? check,
    Future<void> Function(Map<String, String>)? onSave, Map<String, String> clear = const {}}) {
  final ctl = {for (final f in fs) f.id: TextEditingController(text: f.init)};
  final chk = {for (final f in fs) f.id: f.init == '1'};
  final shown = <String>{};
  var err = '';
  return showDialog<Map<String, String>>(
      context: c,
      builder: (_) => StatefulBuilder(builder: (c2, set) {
            Map<String, String> vals() => {for (final f in fs) f.id: f.kind == 'check' ? (chk[f.id]! ? '1' : '0') : ctl[f.id]!.text};
            return AlertDialog(
              title: Text(title),
              content: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (text != null) Text(text),
                for (final f in fs)
                  f.kind == 'check'
                      ? CheckboxListTile(contentPadding: EdgeInsets.zero, title: Text(f.label), value: chk[f.id], onChanged: (v) => set(() => chk[f.id] = v!))
                      : TextField(
                          controller: ctl[f.id],
                          decoration: InputDecoration(labelText: f.label, suffixIcon: f.kind == 'pw' ? IconButton(icon: Icon(shown.contains(f.id) ? Icons.visibility_off : Icons.visibility), onPressed: () => set(() { shown.contains(f.id) ? shown.remove(f.id) : shown.add(f.id); })) : null),
                          obscureText: f.kind == 'pw' && !shown.contains(f.id),
                          keyboardType: f.kind == 'text' || f.kind == 'pw' ? null : TextInputType.number,
                          inputFormatters: f.kind == 'date' ? [DateMask()] : f.kind == 'num' ? [FilteringTextInputFormatter.digitsOnly] : null),
                if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err, style: const TextStyle(color: Colors.redAccent))),
              ])),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c2), child: Text(cancel)),
                FilledButton(
                    onPressed: () async {
                      final v = vals(), e = check?.call(v);
                      if (e != null) { set(() => err = e); return; }
                      if (onSave != null) {
                        await onSave(v);
                        clear.forEach((k, val) => ctl[k]?.text = val);
                        set(() => err = '');
                        return;
                      }
                      Navigator.pop(c2, v);
                    },
                    child: Text(ok)),
              ],
            );
          }));
}

Future<bool> confirm(BuildContext c, String title, String text, {String ok = 'Yes'}) async =>
    (await showDialog<bool>(
        context: c,
        builder: (k) => AlertDialog(title: Text(title), content: Text(text), actions: [
              TextButton(onPressed: () => Navigator.pop(k, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(k, true), child: Text(ok)),
            ]))) ??
    false;
