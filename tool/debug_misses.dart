// Dev tool: per-guard diagnostics for specific corpus messages.
// Run: dart run tool/debug_misses.dart [path-to-messages.ndjson]
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

  final probes = <String, String>{
    'BOA debited': 'was debited with ETB 3.01',
    'Dashen 800k': 'transferred ETB 800,000.00',
    'CNETPay paid': 'paid ETB 100.00 by telebirr',
    'EEU payment': 'payment of ETB 8000 with charge',
    'CBE transfer': 'successfully transferred ETB 100,000.00',
  };

  final remaining = probes.keys.toList();
  for (final line in File(path).readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    final m = jsonDecode(line) as Map<String, dynamic>;
    if ((m['type'] ?? '').toString() != '1') continue;
    final body = (m['body'] ?? '').toString();

    for (final key in remaining.toList()) {
      if (!body.contains(probes[key]!)) continue;
      remaining.remove(key); // first hit only
      print('=== $key ===');
      print('sender: ${m['address']}');
      print('codepoints of head: '
          '${body.substring(0, body.length.clamp(0, 40)).runes.join(',')}');
      print('otpWord: ${looksLikeOtp(body)}');
      print('reminder: ${looksLikeReminder(body)}');
      final amt = extractAmount(body);
      print('amount: ${amt?.value} cur=${amt?.currency}');
      print('type: ${extractType(body)}');
      print('date: ${extractDate(body, DateTime(2000))}');
      print('merchant: ${extractMerchant(body)}');
      print('balance: ${extractBalance(body)}');
      final t = ParserRegistry.parse(
          SmsMessage(address: (m['address'] ?? '').toString(), body: body,
              date: DateTime.fromMillisecondsSinceEpoch(
                  int.parse((m['date'] ?? '0').toString()))));
      print('PARSE RESULT: ${t == null ? 'NULL' : 'ok amount=${t.amount} type=${t.type} merchant=${t.merchant}'}');
      print('');
    }
    if (remaining.isEmpty) break;
  }
}
