import 'package:budget_app/models/models.dart';
import 'package:budget_app/parsers/extractors.dart';
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

    // ── Real samples from an Ethiopian SMS corpus (ETB) ───────────

    test('parses a CBE transfer with ETB currency, payee and balance', () {
      final t = ParserRegistry.parse(sms(
        'Dear Elias Tsegaye Girmaye You have successfully transferred '
        'ETB 100,000.00 from account 1********8521 to account '
        '1********5979 (Mussie Tsegaye Girmay). Service charge of ETB 5.00 '
        'and VAT(15%) of ETB 0.75 and Disaster Recovery(5%) of 0.25 with '
        'total of ETB 100,006.00. Your current balance is ETB 2,006,413.63. '
        'Thanks for Banking with CBE.',
        sender: 'CBE',
      ));
      expect(t, isNotNull);
      expect(t!.amount, 100000.0);
      expect(t.type, TxType.debit);
      expect(t.merchant, 'Mussie Tsegaye Girmay');
      expect(t.balance, 2006413.63);
      expect(t.currency, 'ETB');
      expect(t.bank, 'Commercial Bank of Ethiopia');
    });

    test('parses a CBE incoming transfer as credit', () {
      final t = ParserRegistry.parse(sms(
        'Dear Elias Tsegaye Girmaye You have received ETB 399,999.00 from '
        'account 1********8731 (Eyosias Adeto Keto) to your account '
        '1********8521. Your current balance is ETB 3,006,422.63. '
        'Thanks for Banking with CBE.',
        sender: 'CBE',
      ));
      expect(t, isNotNull);
      expect(t!.amount, 399999.0);
      expect(t.type, TxType.credit);
      expect(t.merchant, 'Eyosias Adeto Keto');
      expect(t.balance, 3006422.63);
    });

    test('parses BOA debit with "Available Balance"', () {
      final t = ParserRegistry.parse(sms(
        'Dear Elias, your account 2*****68 was debited with ETB 3.01. '
        'Available Balance: ETB 131,430.53. Receipt: '
        'https://cs.bankofabyssinia.com/slip/?trx=FT26315. '
        'Bank of Abyssinia.',
        sender: 'BOA',
      ));
      expect(t, isNotNull);
      expect(t!.amount, 3.01);
      expect(t.type, TxType.debit);
      expect(t.balance, 131430.53);
      expect(t.currency, 'ETB');
      expect(t.bank, 'Bank of Abyssinia');
    });

    test('parses CNETPay POS payment with company + datetime', () {
      final t = ParserRegistry.parse(sms(
        'Dear Customer, You have paid ETB 100.00 by telebirr SMS OTP for '
        'PRESENCE MANUFACTURING PLC, Summit on 10/10/2026 19:44:12. '
        'For attachment: https://et.hulubeje.com/print?voucher=997225',
        sender: 'CNETPay',
      ));
      expect(t, isNotNull);
      expect(t!.amount, 100.0);
      expect(t.type, TxType.debit);
      expect(t.merchant, 'PRESENCE MANUFACTURING PLC');
      expect(t.date, DateTime(2026, 10, 10, 19, 44, 12));
      expect(t.bank, 'CNETPay');
    });

    test('parses Dashen SuperApp transfer with possessive payee', () {
      final t = ParserRegistry.parse(sms(
        'Dear ELIAS TSEGAYE GIRMAYE, you have successfully transferred '
        'ETB 800,000.00 from your account number 5318******021 to '
        "Hana Chala Ibsa's account number 5449******011 on 2026-11-17 "
        'at 03:53:59 with transaction reference: 426WDTS2632100WQ. '
        'Your current balance is ETB 996,671.11.',
        sender: 'DB SuperApp',
      ));
      expect(t, isNotNull);
      expect(t!.amount, 800000.0);
      expect(t.type, TxType.debit);
      expect(t.merchant, 'Hana Chala Ibsa');
      expect(t.date, DateTime(2026, 11, 17, 3, 53, 59));
      expect(t.balance, 996671.11);
      expect(t.bank, 'Dashen Bank');
    });

    test('parses utility payment (EEU) without a merchant', () {
      final t = ParserRegistry.parse(sms(
        'Dear customer, payment of ETB 8000 with charge value ETB 6766 for '
        'your prepaid customer ID 82651 through telebirr has been received.',
        sender: 'EEU Info',
      ));
      expect(t, isNotNull);
      expect(t!.amount, 8000.0);
      expect(t.type, TxType.debit);
      expect(t.bank, 'Ethio Electric Utility');
    });

    // ── User labels, new categories, word-boundary matching ───────

    test('a user-assigned sender label overrides bank detection', () {
      senderLabels['251994'] = 'Ethio Telecom';
      try {
        expect(detectBank('251994'), 'Ethio Telecom');
        expect(detectBank('CBE'), 'Commercial Bank of Ethiopia');
      } finally {
        senderLabels.clear();
      }
    });

    test('detects Family Support and Loan categories', () {
      expect(
        inferCategory(null, 'Rs.2,000.00 sent to MOM on 25-11-2026'),
        'Family Support',
      );
      expect(
        inferCategory(null, 'Rs.15,000.00 home loan EMI debited on 25-11'),
        'Loan',
      );
      expect(inferCategory('SWIGGY', 'order paid'), 'Food & Dining');
    });

    test('word boundaries stop substring false positives', () {
      // "moment" contains "mom", "premium" contains "emi".
      expect(inferCategory(null, 'The moment is yours! Dial *131#'),
          'Other');
      expect(inferCategory(null, 'Your premium package renewal is due'),
          'Other');
    });

    test('allCategories covers built-ins plus Other', () {
      expect(allCategories, contains('Food & Dining'));
      expect(allCategories, contains('Family Support'));
      expect(allCategories, contains('Loan'));
      expect(allCategories.last, 'Other');
    });
  });
}
