// Copied into the patched checkout's test/kimono/ by checks/mobile.sh.
// Lives in repatches (not in a patch) so a patch repair can't weaken it.
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/data/db/main/database.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/domain/services/store.service.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/infrastructure/repositories/store.repository.dart';
import 'package:immich_mobile/kimono/kimono_connect.dart';

void main() {
  setUpAll(() async {
    final db = Drift(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
    await StoreService.init(storeRepository: StoreRepository(db), listenUpdates: false);
  });

  setUp(() async {
    await Store.delete(StoreKey.serverUrl);
    KimonoConnect.signedOut = false;
  });

  test('no address until a connect link arrives', () {
    expect(KimonoConnect.server, isNull);
  });

  test('a connect link saves the origin, wakes the sign-in screen and clears a sign-out', () async {
    final before = KimonoConnect.requests.value;
    KimonoConnect.signedOut = true;
    final ok = await KimonoConnect.accept(Uri.parse('kimono-photos://connect?server=https://photos.example.com/some/path?x=1'));
    expect(ok, isTrue);
    expect(KimonoConnect.server, 'https://photos.example.com');
    expect(KimonoConnect.requests.value, before + 1);
    expect(KimonoConnect.signedOut, isFalse);
  });

  test('links without a usable https address are ignored', () async {
    for (final link in [
      'kimono-photos://connect',
      'kimono-photos://connect?server=',
      'kimono-photos://connect?server=ftp://photos.example.com',
      'kimono-photos://connect?server=javascript:alert(1)',
      'kimono-photos://connect?server=https://',
    ]) {
      expect(await KimonoConnect.accept(Uri.parse(link)), isFalse, reason: link);
    }
    expect(KimonoConnect.server, isNull);
  });

  test('only kimono-photos://connect is a connect link', () {
    expect(KimonoConnect.isConnectLink(Uri.parse('kimono-photos://connect?server=https://a.example')), isTrue);
    expect(KimonoConnect.isConnectLink(Uri.parse('kimono-photos://asset?id=1')), isFalse);
    expect(KimonoConnect.isConnectLink(Uri.parse('immich://connect?server=https://a.example')), isFalse);
  });
}
