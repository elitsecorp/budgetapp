import 'package:budget_app/models/models.dart';
import 'package:budget_app/parsers/sms_parser.dart';
import 'package:flutter_test/flutter_test.dart';

SmsMessage sms(
  String body, {
  String sender = 'HDFCBK',
  DateTime? date,
}) =>
    SmsMessage(
      address: sender,
      body: body,
      date: date ?? DateTime(2026, 11, 25, 10, 30),
    );

void main() {
  group('ParserRegistry', () {
    test('parses a classic HDFC debit alert', () {
      final t = ParserRegistry.parse(sms(
        'Rs.499.00 debited from a/c XX1234 on 25-11-2026 to SWIGGY via UPI. '
        'Avl Bal: Rs.12,345.67',
      ));

      expect(t, isNotNull);
      expect(t!.amount, 499.0);
      expect(t.type, TxType.debit);
      expect(t.merchant, 'SWIGGY');
      expect(t.date, DateTime(2026, 11, 25));
      expect(t.balance, 12345.67);
      expect(t.bank, 'HDFC Bank');
      expect(t.category, 'Food & Dining');
      expect(t.currency, 'INR');
    });

    test('parses an ICICI credit alert with multi-word sender', () {
      final t = ParserRegistry.parse(sms(
        'INR 5,000.00 credited to a/c XX1234 on 24/11/2026 from AMIT KUMAR '
        'via IMPS. Avl Bal INR 20,000.00',
        sender: 'ICICIB',
      ));

      expect(t, isNotNull);
      expect(t!.amount, 5000.0);
      expect(t.type, TxType.credit);
      expect(t.merchant, 'AMIT KUMAR');
      expect(t.date, DateTime(2026, 11, 24));
      expect(t.balance, 20000.0);
      expect(t.bank, 'ICICI Bank');
    });

    test('parses a bare-amount debit from an unknown sender', () {
      final t = ParserRegistry.parse(sms(
        'Rs 250 spent at CAFE COFFEE on 25/11/2026',
        sender: 'MYBANK',
      ));

      expect(t, isNotNull);
      expect(t!.amount, 250.0);
      expect(t.type, TxType.debit);
      expect(t.merchant, 'CAFE COFFEE');
      expect(t.date, DateTime(2026, 11, 25));
      expect(t.category, 'Food & Dining');
    });

    test('parses USD amount with ISO date', () {
      final t = ParserRegistry.parse(sms(
        'USD25.50 spent at STARBUCKS on 2026-11-20',
        sender: 'CHASE',
      ));

      expect(t, isNotNull);
      expect(t!.amount, 25.5);
      expect(t.type, TxType.debit);
      expect(t.currency, 'USD');
      expect(t.date, DateTime(2026, 11, 20));
      expect(t.merchant, 'STARBUCKS');
    });

    test('ignores OTP messages even when they contain digits', () {
      expect(
        ParserRegistry.parse(
            sms('123456 is your OTP for login. Do not share it with anyone.')),
        isNull,
      );
    });

    test('ignores non-transactional messages', () {
      expect(
        ParserRegistry.parse(sms(
          'Your order has shipped and will arrive tomorrow.',
          sender: 'MYBANK',
        )),
        isNull,
      );
    });

    test('identifies bank from alphanumeric sender', () {
      final t = ParserRegistry.parse(sms(
        'Rs.100.00 debited from a/c XX9999 on 01-11-2026 to NETFLIX via UPI.',
        sender: 'HDFCBK',
      ));
      expect(t, isNotNull);
      expect(t!.bank, 'HDFC Bank');
      expect(t.category, 'Entertainment');
    });

    // ── Hints adopted from open-source parsers ─────────────────────

    test('rejects lender repayment reminders (no money moves)', () {
      expect(
        ParserRegistry.parse(sms(
          'Kindly repay Rs.4,735.00 due on 30-11-2026 to avoid late payment '
          'charges. T&C apply.',
          sender: 'HDFCBK',
        )),
        isNull,
      );
      expect(
        ParserRegistry.parse(sms(
          'Payment due date for your card is 05-12-2026. Minimum due '
          'Rs.1,200.00. Pay online to avoid charges.',
          sender: 'ICICIB',
        )),
        isNull,
      );
    });

    test('extracts merchant from a UPI handle (to NAME@bank)', () {
      final t = ParserRegistry.parse(sms(
        'Rs.350.00 debited from a/c XX1234 on 25-11-2026 to CAFE@ybl via UPI.',
      ));
      expect(t, isNotNull);
      expect(t!.merchant, 'CAFE');
      expect(t.type, TxType.debit);
    });

    test('reads "available limit" balance phrasing', () {
      final t = ParserRegistry.parse(sms(
        'INR 999.00 debited from a/c XX1234 on 25-11-2026 to NETFLIX via '
        'UPI. Available limit: INR 50,000.00',
        sender: 'ICICIB',
      ));
      expect(t, isNotNull);
      expect(t!.balance, 50000.0);
    });

    test('classifies internet/mobile bills as their own category', () {
      final t = ParserRegistry.parse(sms(
        'Rs.999.00 debited from a/c XX1234 on 25-11-2026 to AIRTEL via UPI.',
      ));
      expect(t, isNotNull);
      expect(t!.category, 'Internet & Phone');
    });
  });
}
