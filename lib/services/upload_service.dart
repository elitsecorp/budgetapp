/// POSTs transactions to a user-configured server endpoint.
/// This — plus APK updates — is the app's only internet usage.
library;

import 'dart:convert';
import 'dart:io';

import '../models/models.dart';

Future<String> sendTransactions({
  required String url,
  required List<Transaction> transactions,
  String? ownerName,
  String? ownerPhone,
  int limit = 200,
}) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
    return 'Invalid URL — paste a full http(s) address';
  }

  final list = transactions.take(limit).toList(); // newest first
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.headers.set('User-Agent', 'BudgetApp/0.2');
    request.write(jsonEncode({
      'owner': {'name': ownerName, 'phone': ownerPhone},
      'sentAt': DateTime.now().toIso8601String(),
      'count': list.length,
      'transactions': [
        for (final t in list)
          {
            'date': t.date.toIso8601String(),
            'type': t.type == TxType.debit ? 'debit' : 'credit',
            'amount': t.amount,
            'currency': t.currency,
            'merchant': t.merchant,
            'category': t.category,
            'bank': t.bank,
            'sender': t.sender,
            'senderName': t.senderName,
            'balance': t.balance,
            'raw': t.raw,
          },
      ],
    }));
    final resp = await request
        .close()
        .timeout(const Duration(seconds: 30));
    await resp.drain<void>();
    return 'Server responded: HTTP ${resp.statusCode} — sent ${list.length} transactions';
  } catch (e) {
    return 'Failed: $e';
  } finally {
    client.close(force: true);
  }
}
