/// Core data models: raw SMS and parsed transactions.
library;

enum TxType { debit, credit }

TxType txTypeFromString(String v) => v == 'credit' ? TxType.credit : TxType.debit;

/// A raw SMS as delivered by the Android side.
class SmsMessage {
  final String address;
  final String body;
  final DateTime date;

  const SmsMessage({
    required this.address,
    required this.body,
    required this.date,
  });

  factory SmsMessage.fromMap(Map<dynamic, dynamic> m) => SmsMessage(
        address: (m['address'] ?? '') as String,
        body: (m['body'] ?? '') as String,
        date: DateTime.fromMillisecondsSinceEpoch(
            (m['date'] as num?)?.toInt() ?? 0),
      );
}

/// A parsed bank transaction, persisted in SQLite.
class Transaction {
  final int? id;
  final String sender;
  final String? senderName; // contact display name for numeric senders
  final String bank;
  final String? merchant;
  final double amount; // always positive; see [type]
  final TxType type;
  final DateTime date;
  final double? balance;
  final String currency;
  final String? category;
  final String raw;
  final bool sent; // already pushed to the sync server

  const Transaction({
    this.id,
    required this.sender,
    this.senderName,
    required this.bank,
    this.merchant,
    required this.amount,
    required this.type,
    required this.date,
    this.balance,
    this.currency = '',
    this.category,
    required this.raw,
    this.sent = false,
  });

  /// Natural key so replayed/duplicate SMS are inserted only once.
  String get dedupe =>
      '$sender|${date.millisecondsSinceEpoch}|$amount|$raw';

  Transaction copyWith({String? bank, bool? sent}) => Transaction(
        id: id,
        sender: sender,
        senderName: senderName,
        bank: bank ?? this.bank,
        merchant: merchant,
        amount: amount,
        type: type,
        date: date,
        balance: balance,
        currency: currency,
        category: category,
        raw: raw,
        sent: sent ?? this.sent,
      );

  Map<String, Object?> toMap() => {
        'sender': sender,
        'sender_name': senderName,
        'bank': bank,
        'merchant': merchant,
        'amount': amount,
        'type': type == TxType.debit ? 'debit' : 'credit',
        'currency': currency,
        'date': date.millisecondsSinceEpoch,
        'balance': balance,
        'category': category,
        'raw': raw,
        'sent': sent ? 1 : 0,
        'dedupe': dedupe,
      };

  factory Transaction.fromMap(Map<String, Object?> m) => Transaction(
        id: m['id'] as int?,
        sender: m['sender'] as String,
        senderName: m['sender_name'] as String?,
        bank: m['bank'] as String,
        merchant: m['merchant'] as String?,
        amount: (m['amount'] as num).toDouble(),
        type: txTypeFromString(m['type'] as String),
        date: DateTime.fromMillisecondsSinceEpoch((m['date'] as num).toInt()),
        balance: (m['balance'] as num?)?.toDouble(),
        currency: (m['currency'] as String?) ?? '',
        category: m['category'] as String?,
        raw: m['raw'] as String,
        sent: ((m['sent'] as num?) ?? 0) != 0,
      );
}
