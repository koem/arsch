// Zu fünft: Der Arsch der Vorrunde nimmt die Mitte auf und legt 2 Karten zurück.
// Die Spiele laufen mit echten Zügen und Bots, darum dauern sie etwas.
@Timeout(Duration(minutes: 7))
library;

import 'dart:async';

import 'package:test/test.dart';

import 'support.dart';

void main() {
  late TestServer server;
  setUp(() async => server = await TestServer.start());
  tearDown(() => server.dispose());

  test('Mensch als Arsch: zurücklegen, vorher kein Legen, nur er sieht die Karten',
      () async {
    final host = await Client.create(server, 'Host');
    final guest = await Client.join(server, host.code!, 'Gast');
    for (var i = 0; i < 3; i++) {
      host.send({'type': 'addBot'});
    }
    await settle();
    host.send({'type': 'start'});
    await settle();
    final watcher = await Client.join(server, host.code!, 'Watcher');

    var humanDiscarded = false;
    var maxWatcherMoves = 0;
    final problems = <String>[];
    final done = Completer<void>();

    void act(Client c, Map<String, dynamic> s) {
      switch (s['phase']) {
        case 'discarding':
          final arsch = s['current'] as int;
          final counts = [for (final p in s['players']) p['cardCount'] as int];
          if (counts[arsch] != 8 ||
              counts.where((n) => n == 6).length != 4 ||
              s['middleCount'] != 0) {
            problems.add('Kartenzahlen beim Zurücklegen: $counts');
          }
          if (myTurn(s)) {
            if ((s['pickedUp'] as List).length != 2) problems.add('pickedUp fehlt');
            humanDiscarded = true;
            final hand = handOf(s);
            Future.delayed(const Duration(milliseconds: 30), () {
              c.send({'type': 'play', 'cards': [hand.first]}); // muss abgelehnt werden
              c.send({'type': 'discard', 'cards': hand.take(2).toList()});
            });
          } else if (s.containsKey('pickedUp')) {
            problems.add('pickedUp an Platz ${s['you']} verraten');
          }
        case 'roundOver':
          if (humanDiscarded && !done.isCompleted) done.complete();
          if (c == host) {
            Future.delayed(const Duration(milliseconds: 30),
                () => c.send({'type': 'nextRound'}));
          }
        case 'gameOver':
          if (!done.isCompleted) done.complete();
        case 'playing':
          if (myTurn(s)) {
            Future.delayed(const Duration(milliseconds: 30), () => simpleMove(c, s));
          }
      }
    }

    watcher.states.listen((s) {
      final n = (s['recent'] as List).length;
      if (n > maxWatcherMoves) maxWatcherMoves = n;
      if (s.containsKey('pickedUp')) problems.add('Zuschauer sieht pickedUp');
    });
    for (final c in [host, guest]) {
      c.states.listen((s) => act(c, s));
      act(c, c.last!);
    }
    await done.future.timeout(const Duration(minutes: 6));

    expect(problems, isEmpty);
    // Die Menschen spielen schwach und werden praktisch immer Arsch.
    expect(humanDiscarded, isTrue);
    expect({...host.errors, ...guest.errors},
        {'Zuerst legt der Arsch 2 Karten zurück in die Mitte.'});
    expect(maxWatcherMoves, greaterThan(12),
        reason: 'Zuschauer sehen den ganzen Verlauf der Runde');
  });

  test('Bot als Arsch legt selbst zurück, danach geht es normal weiter', () async {
    final solo = await Client.create(server, 'Solo');
    for (var i = 0; i < 4; i++) {
      solo.send({'type': 'addBot'});
    }
    await settle();
    solo.send({'type': 'start'});

    var botDiscards = 0;
    String? previousPhase;
    int? previousArsch;
    final done = Completer<void>();
    final problems = <String>[];
    solo.states.listen((s) {
      final phase = s['phase'] as String;
      if (previousPhase == 'discarding' && phase == 'playing' && previousArsch != s['you']) {
        botDiscards++;
        final counts = [for (final p in s['players']) p['cardCount']];
        if (!counts.every((n) => n == 6) || s['middleCount'] != 2) {
          problems.add('nach dem Zurücklegen: $counts, Mitte ${s['middleCount']}');
        }
      }
      if (phase == 'discarding') previousArsch = s['current'] as int;
      previousPhase = phase;
      if (phase == 'discarding' && myTurn(s)) {
        solo.send({'type': 'discard', 'cards': handOf(s).take(2).toList()});
      }
      // Spielt wie die Bots, damit auch mal ein Bot Arsch wird.
      if (phase == 'playing' && myTurn(s)) botLikeMove(solo, s);
      if (phase == 'roundOver') {
        if (botDiscards >= 2) {
          if (!done.isCompleted) done.complete();
        } else {
          solo.send({'type': 'nextRound'});
        }
      }
      if (phase == 'gameOver' && !done.isCompleted) done.complete();
    });
    await done.future.timeout(const Duration(minutes: 6));
    expect(problems, isEmpty);
    expect(botDiscards, greaterThan(0));
  });
}
