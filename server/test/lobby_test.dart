@Timeout(Duration(minutes: 3))
library;

import 'package:test/test.dart';

import 'support.dart';

void main() {
  late TestServer server;
  setUp(() async => server = await TestServer.start());
  tearDown(() => server.dispose());

  test('Bots: hinzufügen, Platz machen, nur Gastgeber, Runde spielen', () async {
    final host = await Client.create(server, 'Host');
    for (var i = 0; i < 4; i++) {
      host.send({'type': 'addBot'});
    }
    await settle();
    expect(host.names, ['Host', 'Bot 1', 'Bot 2', 'Bot 3', 'Bot 4']);

    host.send({'type': 'addBot'});
    await settle();
    expect(host.errors, contains('Der Raum ist voll.'));

    // Ein Mensch kommt dazu: ein Bot macht Platz, Menschen sitzen vor Bots.
    final guest = await Client.join(server, host.code!, 'Gast');
    await settle();
    expect(host.names, ['Host', 'Gast', 'Bot 1', 'Bot 2', 'Bot 3']);
    expect(host.last!['players'][1]['bot'], isFalse);
    expect(host.last!['players'][2]['bot'], isTrue);

    guest.send({'type': 'addBot'});
    await settle();
    expect(guest.errors, ['Nur der Gastgeber kann das tun.']);

    host.send({'type': 'removeBot', 'seat': 1});
    await settle();
    expect(host.errors.last, 'Dieser Platz ist kein Bot.');
    host.send({'type': 'removeBot', 'seat': 4});
    await settle();
    expect(host.names, hasLength(4));

    host.send({'type': 'start'});
    await host.waitFor((s) => s['phase'] == 'playing');
    var sawBotMove = false;
    final subs = [
      for (final c in [host, guest]) autoPlay(c, simpleMove),
      host.states.listen((s) {
        for (final m in s['recent'] as List) {
          if (isBot(s, m['seat'] as int)) sawBotMove = true;
          expect(m['seat'], isNot(s['you']), reason: 'eigene Züge nicht im Verlauf');
        }
      }),
    ];
    final end = await host.waitFor((s) => s['phase'] != 'playing',
        timeout: const Duration(minutes: 2));
    for (final s in subs) {
      await s.cancel();
    }
    expect(end['phase'], anyOf('roundOver', 'gameOver'));
    expect(sawBotMove, isTrue);
    final players = (end['players'] as List).cast<Map>();
    final sumScores = players.map((p) => p['score'] as int).reduce((a, b) => a + b);
    final sumSwaps = players.map((p) => p['swaps'] as int).reduce((a, b) => a + b);
    expect(sumScores, sumSwaps, reason: 'jeder Swap gibt einen Punkt extra');
    expect(guest.errors, hasLength(1));
  });

  test('Zuschauer: voller Tisch, laufendes Spiel, keine Aktionen', () async {
    final host = await Client.create(server, 'Host');
    final code = host.code!;
    final guests = [for (var i = 1; i <= 4; i++) await Client.join(server, code, 'G$i')];

    // Sechster Mensch in der Lobby: Zuschauer, rückt nach, wenn Platz frei wird.
    final extra = await Client.join(server, code, 'Extra');
    expect(extra.last!['spectator'], isTrue);
    expect(extra.last!['you'], -1);
    expect(extra.errors, isEmpty);
    expect(host.last!['spectators'], 1);
    guests[3].send({'type': 'leave'});
    await settle();
    expect(extra.last!['spectator'], isFalse);
    expect(extra.names, contains('Extra'));

    guests[2].send({'type': 'leave'});
    await settle();
    host.send({'type': 'addBot'});
    await settle();
    host.send({'type': 'start'});
    await host.waitFor((s) => s['phase'] == 'playing');

    // Beitreten während des Spiels: zuschauen, ohne Handkarten.
    final watcher = await Client.join(server, code, 'Watcher');
    final w = watcher.last!;
    expect(w['spectator'], isTrue);
    expect(w['hand'], isEmpty);
    expect([for (final p in w['players']) p['cardCount']], everyElement(6));
    watcher.send({'type': 'pass'});
    watcher.send({'type': 'nextRound'});
    await settle();
    expect(watcher.errors, ['Du schaust nur zu.', 'Du schaust nur zu.']);
  });
}
