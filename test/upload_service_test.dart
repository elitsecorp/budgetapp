import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:budget_app/models/models.dart';
import 'package:budget_app/services/upload_service.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction tx(int id, {double amount = 100, DateTime? date}) => Transaction(
      id: id,
      sender: 'CBE',
      bank: 'Commercial Bank of Ethiopia',
      merchant: 'SWIGGY',
      amount: amount,
      type: TxType.debit,
      date: date ?? DateTime(2026, 11, 25, 14, 30),
      currency: 'ETB',
      category: 'Food & Dining',
      raw: 'raw text $id',
      sent: false,
    );

/// Spins a local HTTP server, hands the captured request to [onRequest],
/// and responds with [status] + [body].
Future<({HttpServer server, Future<void> done})> serve(
  FutureOr<HttpResponse> Function(HttpRequest request) onRequest,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final done = server.first.then((req) async {
    final resp = await onRequest(req);
    await resp.close();
  });
  return (server: server, done: done);
}

void main() {
  group('sendTransactions ↔ /api/sync contract', () {
    test('sends date_ms, dedupe, owner.phone and X-API-Key', () async {
      late Map<String, dynamic> body;
      late String? apiKeyHeader;
      final s = await serve((req) {
        apiKeyHeader = req.headers.value('X-API-Key');
        final completerBody = utf8.decoder.bind(req);
        return completerBody.join().then((text) {
          body = jsonDecode(text) as Map<String, dynamic>;
          req.response.headers.contentType = ContentType.json;
          req.response.write(
              '{"user_id": 1, "created": false, "accepted": 2, "duplicates": 0, "total": 2}');
          return req.response;
        });
      });

      final outcome = await sendTransactions(
        url: 'http://127.0.0.1:${s.server.port}/api/sync',
        transactions: [tx(1, amount: 499), tx(2, amount: 250)],
        ownerName: 'Elias Tsegaye Girmaye',
        ownerPhone: '927709161',
        apiKey: 'secret-key',
      );
      await s.done;
      await s.server.close(force: true);

      expect(outcome.success, isTrue);
      expect(outcome.sentIds, [1, 2]);
      expect(outcome.message, contains('2 new'));
      expect(apiKeyHeader, 'secret-key');

      expect(body['owner'], {'name': 'Elias Tsegaye Girmaye', 'phone': '927709161'});
      expect(body['count'], 2);
      final first = (body['transactions'] as List).first as Map<String, dynamic>;
      expect(first['date_ms'], DateTime(2026, 11, 25, 14, 30).millisecondsSinceEpoch);
      expect(first['dedupe'], isNotEmpty);
      expect(first['type'], 'debit');
      expect(first['amount'], 499);
      expect(first['raw'], 'raw text 1');
    });

    test('reports a missing API key (401) without marking anything sent',
        () async {
      final s = await serve((req) {
        req.response.statusCode = 401;
        req.response.headers.contentType = ContentType.json;
        req.response.write('{"error": "missing or invalid API key"}');
        return req.response;
      });

      final outcome = await sendTransactions(
        url: 'http://127.0.0.1:${s.server.port}/api/sync',
        transactions: [tx(7)],
        ownerPhone: '927709161',
      );
      await s.done;
      await s.server.close(force: true);

      expect(outcome.success, isFalse);
      expect(outcome.sentIds, isEmpty);
      expect(outcome.message, contains('API key'));
    });

    test('surfaces server-side validation errors (400)', () async {
      final s = await serve((req) {
        req.response.statusCode = 400;
        req.response.headers.contentType = ContentType.json;
        req.response.write('{"error": "phone is required"}');
        return req.response;
      });

      final outcome = await sendTransactions(
        url: 'http://127.0.0.1:${s.server.port}/api/sync',
        transactions: [tx(7)],
        ownerPhone: '927709161',
      );
      await s.done;
      await s.server.close(force: true);

      expect(outcome.success, isFalse);
      expect(outcome.sentIds, isEmpty);
      expect(outcome.message, contains('phone is required'));
    });

    test('rejects non-http URLs before any network call', () async {
      final outcome = await sendTransactions(
        url: 'ftp://example.com/sync',
        transactions: [tx(1)],
        ownerPhone: '927709161',
      );
      expect(outcome.success, isFalse);
      expect(outcome.message, contains('Invalid URL'));
    });
  });
}
