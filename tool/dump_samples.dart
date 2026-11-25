// Dev tool: dump sample bodies per financial sender + measure ETB misses.
// Run: dart run tool/dump_samples.dart [path-to-messages.ndjson]
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:budget_app/models/models.dart';
import 'package:budget_app/parsers/sms_parser.dart';

void main(List<String> args) {
  final path = args.isNotEmpty
      ? args[0]
      : r'C:\Users\et\AppData\Local\Temp\opencode\sms_export\messages.ndjson';
  final lines = File(path).readAsLinesSync();

  final msgs = <SmsMessage>[];
  for (final line in lines) {
    if (line.trim().isEmpty) continue;
    final m = jsonDecode(line) as Map<String, dynamic>;
    if ((m['type'] ?? '').toString() != '1') continue;
    msgs.add(SmsMessage(
      address: (m['address'] ?? '').toString(),
      body: (m['body'] ?? '').toString(),
      date: DateTime.fromMillisecondsSinceEpoch(
          int.parse((m['date'] ?? '0').toString())),
    ));
  }

  // ── ETB coverage ───────────────────────────────────────────────
  final etb = msgs.where((m) => RegExp(r'\bETB\b').hasMatch(m.body)).toList();
  var etbParsed = 0;
  final etbMiss = <SmsMessage>[];
  for (final m in etb) {
    if (ParserRegistry.parse(m) != null) {
      etbParsed++;
    } else if (etbMiss.length < 200) {
      etbMiss.add(m);
    }
  }
  print('ETB messages: ${etb.length}, parsed: $etbParsed '
      '(${(etbParsed / etb.length * 100).toStringAsFixed(1)}%), '
      'misses: ${etbMiss.length} (showing up to 200)');

  // Prioritise misses from financial-looking senders
  const finSenders = {
    'CBE', 'BOA', 'telebirr', 'Dashen Bank', 'DB SuperApp', '7533',
    'CNETPay', 'USP', 'EEU Info', 'AWACHSACCO', 'Gadaa Bank', 'NIB',
    'DigitalEqub', 'MPESA Info', 'Safaricom', 'OCTB', '127', '8611',
    '824', '830', '810', '130', '131',
  };
  final prioritised = etbMiss
      .where((m) => finSenders.contains(m.address))
      .take(70)
      .toList();
  final rest = etbMiss
      .where((m) => !finSenders.contains(m.address))
      .take(40)
      .toList();

  print('\n=== ETB misses from financial senders ===');
  for (final m in prioritised) {
    print('[${m.address}] ${m.body.replaceAll('\n', ' ')}');
  }
  print('\n=== ETB misses, other senders ===');
  for (final m in rest) {
    print('[${m.address}] ${m.body.replaceAll('\n', ' ')}');
  }

  // ── Sample full bodies per key sender ──────────────────────────
  print('\n=== samples per sender ===');
  const show = [
    'CBE', 'BOA', 'telebirr', 'Dashen Bank', 'DB SuperApp', '7533',
    'CNETPay', 'USP', 'EEU Info', 'AWACHSACCO', 'Gadaa Bank', 'NIB',
    'MPESA Info', 'OCTB', 'DigitalEqub',
  ];
  for (final sender in show) {
    final list = msgs.where((m) => m.address == sender).take(4).toList();
    if (list.isEmpty) continue;
    print('\n--- $sender (${msgs.where((m) => m.address == sender).length}) ---');
    for (final m in list) {
      print('  ${m.body.replaceAll('\n', ' ')}');
    }
  }
}
