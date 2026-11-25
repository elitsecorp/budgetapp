import 'package:budget_app/util/identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('detectOwnerName', () {
    test('picks the fullest name across greeting variants', () {
      final name = detectOwnerName([
        'Dear Elias Tsegaye Girmaye You have successfully transferred '
            'ETB 8,700.00 from account 1********8521.',
        'Dear ELIAS TSEGAYE GIRMAYE, you have successfully transferred '
            'ETB 450.00.',
        'Dear Elias, your account 2*****68 was debited with ETB 3.01.',
        'Dear Customer, Your airtime top-up has given you 2 coins.',
        'Dear customer, payment of ETB 8000 has been received.',
      ]);
      expect(name, 'Elias Tsegaye Girmaye');
    });

    test('returns null when only generic greetings exist', () {
      expect(
        detectOwnerName([
          'Dear Customer, your balance is insufficient.',
          'Dear customer, You have finished internet plan.',
        ]),
        isNull,
      );
    });
  });

  group('detectOwnerPhone', () {
    test('picks the number quoted repeatedly in messages', () {
      final phone = detectOwnerPhone([
        'Your service number 927709161 will expire after 7 days.',
        'Package 18GB purchase made for 927709161 on 25/11/2026.',
        'Recharge your account 927709161 before the due date.',
        'Call 0935014609 for support.',
      ]);
      expect(phone, '927709161');
    });

    test('returns null when no number repeats', () {
      expect(
        detectOwnerPhone([
          'Contact 911103314 for assistance.',
          'Call 943076616 now.',
        ]),
        isNull,
      );
    });
  });
}
