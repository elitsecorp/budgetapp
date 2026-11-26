/// POSTs transactions to the sync server (`POST /api/sync`).
/// This — plus APK updates — is the app's only internet usage.
///
/// Contract (see server/budget_server/api.py):
/// * `X-API-Key` header when the server configures `API_KEY`
/// * `owner.phone` is REQUIRED (server answers 400 without it)
/// * each transaction carries `date_ms` (epoch ms — unambiguous, avoids the
///   naive-ISO timezone trap) and `dedupe` (server's natural key)
/// * 200 → `{accepted, duplicates, total}`; 401 → bad key; 400 → `{error}`
library;

import 'dart:convert';
import 'dart:io';

import '../models/models.dart';

class SendOutcome {
  final bool success;
  final String message;
  final List<int> sentIds; // transactions the server confirmed (2xx)
  const SendOutcome(this.success, this.message, [this.sentIds = const []]);
}

const _chunkSize = 500;

Future<SendOutcome> sendTransactions({
  required String url,
  required List<Transaction> transactions,
  String? ownerName,
  String? ownerPhone,
  String apiKey = '',
}) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
    return const SendOutcome(false, 'Invalid URL — paste a full http(s) address');
  }
  if (transactions.isEmpty) {
    return const SendOutcome(false, 'Nothing to send.');
  }

  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);
  final confirmed = <int>[];
  var totalAccepted = 0;
  var totalDuplicates = 0;

  try {
    for (var start = 0; start < transactions.length; start += _chunkSize) {
      final chunk = transactions
          .skip(start)
          .take(_chunkSize)
          .where((t) => t.id != null)
          .toList();
      if (chunk.isEmpty) continue;

      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.headers.set('User-Agent', 'BudgetApp/0.3');
      if (apiKey.isNotEmpty) request.headers.set('X-API-Key', apiKey);
      request.write(jsonEncode({
        'owner': {'name': ownerName, 'phone': ownerPhone},
        'sentAt': DateTime.now().toIso8601String(),
        'count': chunk.length,
        'transactions': [
          for (final t in chunk)
            {
              'date_ms': t.date.millisecondsSinceEpoch,
              'dedupe': t.dedupe,
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

      final resp = await request.close().timeout(const Duration(seconds: 60));
      final body = await utf8.decoder.bind(resp).join();
      Map<String, dynamic>? json;
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) json = decoded;
      } catch (_) {
        // Non-JSON body (proxy error page etc.) — handled below.
      }

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        final detail = json?['error']?.toString() ??
            'HTTP ${resp.statusCode} ${body.length < 200 ? body : ''}';
        if (resp.statusCode == 401) {
          return SendOutcome(
            false,
            'Server rejected the API key (401) — set the key under '
            '"Send to server".',
            confirmed,
          );
        }
        if (resp.statusCode == 400) {
          return SendOutcome(
            false,
            'Server refused the data (400): $detail',
            confirmed,
          );
        }
        return SendOutcome(
          false,
            'Server error: $detail — ${confirmed.length} already synced, '
            '${transactions.length - confirmed.length} still pending.',
          confirmed,
        );
      }

      confirmed.addAll(chunk.map((t) => t.id!));
      totalAccepted += (json?['accepted'] as num?)?.toInt() ?? chunk.length;
      totalDuplicates +=
          (json?['duplicates'] as num?)?.toInt() ?? 0;
    }

    final msg = 'Synced ${confirmed.length} transaction(s): '
        '$totalAccepted new, $totalDuplicates duplicate(s) already on server.';
    return SendOutcome(true, msg, confirmed);
  } catch (e) {
    return SendOutcome(
      false,
      'Failed: $e — ${confirmed.length} already synced, '
      '${transactions.length - confirmed.length} still pending.',
      confirmed,
    );
  } finally {
    client.close(force: true);
  }
}
