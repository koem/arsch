// Bedenkzeit (hier 1 s statt 24 h) und Aufräumen verlassener Räume.
@Timeout(Duration(minutes: 3))
library;

import 'package:test/test.dart';

import 'support.dart';

void main() {
  late TestServer server;
  setUp(() async => server = await TestServer.start(env: {
        'TURN_TIMEOUT': '1',
        'TURN_REMINDER': '1',
        'FINISHED_GAME': '4',
      }));
  tearDown(() => server.dispose());

  test('Zeit abgelaufen: Server zieht für Abwesende; Raum erst nach der Runde weg',
      () async {
    final host = await Client.create(server, 'Host');
    final guest = await Client.join(server, host.code!, 'Gast');
    host.send({'type': 'addBot'});
    host.send({'type': 'addBot'});
    await settle();
    final states = <Map<String, dynamic>>[];
    host.states.listen(states.add);
    host.send({'type': 'start'});
    await settle();
    final watcher = await Client.join(server, host.code!, 'W');

    // Niemand zieht – nur Bots und Zeitabläufe.
    await Future.delayed(const Duration(seconds: 12));
    final playing = states.where((s) => s['phase'] == 'playing');
    final humanTurns = playing.where((s) => !isBot(s, s['current'] as int));
    final botTurns = playing.where((s) => isBot(s, s['current'] as int));
    expect(humanTurns, isNotEmpty);
    for (final s in humanTurns) {
      expect(s['turnSecondsLeft'], lessThanOrEqualTo(1));
      expect(s['reminderSecondsBefore'], 1);
    }
    for (final s in botTurns) {
      expect(s.containsKey('turnSecondsLeft'), isFalse);
    }
    final round = (watcher.last!['recent'] as List).cast<Map>();
    final humanMoves = round.where((m) => m['seat'] == 0 || m['seat'] == 1);
    expect(humanMoves, isNotEmpty);
    expect(humanMoves.every((m) => m['timedOut'] == true), isTrue);
    final botMoves = round.where((m) => (m['seat'] as int) >= 2);
    expect(botMoves.every((m) => m['timedOut'] == false), isTrue);

    // Alle Menschen gehen mitten in der Runde: Die Runde läuft weiter und wird
    // nicht gelöscht; erst FINISHED_GAME (4 s) nach dem Rundenende.
    await host.close();
    await guest.close();
    DateTime? roundOverAt;
    DateTime? goneAt;
    String? phaseWhenGone;
    for (var i = 0; i < 240 && goneAt == null; i++) {
      await settle(500);
      final phase = watcher.last!['phase'] as String;
      if (roundOverAt == null && phase != 'playing' && phase != 'discarding') {
        roundOverAt = DateTime.now();
      }
      if (await server.roomCount() == 0) {
        goneAt = DateTime.now();
        phaseWhenGone = phase;
      }
    }
    expect(roundOverAt, isNotNull, reason: 'Runde endet von selbst');
    expect(goneAt, isNotNull);
    expect(phaseWhenGone, isNot('playing'));
    expect(goneAt!.difference(roundOverAt!).inMilliseconds, greaterThanOrEqualTo(3000));
  });
}
