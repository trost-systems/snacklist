import 'package:family_groceries/list/catalog/pg.dart';
import 'package:flutter_test/flutter_test.dart';

// The answers of the local stack (PostgreSQL 17, ICU en-US) to the same
// questions.
void main() {
  test('similarity is pg_trgm similarity', () {
    for (final (a, b, sim) in [
      ('milch', 'milch', 1.0),
      ('milch', 'milchreis', 0.454545),
      ('mi', 'milch', 0.285714),
      ('a', 'ab', 0.25),
      ('1,5 % milch', 'milch 1,5 %', 1.0),
      ('rote be', 'rote bete', 0.7),
      ('hafermlich', 'hafermilch', 0.466667),
      ('e', 'é', 0.0),
      ('x y z', 'xyz', 0.111111),
      ('mül', 'muell', 0.111111),
      ('', 'a', 0.0),
      ('12', '123', 0.4),
      ('café', 'cafe', 0.428571),
      ('ab-cd', 'ab cd', 1.0),
      ('aaa', 'aaaa', 1.0),
    ]) {
      expect(
        similarity(trigrams(a), trigrams(b)),
        closeTo(sim, 1e-6),
        reason: '$a / $b',
      );
    }
  });

  test('withinEdits is levenshtein_less_equal(a, b, 2) <= 2', () {
    for (final (a, b, distance) in [
      ('milch', 'milchreis', 3),
      ('hafermlich', 'hafermilch', 2),
      ('aepfel', 'apfel', 1),
      ('mül', 'muell', 3),
      ('ab-cd', 'ab cd', 1),
      ('rote be', 'rote bete', 2),
    ]) {
      expect(withinEdits(a, b, 2), distance <= 2, reason: '$a / $b');
      expect(withinEdits(a, b, 1), distance <= 1, reason: '$a / $b');
    }
  });

  test('collate sorts as order by does', () {
    const sorted = [
      '_x', '1,5 %', 'a b', 'A b', 'a-b', 'ab', 'Ab', 'apfel', 'Apfel', //
      'äpfel', 'Äpfel', 'äz', 'bio', 'Bio', 'é', 'groesse', 'Größe 4', 'ss',
      'ß', 'st', 'Zwiebel', 'zz',
    ];
    expect([...sorted.reversed]..sort(collate), sorted);
    expect(collate(null, 'a'), greaterThan(0));
  });

  test('initcap and capText', () {
    expect(initcap('rote bete'), 'Rote Bete');
    expect(initcap('äpfel'), 'Äpfel');
    expect(capText('Milch', 10), 'Milch');
    expect(capText('Milch, Butter Eier', 14), 'Milch, Butter');
    expect(capText('Milchbutter', 5), 'Milch');
    expect(capText(null, 5), isNull);
  });
}
