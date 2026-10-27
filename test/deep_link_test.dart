import 'package:bishare/core/deeplink/deep_link.dart';
import 'package:flutter_test/flutter_test.dart';

/// The links the app claims. The old account system's `/share/<token>` and
/// `/request/<code>` pages are gone on the site and the API, so those links
/// must parse to nothing instead of opening a download that cannot work.
void main() {
  test('a transfer link, with and without its key', () {
    final plain = DeepLink.parse('https://bishare.app/transfer/AB2C3D');
    expect(
      plain,
      isA<CloudTransferLink>()
          .having((l) => l.code, 'code', 'AB2C3D')
          .having((l) => l.key, 'key', isNull),
    );
    final keyed = DeepLink.parse(
      'https://bishare.app/transfer/ab2-c3d#k=AAECAwQF',
    );
    expect(
      keyed,
      isA<CloudTransferLink>()
          .having((l) => l.code, 'code', 'AB2C3D')
          .having((l) => l.key, 'key', 'AAECAwQF'),
    );
    expect(
      DeepLink.parse('bishare.app/transfer/AB2C3D'),
      isA<CloudTransferLink>(),
    );
  });

  test('a link copied from a receive page parses, on either host', () {
    for (final link in const [
      'https://dl.bishareusercontent.com/transfer/AB2C3D#k=AAECAwQF',
      'https://get.bishare.app/transfer/AB2C3D#k=AAECAwQF',
      'dl.bishareusercontent.com/transfer/AB2C3D#k=AAECAwQF',
    ]) {
      expect(
        DeepLink.parse(link),
        isA<CloudTransferLink>().having((l) => l.key, 'key', 'AAECAwQF'),
        reason: link,
      );
    }
    expect(
      DeepLink.parse(
        'https://bishareusercontent.com.evil.example/transfer/AB2C3D',
      ),
      isNull,
    );
  });

  test('the old share and request links are not claimed', () {
    expect(DeepLink.parse('https://bishare.app/share/abcdef123456'), isNull);
    expect(DeepLink.parse('https://bishare.app/request/ABCDEF'), isNull);
    expect(DeepLink.parse('bishare.app/share/abcdef'), isNull);
    expect(DeepLink.looksLikeBiShare('https://bishare.app/share/abc'), isFalse);
  });

  test('the other schemes still parse', () {
    expect(DeepLink.parse('bishare://share'), isA<RescanSharedLink>());
    expect(
      DeepLink.parse('bishare-stream://AB2C3D#k=AAECAwQF'),
      isA<StreamReceiveLink>().having((l) => l.key, 'key', 'AAECAwQF'),
    );
    expect(
      DeepLink.parse('bishare://download?host=192.168.1.5&port=53317&token=t1'),
      isA<LocalInstantLink>().having(
        (l) => l.url.toString(),
        'url',
        'http://192.168.1.5:53317/api/v1/instant?token=t1',
      ),
    );
    expect(DeepLink.parse(''), isNull);
    expect(DeepLink.parse('https://example.com/transfer/AB2C3D'), isNull);
  });
}
