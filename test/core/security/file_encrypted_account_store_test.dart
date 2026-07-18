import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:steam_account_companion/core/security/file_encrypted_account_store.dart';

void main() {
  late Directory tempDir;
  late FileEncryptedAccountStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sac_account_store_');
    store = FileEncryptedAccountStore(rootDirectory: tempDir);
    await store.ensureReady();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('save/read/list/delete round-trip on disk', () async {
    await store.save(
      accountId: 'steam:1',
      encryptedPayload: [1, 2, 3, 4],
    );
    await store.save(
      accountId: 'steam:2',
      encryptedPayload: [9, 8, 7],
    );

    expect(await store.listAccountIds(), containsAll(['steam:1', 'steam:2']));
    expect(await store.read('steam:1'), [1, 2, 3, 4]);

    final reopened = FileEncryptedAccountStore(rootDirectory: tempDir);
    expect(await reopened.read('steam:2'), [9, 8, 7]);
    expect(await reopened.listAccountIds(), hasLength(2));

    await reopened.delete('steam:1');
    expect(await reopened.read('steam:1'), isNull);
    expect(await reopened.listAccountIds(), ['steam:2']);
  });

  test('account ids with special characters map to safe file names', () async {
    const id = 'name:user@example.com';
    await store.save(accountId: id, encryptedPayload: [42]);
    expect(await store.read(id), [42]);

    final blobs = Directory('${tempDir.path}/blobs');
    final files = blobs.listSync().whereType<File>().toList();
    expect(files, isNotEmpty);
    expect(files.first.path.endsWith('.bin'), isTrue);
    expect(files.first.uri.pathSegments.last.contains(':'), isFalse);
  });

  test('concurrent saves keep both account ids', () async {
    await Future.wait([
      store.save(accountId: 'a', encryptedPayload: [1]),
      store.save(accountId: 'b', encryptedPayload: [2]),
      store.save(accountId: 'c', encryptedPayload: [3]),
    ]);
    final ids = await store.listAccountIds();
    expect(ids.toSet(), {'a', 'b', 'c'});
  });

  test('corrupt index is rebuilt from blobs when allowed', () async {
    await store.save(accountId: 'steam:9', encryptedPayload: [9, 9]);
    final index = File('${tempDir.path}/index.json');
    await index.writeAsString('{not-json', flush: true);

    final recovered = FileEncryptedAccountStore(
      rootDirectory: tempDir,
      rebuildIndexFromBlobsOnCorrupt: true,
    );
    final ids = await recovered.listAccountIds();
    expect(ids, ['steam:9']);
    expect(await recovered.read('steam:9'), [9, 9]);
  });

  test('corrupt index throws when rebuild disabled', () async {
    await store.save(accountId: 'steam:9', encryptedPayload: [9]);
    final index = File('${tempDir.path}/index.json');
    await index.writeAsString('{not-json', flush: true);

    final strict = FileEncryptedAccountStore(
      rootDirectory: tempDir,
      rebuildIndexFromBlobsOnCorrupt: false,
    );
    expect(
      () => strict.listAccountIds(),
      throwsA(isA<AccountStoreIntegrityException>()),
    );
  });

  test('atomic index write leaves valid JSON', () async {
    await store.save(accountId: 'x', encryptedPayload: [1]);
    final raw = await File('${tempDir.path}/index.json').readAsString();
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    expect(decoded['ids'], ['x']);
  });

  test('orphan blob after crash mid-save is recovered on reopen', () async {
    // Simulate: blob rename succeeded, index never updated.
    final survivor = FileEncryptedAccountStore(rootDirectory: tempDir);
    await survivor.ensureReady();
    await survivor.save(accountId: 'kept', encryptedPayload: [1]);

    // Write a blob the way save does, without touching index.
    const orphanId = 'orphan:new';
    final safe = base64Url.encode(utf8.encode(orphanId)).replaceAll('=', '');
    final blob = File('${tempDir.path}/blobs/$safe.bin');
    await blob.writeAsBytes([7, 7, 7], flush: true);

    // Index still only has "kept".
    final indexRaw = await File('${tempDir.path}/index.json').readAsString();
    expect(jsonDecode(indexRaw)['ids'], ['kept']);

    final recovered = FileEncryptedAccountStore(rootDirectory: tempDir);
    await recovered.ensureReady();
    final ids = await recovered.listAccountIds();
    expect(ids.toSet(), {'kept', orphanId});
    expect(await recovered.read(orphanId), [7, 7, 7]);
  });

  test('index entry without blob is dropped on reconcile', () async {
    await store.save(accountId: 'alive', encryptedPayload: [1]);
    await store.save(accountId: 'ghost', encryptedPayload: [2]);
    // Delete only ghost's blob (crash after unlink, before index update).
    final ghostSafe =
        base64Url.encode(utf8.encode('ghost')).replaceAll('=', '');
    final ghostBlob = File('${tempDir.path}/blobs/$ghostSafe.bin');
    expect(await ghostBlob.exists(), isTrue);
    await ghostBlob.delete();

    final recovered = FileEncryptedAccountStore(rootDirectory: tempDir);
    await recovered.ensureReady();
    expect(await recovered.listAccountIds(), ['alive']);
    expect(await recovered.read('ghost'), isNull);
  });
}
