// Spielstände überstehen Neustarts des Servers.
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support.dart';

String _j(Object? o) => jsonEncode(o);

void main() {
  late TestServer server;
  setUp(() async => server = await TestServer.start(env: {'TURN_TIMEOUT': '60'}));
  tearDown(() => server.dispose());

  test('Neustart (SIGTERM und kill -9): alles wie vorher, Bedenkzeit läuft weiter',
      () async {
    final host = await Client.create(server, 'Host');
    final guest = await Client.join(server, host.code!, 'Gast');
    host.send({'type': 'addBot'});
    host.send({'type': 'addBot'});
    await settle();
    host.send({'type': 'start'});
    await settle();
    final watcher = await Client.join(server, host.code!, 'W');

    // Ein paar Züge spielen.
    final subs = [for (final c in [host, guest]) autoPlay(c, simpleMove)];
    await Future.delayed(const Duration(seconds: 6));
    for (final s in subs) {
      await s.cancel();
    }
    // Warten, bis ein Mensch dran ist (dann läuft seine Bedenkzeit).
    await host.waitFor((s) => s['phase'] == 'playing' && !isBot(s, s['current'] as int));
    await Future.delayed(const Duration(seconds: 3));
    final before = host.last!;
    final beforeGuest = guest.last!;
    final leftBefore = before['turnSecondsLeft'] as int;

    await server.restart();
    expect(File('${server.dataDir.path}/rooms.json').existsSync(), isTrue);
    expect(server.output.toString(), contains('1 gespeicherte Räume geladen.'));

    final host2 = await Client.connect(
        server, {'type': 'rejoin', 'code': host.code, 'token': host.token});
    final guest2 = await Client.connect(
        server, {'type': 'rejoin', 'code': guest.code, 'token': guest.token});
    final watcher2 = await Client.connect(
        server, {'type': 'rejoin', 'code': watcher.code, 'token': watcher.token});
    expect(host2.errors, isEmpty);
    expect(guest2.errors, isEmpty);
    expect(watcher2.errors, isEmpty);
    expect(watcher2.last!['spectator'], isTrue);

    final after = host2.last!;
    expect(_j(after['hand']), _j(before['hand']));
    expect(_j(guest2.last!['hand']), _j(beforeGuest['hand']));
    for (final key in [
      'round', 'current', 'pile', 'previousPile', 'middleCount', 'phase', 'recent'
    ]) {
      expect(_j(after[key]), _j(before[key]), reason: key);
    }
    List summary(Map s) => [
          for (final p in s['players'] as List)
            [p['name'], p['cardCount'], p['score'], p['bot'], p['swaps']]
        ];
    expect(_j(summary(after)), _j(summary(before)));
    final leftAfter = after['turnSecondsLeft'] as int;
    expect(leftAfter, lessThan(leftBefore), reason: 'Uhr läuft weiter');
    expect(leftAfter, greaterThan(leftBefore - 20), reason: 'nicht neu gestartet');

    // Nach dem Neustart wird weitergespielt.
    final mover = myTurn(after) ? host2 : guest2;
    simpleMove(mover, mover.last!);
    await settle(800);
    expect(mover.errors, isEmpty);
    expect(_j(host2.last!['recent']) != _j(after['recent']) ||
        host2.last!['current'] != after['current'], isTrue);

    // Hart abschießen: der letzte (verzögerte) Speicherstand reicht.
    await settle(1000);
    final snapshot = host2.last!;
    await server.restart(signal: ProcessSignal.sigkill);
    final host3 = await Client.connect(
        server, {'type': 'rejoin', 'code': host.code, 'token': host.token});
    expect(host3.errors, isEmpty);
    expect(_j(host3.last!['hand']), _j(snapshot['hand']));
    expect(host3.last!['round'], snapshot['round']);
  });

  test('Kaputte Spielstand-Datei wird beiseitegelegt', () async {
    await server.stop();
    File('${server.dataDir.path}/rooms.json').writeAsStringSync('{kaputt');
    await server.restart();
    expect(await server.roomCount(), 0);
    expect(
        server.dataDir.listSync().map((f) => f.path.split('/').last),
        contains(startsWith('rooms.json.broken-')));
  });
}
