import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:steam_account_companion/app/app_services.dart';
import 'package:steam_account_companion/core/network/steam_time_client.dart';

void main() {
  test('concurrent time sync shares request and upgrades listener notification',
      () async {
    final timeClient = _BlockingSteamTimeClient();
    final services = await AppServices.createInMemory(
      timeClient: timeClient,
      syncServerTimeOnStart: false,
    );
    addTearDown(services.dispose);

    var notifications = 0;
    services.addListener(() => notifications++);

    final silent = services.syncServerTime(notify: false);
    final visible = services.syncServerTime();

    expect(timeClient.callCount, 1);
    expect(services.timeSyncInProgress, isTrue);
    expect(notifications, 1);

    timeClient.complete();
    final results = await Future.wait([silent, visible]);

    expect(results, everyElement(isNotNull));
    expect(timeClient.callCount, 1);
    expect(services.timeSyncInProgress, isFalse);
    expect(services.hasSyncedServerTime, isTrue);
    expect(notifications, 2);
  });
}

class _BlockingSteamTimeClient implements SteamTimeClient {
  final _response = Completer<int>();
  var callCount = 0;

  @override
  Future<int> queryServerTimeSeconds() {
    callCount++;
    return _response.future;
  }

  void complete() {
    _response.complete(DateTime.now().millisecondsSinceEpoch ~/ 1000);
  }
}
