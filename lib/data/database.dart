/// SQLite storage for parsed transactions.
library;

// sqflite also exports a `Transaction` type; hide it in favor of our model.
import 'package:sqflite/sqflite.dart' hide Transaction;

import '../models/models.dart';

class BudgetDatabase {
  BudgetDatabase._();
  static final instance = BudgetDatabase._();

  Database? _db;

  Future<Database> get _database async => _db ??= await _open();

  Future<Database> _open() async {
    final path = '${await getDatabasesPath()}/budget.db';
    return openDatabase(
      path,
      version: 2,
      onConfigure: (db) => db.execute('PRAGMA journal_mode = WAL'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE transactions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sender TEXT NOT NULL,
            sender_name TEXT,
            bank TEXT NOT NULL,
            merchant TEXT,
            amount REAL NOT NULL,
            type TEXT NOT NULL,
            currency TEXT NOT NULL DEFAULT '',
            date INTEGER NOT NULL,
            balance REAL,
            category TEXT,
            raw TEXT NOT NULL,
            dedupe TEXT NOT NULL UNIQUE
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_transactions_date ON transactions(date DESC)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
              'ALTER TABLE transactions ADD COLUMN sender_name TEXT');
        }
      },
    );
  }

  /// Inserts [t] unless the same SMS was already stored. Returns true when a
  /// new row was created.
  Future<bool> insertIfNew(Transaction t) async {
    final db = await _database;
    final existing = await db.query(
      'transactions',
      columns: ['id'],
      where: 'dedupe = ?',
      whereArgs: [t.dedupe],
      limit: 1,
    );
    if (existing.isNotEmpty) return false;
    await db.insert('transactions', t.toMap());
    return true;
  }

  Future<List<Transaction>> all({String? search, TxType? type}) async {
    final db = await _database;
    final where = <String>[];
    final args = <Object?>[];

    if (type != null) {
      where.add('type = ?');
      args.add(type == TxType.debit ? 'debit' : 'credit');
    }
    final q = search?.trim();
    if (q != null && q.isNotEmpty) {
      where.add('(merchant LIKE ? OR bank LIKE ? OR category LIKE ? OR raw LIKE ?)');
      final like = '%$q%';
      args.addAll([like, like, like, like]);
    }

    final rows = await db.query(
      'transactions',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'date DESC',
    );
    return rows.map(Transaction.fromMap).toList();
  }

  Future<void> clear() async {
    final db = await _database;
    await db.delete('transactions');
  }

  /// Distinct sender addresses that still lack a contact name.
  Future<List<String>> sendersNeedingContact() async {
    final db = await _database;
    final rows = await db.rawQuery(
        "SELECT DISTINCT sender FROM transactions "
        "WHERE sender_name IS NULL AND sender GLOB '*[0-9]*' "
        "AND sender NOT GLOB '*[A-Za-z]*'");
    return rows.map((r) => r['sender'] as String).toList();
  }

  Future<void> setSenderName(String sender, String name) async {
    final db = await _database;
    await db.update(
      'transactions',
      {'sender_name': name},
      where: 'sender = ?',
      whereArgs: [sender],
    );
  }
}
