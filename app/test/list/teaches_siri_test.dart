import 'package:family_groceries/list/list_scope.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const home = Household(id: 'home', name: 'Zuhause', isDefault: true);
  const club = Household(id: 'club', name: 'Sommerfest');
  const session = InHousehold('peter', club, [home, club]);

  test("Siri learns item names from the default household's list only", () {
    expect(teachesSiri(session, 'home'), isTrue);
    expect(teachesSiri(session, 'club'), isFalse);
    expect(teachesSiri(const NeedsHousehold('peter'), 'home'), isFalse);
  });
}
