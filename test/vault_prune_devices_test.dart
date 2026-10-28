import 'package:bishare/features/vault/data/vault_account.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which devices the app removes by itself (owner 2026-10-28): idle for 30
/// days, or an earlier install of this phone (same name, unseen since this
/// one was added). Anything in use stays.
void main() {
  const day = 24 * 60 * 60 * 1000;
  final now = DateTime(2026, 10, 28).millisecondsSinceEpoch;

  VaultDeviceView dev(
    String id, {
    String? name,
    required int addedAt,
    int? lastSeenAt,
    bool me = false,
    bool web = false,
  }) => VaultDeviceView(
    id: id,
    name: name,
    thisDevice: me,
    pending: false,
    addedAt: addedAt,
    lastSeenAt: lastSeenAt,
    web: web,
  );

  final me = dev(
    'me',
    name: 'samsung SM-A245F',
    addedAt: now - 1 * day,
    me: true,
  );

  test('an earlier install of this phone goes', () {
    final old = dev(
      'old',
      name: 'samsung SM-A245F',
      addedAt: now - 20 * day,
      lastSeenAt: now - 2 * day,
    );
    expect(VaultAccount.leftBehind(old, me, now), isTrue);
  });

  test('a phone with the same name still in use stays', () {
    final sibling = dev(
      'sib',
      name: 'samsung SM-A245F',
      addedAt: now - 20 * day,
      lastSeenAt: now - 3600 * 1000,
    );
    expect(VaultAccount.leftBehind(sibling, me, now), isFalse);
  });

  test('a device unseen for 30 days goes, one seen last week stays', () {
    expect(
      VaultAccount.leftBehind(
        dev(
          'mac',
          name: 'Mac',
          addedAt: now - 90 * day,
          lastSeenAt: now - 31 * day,
        ),
        me,
        now,
      ),
      isTrue,
    );
    expect(
      VaultAccount.leftBehind(
        dev(
          'ipad',
          name: 'iPad',
          addedAt: now - 90 * day,
          lastSeenAt: now - 7 * day,
        ),
        me,
        now,
      ),
      isFalse,
    );
  });

  test('a browser does not remove phones by name', () {
    final browser = dev(
      'web',
      name: 'samsung SM-A245F',
      addedAt: now - 1 * day,
      me: true,
      web: true,
    );
    final old = dev(
      'old',
      name: 'samsung SM-A245F',
      addedAt: now - 20 * day,
      lastSeenAt: now - 2 * day,
    );
    expect(VaultAccount.leftBehind(old, browser, now), isFalse);
  });
}
