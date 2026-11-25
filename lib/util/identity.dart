/// Detect the phone owner's name and number from the message corpus itself.
///
/// Banks greet you by name (`Dear Elias Tsegaye Girmaye …`) and telecom
/// messages repeatedly quote your own number, so the inbox is a reliable —
/// and fully offline — source of profile info.
library;

/// Matches `Dear <Name>` — up to 3 words, word chars separated by
/// spaces/tabs only (newlines would swallow the next sentence).
final _dearRe = RegExp(
  r'\bDear[ \t]+((?:Mr\.?\/Ms\.?[ \t]+)?[A-Z][A-Za-z]+(?:[ \t]+[A-Z][A-Za-z]+){0,2})',
);

const _notOwnerNames = {
  'Customer', 'our', 'esteemed', 'Valued', 'Sir', 'Madam', 'Cardholder',
  'Member', 'Account', 'Dear',
};

/// Most likely owner name across [binds], or null.
///
/// Groups case-insensitively, then prefers the longest variant among the
/// top-frequency candidates so "ELIAS TSEGAYE GIRMAYE" beats plain "ELIAS".
String? detectOwnerName(Iterable<String> bodies) {
  final counts = <String, int>{}; // lowercased → occurrences
  final variants = <String, String>{}; // lowercased → most common original
  final words = <String, int>{}; // lowercased → word count

  for (final body in bodies) {
    final m = _dearRe.firstMatch(body);
    if (m == null) continue;
    final name = m.group(1)!.trim();
    final parts = name.split(RegExp(r'[ \t]+'));
    if (parts.isEmpty || _notOwnerNames.contains(parts.first)) continue;
    final key = name.toLowerCase();
    counts[key] = (counts[key] ?? 0) + 1;
    variants.putIfAbsent(key, () => name);
    words[key] = parts.length;
  }

  if (counts.isEmpty) return null;
  final maxCount = counts.values.reduce((a, b) => a > b ? a : b);
  final candidates = counts.entries
      .where((e) => e.value >= maxCount * 0.5)
      .toList()
    ..sort((a, b) {
      final byWords = (words[b.key] ?? 0).compareTo(words[a.key] ?? 0);
      if (byWords != 0) return byWords;
      return b.value.compareTo(a.value);
    });
  return variants[candidates.first.key];
}

final _ownPhoneRe = RegExp(r'\b9\d{8}\b');

/// Most frequently quoted 9-digit mobile number in [bodies], or null.
String? detectOwnerPhone(Iterable<String> bodies) {
  final counts = <String, int>{};
  for (final body in bodies) {
    for (final m in _ownPhoneRe.allMatches(body)) {
      final p = m.group(0)!;
      counts[p] = (counts[p] ?? 0) + 1;
    }
  }
  if (counts.isEmpty) return null;
  final sorted = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  // Require a clear winner to avoid mistaking someone else's number.
  if (sorted.first.value < 3) return null;
  return sorted.first.key;
}
