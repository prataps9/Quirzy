import 'package:flutter_test/flutter_test.dart';
import 'package:quirzy/auth/providers/auth_provider.dart';

void main() {
  test('a user saved at sign-in can be restored when the server is unreachable', () async {
    final stored = {
      'user_id': 'u1',
      'user_name': 'Asha',
      'user_email': 'asha@example.com',
      'user_photo_url': 'https://example.com/a.png',
    };
    final user = await AuthNotifier.cachedUser((key) async => stored[key]);
    expect(user, isNotNull);
    expect(user!.id, 'u1');
    expect(user.name, 'Asha');
    expect(user.photoUrl, 'https://example.com/a.png');
  });

  test('nothing saved means signed out', () async {
    expect(await AuthNotifier.cachedUser((key) async => null), isNull);
    expect(await AuthNotifier.cachedUser((key) async => key == 'user_id' ? '' : 'x'), isNull);
  });
}
