/// Turns a parsed transaction into a human "why did I spend this" reason
/// plus a matching icon — used by the detail screen and transaction list.
library;

import 'package:material_ui/material_ui.dart';

import '../models/models.dart';

/// Most-specific rules first; generic payment terms last.
const _reasonRules = <(List<String>, String)>[
  (['swiggy', 'zomato', 'restaurant', 'cafe', 'coffee', 'mcdonald', 'kfc',
    'dominos', 'pizza', 'biryani', 'eatery', 'dhaba', 'food'],
    'Food order or dining out'),
  (['bigbasket', 'blinkit', 'grofers', 'dmart', 'grocery', 'kirana',
    'supermarket', 'vegetables'],
    'Grocery shopping'),
  (['internet', 'wifi', 'broadband', 'fiber', 'fibre', 'airtel', 'jio',
    'vodafone', 'bsnl', 'recharge', 'postpaid', 'prepaid', 'mobile',
    'hathway', 'data pack'],
    'Internet or mobile bill'),
  (['electricity', 'water bill', 'gas bill', 'lpg', 'utility'],
    'Household utility bill'),
  (['netflix', 'spotify', 'hotstar', 'prime video', 'youtube premium',
    'subscription', 'membership'],
    'Subscription service'),
  (['petrol', 'fuel', 'uber', 'ola', 'rapido', 'metro', 'fastag', 'toll',
    'parking', 'taxi', 'irctc'],
    'Transport or fuel'),
  (['amazon', 'flipkart', 'myntra', 'ajio', 'meesho', 'shopping', 'mall',
    'ikea', 'zara', 'nike'],
    'Shopping'),
  (['pharmacy', 'hospital', 'medical', 'apollo', 'clinic', 'doctor',
    'medicine', '1mg', 'pharmeasy'],
    'Health or medical expense'),
  (['hotel', 'flight', 'oyo', 'makemytrip', 'goibibo', 'booking.com'],
    'Travel booking'),
  (['salary', 'payroll'], 'Salary or income'),
  (['upi', 'imps', 'neft', 'rtgs', 'transfer', 'sent to'], 'Money transfer'),
];

/// Best guess at why the money moved, e.g.
/// "Food order or dining out" for a SWIGGY debit.
String spendReason(Transaction t) {
  final hay = '${t.merchant ?? ''} ${t.raw}'.toLowerCase();
  for (final (words, phrase) in _reasonRules) {
    if (words.any(hay.contains)) return phrase;
  }
  if (t.type == TxType.credit) return 'Money received';
  final category = t.category;
  if (category == null || category == 'Other') return 'Purchase';
  return 'Spent on $category';
}

/// Icon matching the transaction's category (shared by list + detail).
IconData iconForCategory(String? category) {
  switch (category) {
    case 'Food & Dining':
      return Icons.restaurant;
    case 'Groceries':
      return Icons.local_grocery_store;
    case 'Shopping':
      return Icons.shopping_bag;
    case 'Transport':
      return Icons.directions_car;
    case 'Entertainment':
      return Icons.movie;
    case 'Health':
      return Icons.local_hospital;
    case 'Bills & Utilities':
      return Icons.receipt_long;
    case 'Internet & Phone':
      return Icons.wifi;
    case 'Travel':
      return Icons.flight;
    case 'Salary & Income':
      return Icons.account_balance_wallet;
    case 'Money Transfer':
      return Icons.swap_horiz;
    case 'Family Support':
      return Icons.family_restroom;
    case 'Loan':
      return Icons.account_balance;
    default:
      return Icons.payments_outlined;
  }
}
