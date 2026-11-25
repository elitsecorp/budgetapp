// Dev tool: analyze an ndjson SMS export against our parser.
// Run: dart run tool/analyze_export.dart [path-to-messages.ndjson]
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:budget_app/models/models.dart';
import 'package:budget_app/parsers/extractors.dart';
import 'package:budget_app/parsers/sms_parser.dart';

void main(List<String> args) {
  final path = args.isNotEmpty
      ? args[0]
      : r'C:\Users\et\AppData\Local\Temp\opencode\sms_export\messages.ndjson';
  final lines = File(path).readAsLinesSync();
  print('total lines: ${lines.length}');

  final msgs = <SmsMessage>[];
  final typeCounts = <String, int>{};
  for (final line in lines) {
    if (line.trim().isEmpty) continue;
    final m = jsonDecode(line) as Map<String, dynamic>;
    final type = (m['type'] ?? '?').toString();
    typeCounts[type] = (typeCounts[type] ?? 0) + 1;
    if (type != '1') continue; // inbox only
    msgs.add(SmsMessage(
      address: (m['address'] ?? '').toString(),
      body: (m['body'] ?? '').toString(),
      date: DateTime.fromMillisecondsSinceEpoch(
          int.parse((m['date'] ?? '0').toString())),
    ));
  }
  print('by type: $typeCounts');
  print('inbox messages: ${msgs.length}');

  // ── Top senders ────────────────────────────────────────────────
  final senders = <String, int>{};
  for (final m in msgs) {
    senders[m.address] = (senders[m.address] ?? 0) + 1;
  }
  final top = senders.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  print('\n--- top 30 senders ---');
  for (final e in top.take(30)) {
    print('${e.value.toString().padLeft(5)}  ${e.key}');
  }

  // ── Money-ish messages and parser coverage ─────────────────────
  final moneyRe = RegExp(
      r'\b(etb|br\b|birr|usd|\$|inr|rs\.?|paid|payment|debit|credit|transfer|balance|purchased|withdraw|deposit|atm|pos|telebirr|cbe|awash|dashen|abyssinia|nib|zemen|lion|abay|oromia|amhara)\b',
      caseSensitive: false);
  final money = msgs.where((m) => moneyRe.hasMatch(m.body)).toList();
  print('\nmoney-ish messages: ${money.length}');

  var parsed = 0;
  final unparsed = <String>[];
  final seen = <String>{};
  for (final m in money) {
    final t = ParserRegistry.parse(m);
    if (t != null) {
      parsed++;
    } else {
      final key = '${m.address}|${m.body.substring(0, m.body.length.clamp(0, 50))}';
      if (seen.add(key) && unparsed.length < 60) unparsed.add(key);
    }
  }
  print('parsed: $parsed  (${(parsed / money.length * 100).toStringAsFixed(1)}%)');
  print('unparsed samples (up to 60):');
  for (final u in unparsed) {
    final parts = u.split('|');
    final body = parts.sublist(1).join('|');
    print('  [${parts[0]}] ${body.replaceAll('\n', ' ')}');
  }

  // ── Currency tokens ────────────────────────────────────────────
  print('\n--- currency tokens ---');
  final curRe = RegExp(r'\b(ETB|Br|Birr|USD|EUR|GBP|INR|Rs)\b\s?[\d,]',
      caseSensitive: false);
  final curs = <String, int>{};
  for (final m in msgs) {
    for (final c in curRe.allMatches(m.body)) {
      curs[c.group(1)!] = (curs[c.group(1)!] ?? 0) + 1;
    }
  }
  print(curs);

  // ── Date formats ───────────────────────────────────────────────
  print('\n--- date-like tokens ---');
  final dateRes = <String, RegExp>{
    'dd/mm/yyyy': RegExp(r'\b\d{1,2}/\d{1,2}/\d{4}\b'),
    'dd-mm-yyyy': RegExp(r'\b\d{1,2}-\d{1,2}-\d{4}\b'),
    'dd/mm/yy': RegExp(r'\b\d{1,2}/\d{1,2}/\d{2}\b'),
    'iso': RegExp(r'\b\d{4}-\d{2}-\d{2}\b'),
    'dd Month yyyy': RegExp(r'\b\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{4}\b', caseSensitive: false),
  };
  for (final e in dateRes.entries) {
    var n = 0;
    for (final m in msgs) {
      if (e.value.hasMatch(m.body)) n++;
    }
    print('${e.key}: $n');
  }

  // ── Owner name candidates ("Dear X") ───────────────────────────
  print('\n--- Dear <NAME> frequency ---');
  final dearRe = RegExp(r'\bDear\s+([A-Z][A-Za-z]+(?:\s+[A-Z][A-Za-z]+)?)\b');
  final names = <String, int>{};
  for (final m in msgs) {
    final d = dearRe.firstMatch(m.body);
    if (d != null) names[d.group(1)!] = (names[d.group(1)!] ?? 0) + 1;
  }
  final topNames = names.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in topNames.take(15)) {
    print('${e.value.toString().padLeft(4)}  ${e.key}');
  }

  // ── Owner phone candidates ─────────────────────────────────────
  print('\n--- phone-ish tokens in bodies ---');
  final phoneRe = RegExp(r'\b9\d{8}\b');
  final phones = <String, int>{};
  for (final m in msgs) {
    for (final p in phoneRe.allMatches(m.body)) {
      phones[p.group(0)!] = (phones[p.group(0)!] ?? 0) + 1;
    }
  }
  final topPhones = phones.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in topPhones.take(10)) {
    print('${e.value.toString().padLeft(4)}  ${e.key}');
  }

  // ── Bank-ish senders seen in parsed results ────────────────────
  print('\n--- bank markers seen in sender addresses ---');
  final bankish = <String>{};
  for (final m in msgs) {
    if (detectBank(m.address) != m.address) bankish.add(m.address);
  }
  print(bankish.take(40).join(', '));
}
