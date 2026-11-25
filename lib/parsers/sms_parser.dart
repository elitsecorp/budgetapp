/// Parser interface, bank-specific wrappers and the registry that routes an
/// SMS to the first parser that understands it (generic parser as fallback).
library;

import '../models/models.dart';
import 'extractors.dart';

abstract class SmsParser {
  bool canParse(SmsMessage msg);

  /// Returns null when the message matched this parser but could not be
  /// turned into a transaction (the registry then tries the next parser).
  Transaction? parse(SmsMessage msg);
}

/// Understands the common shapes of bank alert SMS across banks.
class GenericParser implements SmsParser {
  const GenericParser();

  @override
  bool canParse(SmsMessage msg) => true;

  @override
  Transaction? parse(SmsMessage msg) {
    final body = msg.body;
    if (looksLikeOtp(body) || looksLikeReminder(body)) return null;

    final amount = extractAmount(body);
    if (amount == null) return null;

    final type = extractType(body);
    if (type == null) return null;

    final merchant = extractMerchant(body);
    return Transaction(
      sender: msg.address,
      bank: detectBank(msg.address),
      merchant: merchant,
      amount: amount.value,
      type: type,
      date: extractDate(body, msg.date),
      balance: extractBalance(body),
      currency: amount.currency,
      category: inferCategory(merchant, body),
      raw: body,
    );
  }
}

/// A parser that only applies to messages from a specific bank, tagging the
/// result with the bank's display name. Add your bank's real message format
/// here as you collect samples from the raw-inbox screen.
class BankParser implements SmsParser {
  final List<String> markers;
  final String bankName;
  final SmsParser delegate;

  const BankParser(this.markers, this.bankName,
      {this.delegate = const GenericParser()});

  @override
  bool canParse(SmsMessage msg) {
    final a = msg.address.toUpperCase();
    return markers.any(a.contains);
  }

  @override
  Transaction? parse(SmsMessage msg) {
    final t = delegate.parse(msg);
    if (t == null) return null;
    // Give priority to the generic parser's fields but force our bank name
    // when the generic one could not identify the sender.
    return t.bank == t.sender ? t.copyWith(bank: bankName) : t;
  }
}

class ParserRegistry {
  ParserRegistry._();

  static const _banks = <SmsParser>[
    BankParser(['HDFC'], 'HDFC Bank'),
    BankParser(['ICICI', 'ICIC'], 'ICICI Bank'),
    BankParser(['SBIN', 'SBIIN', 'SBIP', 'SBI'], 'State Bank of India'),
    BankParser(['KKBK', 'KOTAK'], 'Kotak Mahindra Bank'),
    BankParser(['AXBK', 'AXIS'], 'Axis Bank'),
    BankParser(['PNBS', 'PUNB'], 'Punjab National Bank'),
    BankParser(['CNRB'], 'Canara Bank'),
    BankParser(['BARB'], 'Bank of Baroda'),
    BankParser(['YESB'], 'Yes Bank'),
    BankParser(['IDFB', 'IDFC'], 'IDFC First Bank'),
    BankParser(['INDUS', 'INDB'], 'IndusInd Bank'),
    BankParser(['AUBK'], 'AU Small Finance Bank'),
    BankParser(['FDRL'], 'Federal Bank'),
  ];

  static const _fallback = GenericParser();

  /// Parses [msg], or returns null when no parser recognizes it as a
  /// transaction (OTP codes, promos, personal messages, ...).
  static Transaction? parse(SmsMessage msg) {
    for (final p in _banks) {
      if (p.canParse(msg)) {
        final t = p.parse(msg);
        if (t != null) return t;
      }
    }
    return _fallback.parse(msg);
  }
}
