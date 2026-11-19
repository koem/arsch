import 'dart:convert';
import 'dart:math';

import 'package:arsch_shared/arsch_shared.dart';
import 'package:test/test.dart';

/// Mit dem sortierten Blatt und 4 Spielern bekommt Platz 0 alle Karo-Karten,
/// Platz 1 alle Herz-Karten usw. Jeder hat also jeden Wert genau einmal.
ArschGame sortedGame4() => ArschGame(4)..startRound(deck: fullDeck());

PlayingCard c(Rank r, Suit s) => PlayingCard(r, s);

void main() {
  test('Austeilen zu fünft: 6 Karten pro Spieler, 2 in der Mitte', () {
    final g = ArschGame(5)..startRound();
    expect(g.hands.every((h) => h.length == 6), isTrue);
    expect(g.middle.length, 2);
  });

  test('Austeilen zu viert: 8 Karten pro Spieler, keine in der Mitte', () {
    final g = ArschGame(4)..startRound();
    expect(g.hands.every((h) => h.length == 8), isTrue);
    expect(g.middle, isEmpty);
  });

  test('Nur 4 oder 5 Spieler erlaubt', () {
    expect(() => ArschGame(3), throwsArgumentError);
    expect(() => ArschGame(6), throwsArgumentError);
  });

  test('Wer die niedrigste Karte hat, fängt an', () {
    final g = sortedGame4();
    expect(g.currentPlayer, 0); // Karo 7
  });

  test('Man muss höher legen, gleich viele Karten', () {
    final g = sortedGame4();
    g.play(0, [c(Rank.acht, Suit.karo)]);
    expect(g.currentPlayer, 1);
    expect(() => g.play(1, [c(Rank.acht, Suit.herz)]),
        throwsA(isA<GameRuleException>()));
    expect(() => g.play(1, [c(Rank.sieben, Suit.herz)]),
        throwsA(isA<GameRuleException>()));
    g.play(1, [c(Rank.neun, Suit.herz)]);
    expect(g.currentPlayer, 2);
  });

  test('Fremde Karten und falscher Spieler werden abgelehnt', () {
    final g = sortedGame4();
    expect(() => g.play(0, [c(Rank.acht, Suit.herz)]),
        throwsA(isA<GameRuleException>()));
    expect(() => g.play(1, [c(Rank.acht, Suit.herz)]),
        throwsA(isA<GameRuleException>()));
  });

  test('Wer ausspielt, darf nicht schieben', () {
    final g = sortedGame4();
    expect(() => g.pass(0), throwsA(isA<GameRuleException>()));
  });

  test('Schieben alle anderen, spielt der letzte Leger neu aus', () {
    final g = sortedGame4();
    g.play(0, [c(Rank.sieben, Suit.karo)]);
    g.play(1, [c(Rank.acht, Suit.herz)]);
    g.pass(2);
    g.pass(3);
    expect(g.pile, isNotEmpty);
    g.pass(0);
    expect(g.pile, isEmpty);
    expect(g.currentPlayer, 1);
  });

  test('Asse beenden den Stich sofort', () {
    final g = sortedGame4();
    g.play(0, [c(Rank.ass, Suit.karo)]);
    expect(g.pile, isEmpty);
    expect(g.currentPlayer, 0);
  });

  test('Komplette Runde: Punkte und Arsch beginnt die nächste Runde', () {
    final g = sortedGame4();
    while (g.phase == GamePhase.playing) {
      final seat = g.currentPlayer;
      final hand = g.hands[seat];
      final playable =
          hand.where((card) => validatePlay([card], g.pile) == null);
      if (playable.isEmpty) {
        g.pass(seat);
      } else {
        g.play(seat, [playable.first]);
      }
    }
    expect(g.finishOrder.toSet().length, 4);
    expect(g.scores.reduce((a, b) => a + b), 0);
    expect(List.of(g.scores)..sort(), [-2, -1, 1, 2]);
    expect(g.scores[g.finishOrder.first], 2);
    expect(g.scores[g.finishOrder.last], -2);

    final arsch = g.finishOrder.last;
    g.startRound();
    expect(g.currentPlayer, arsch);
    expect(g.roundNumber, 2);
  });

  test('Titel und Punkte', () {
    expect(titleFor(2, 5), 'Mitte');
    expect(titleFor(2, 4), 'Vize-Arsch');
    expect(pointsFor(4, 5), -2);
    expect(pointsFor(3, 4), -2);
  });

  test('Zugprotokoll: Züge seit dem eigenen letzten Zug', () {
    final g = sortedGame4();
    expect(g.movesSince(0), isEmpty);
    g.play(0, [c(Rank.sieben, Suit.karo)]);
    g.play(1, [c(Rank.acht, Suit.herz)]);
    g.pass(2);
    // Seat 0 sieht alles nach seinem eigenen Zug.
    expect([for (final a in g.movesSince(0)) a.seat], [1, 2]);
    expect(g.movesSince(0).last.isPass, isTrue);
    // Wer noch nicht dran war, sieht alles seit Rundenbeginn.
    expect(g.movesSince(3).length, 3);
    g.pass(3);
    g.pass(0); // Stich vorbei, seat 1 spielt neu aus
    expect(g.log.last.endsTrick, isTrue);
    expect([for (final a in g.movesSince(1)) a.seat], [2, 3, 0]);
    expect(g.movesSince(1, max: 2).length, 2);
    g.play(1, [c(Rank.neun, Suit.herz)]);
    g.play(2, [c(Rank.ass, Suit.pik)]); // Ass beendet den Stich
    expect(g.log.last.endsTrick, isTrue);
  });

  test('Neue Runde leert das Zugprotokoll', () {
    final g = ArschGame(4, random: Random(1))..startRound();
    while (g.phase == GamePhase.playing) {
      final s = g.currentPlayer;
      final m = botMove(g.hands[s], g.pile);
      m.isEmpty ? g.pass(s) : g.play(s, m);
    }
    expect(g.log, isNotEmpty);
    g.startRound();
    expect(g.log, isEmpty);
  });

  test('Bot: kleinste erlaubte Kombination oder schieben', () {
    final hand = [
      c(Rank.sieben, Suit.herz),
      c(Rank.neun, Suit.karo),
      c(Rank.neun, Suit.pik),
      c(Rank.dame, Suit.kreuz),
      c(Rank.ass, Suit.herz),
    ];
    // Ausspielen: alle Karten des niedrigsten Werts.
    expect(botMove(hand, []), [c(Rank.sieben, Suit.herz)]);
    expect(botMove(hand.sublist(1), []).length, 2);
    // Eine Karte: kleinste höhere.
    expect(botMove(hand, [c(Rank.acht, Suit.karo)]), [c(Rank.neun, Suit.karo)]);
    // Zwei Karten: nur die Neunen passen auf zwei Achten.
    expect(botMove(hand, [c(Rank.acht, Suit.karo), c(Rank.acht, Suit.herz)]).length, 2);
    // Nichts Höheres zu zweit: schieben.
    expect(botMove(hand, [c(Rank.neun, Suit.herz), c(Rank.neun, Suit.kreuz)]), isEmpty);
  });

  test('Nur Bots: 200 komplette Spiele ohne Regelverstoß', () {
    for (var seed = 0; seed < 200; seed++) {
      final g = ArschGame(4 + seed % 2, random: Random(seed));
      var moves = 0;
      while (g.phase != GamePhase.gameOver) {
        g.startRound();
        if (g.phase == GamePhase.discarding) {
          final s = g.currentPlayer;
          g.discard(s, botDiscard(g.hands[s]));
        }
        while (g.phase == GamePhase.playing) {
          final s = g.currentPlayer;
          final m = botMove(g.hands[s], g.pile);
          if (m.isEmpty) {
            g.pass(s);
          } else {
            expect(validatePlay(m, g.pile), isNull);
            g.play(s, m);
          }
          expect(++moves, lessThan(100000));
        }
      }
    }
  });

  /// Spielt die laufende Runde mit Bot-Zügen zu Ende.
  void playOut(ArschGame g) {
    while (g.phase == GamePhase.playing) {
      final s = g.currentPlayer;
      final m = botMove(g.hands[s], g.pile);
      m.isEmpty ? g.pass(s) : g.play(s, m);
    }
  }

  test('Zu fünft: Arsch nimmt die Mitte auf und legt 2 Karten zurück', () {
    final g = ArschGame(5, random: Random(7))..startRound();
    expect(g.phase, GamePhase.playing, reason: 'Runde 1: kein Tausch');
    final firstMiddle = List.of(g.middle);
    playOut(g);
    final arsch = g.finishOrder.last;
    g.startRound();
    final middle = List.of(g.middle);
    expect(middle, isEmpty);
    expect(g.phase, GamePhase.discarding);
    expect(g.currentPlayer, arsch);
    expect(g.hands[arsch].length, 8);
    expect(g.pickedUp.length, 2);
    expect(g.hands[arsch], containsAll(g.pickedUp));
    for (var s = 0; s < 5; s++) {
      if (s != arsch) expect(g.hands[s].length, 6);
    }
    expect(firstMiddle.length, 2);

    // Vor dem Zurücklegen darf niemand legen oder schieben.
    final other = (arsch + 1) % 5;
    expect(() => g.play(arsch, [g.hands[arsch].first]),
        throwsA(isA<GameRuleException>()));
    expect(() => g.discard(other, g.hands[other].take(2).toList()),
        throwsA(isA<GameRuleException>()));
    expect(() => g.discard(arsch, [g.hands[arsch].first]),
        throwsA(isA<GameRuleException>()));
    expect(() => g.discard(arsch, [g.hands[arsch].first, g.hands[arsch].first]),
        throwsA(isA<GameRuleException>()));
    expect(() => g.discard(arsch, [g.hands[arsch].first, g.hands[other].first]),
        throwsA(isA<GameRuleException>()));
    expect(() => g.startRound(), throwsA(isA<GameRuleException>()));

    // Er darf auch die gerade aufgenommenen Karten zurücklegen.
    final back = g.pickedUp;
    g.discard(arsch, back);
    expect(g.phase, GamePhase.playing);
    expect(g.middle, back..sort());
    expect(g.pickedUp, isEmpty);
    expect([for (final h in g.hands) h.length], everyElement(6));
    expect(g.currentPlayer, arsch);
    expect(() => g.discard(arsch, g.hands[arsch].take(2).toList()),
        throwsA(isA<GameRuleException>()));
    playOut(g);
    expect(g.phase, isNot(GamePhase.playing));
  });

  test('Zu viert gibt es keine Mitte und nichts zurückzulegen', () {
    final g = ArschGame(4, random: Random(3))..startRound();
    playOut(g);
    g.startRound();
    expect(g.phase, GamePhase.playing);
    expect(g.middle, isEmpty);
  });

  test('Bot legt seine zwei niedrigsten Karten zurück', () {
    final hand = [
      c(Rank.ass, Suit.herz),
      c(Rank.acht, Suit.kreuz),
      c(Rank.sieben, Suit.pik),
      c(Rank.dame, Suit.karo),
    ];
    expect(botDiscard(hand), [c(Rank.sieben, Suit.pik), c(Rank.acht, Suit.kreuz)]);
  });

  test('Zuschauer (Platz -1) sehen die ganze Runde', () {
    final g = ArschGame(4, random: Random(5))..startRound();
    playOut(g);
    expect(g.movesSince(-1, max: null).length, g.log.length);
    expect(g.log.length, greaterThan(12));
  });

  test('Zeit abgelaufen: schieben, beim Ausspielen niedrigste Karte legen', () {
    final g = sortedGame4();
    // Seat 0 spielt aus und kann nicht schieben: niedrigste Karte.
    g.timeoutMove(0);
    expect(g.pile, [c(Rank.sieben, Suit.karo)]);
    expect(g.log.last.timedOut, isTrue);
    // Seat 1 muss bedienen: Zeitablauf = schieben.
    g.timeoutMove(1);
    expect(g.log.last.isPass, isTrue);
    expect(g.log.last.timedOut, isTrue);
    expect(g.currentPlayer, 2);
    // Normale Züge sind nicht markiert; fremder Platz wird abgelehnt.
    g.pass(2);
    expect(g.log.last.timedOut, isFalse);
    expect(() => g.timeoutMove(0), throwsA(isA<GameRuleException>()));
  });

  test('Zeit abgelaufen beim Zurücklegen: die zwei niedrigsten gehen zurück', () {
    final g = ArschGame(5, random: Random(7))..startRound();
    playOut(g);
    final arsch = g.finishOrder.last;
    g.startRound();
    final lowest = botDiscard(g.hands[arsch]);
    g.timeoutMove(arsch);
    expect(g.phase, GamePhase.playing);
    expect(g.middle, lowest);
  });

  test('Speichern und Laden: der Spielstand läuft identisch weiter', () {
    // Zu fünft, mehrere Runden (auch während des Zurücklegens) und mitten im
    // Stich speichern; das geladene Spiel muss sich genauso verhalten.
    for (var seed = 0; seed < 30; seed++) {
      var g = ArschGame(5, random: Random(seed))..startRound();
      var steps = 0;
      while (g.phase != GamePhase.gameOver && steps < 400) {
        // Nach jedem Schritt speichern + laden.
        final json = jsonEncode(g.toJson());
        final copy = ArschGame.fromJson(
            jsonDecode(json) as Map<String, dynamic>,
            random: Random(seed));
        expect(jsonEncode(copy.toJson()), json);
        g = copy;
        steps++;
        final s = g.currentPlayer;
        switch (g.phase) {
          case GamePhase.discarding:
            g.discard(s, botDiscard(g.hands[s]));
          case GamePhase.playing:
            final m = botMove(g.hands[s], g.pile);
            m.isEmpty ? g.pass(s) : g.play(s, m);
          case GamePhase.roundOver:
            g.startRound();
          case GamePhase.gameOver:
            break;
        }
      }
      expect(steps, greaterThan(20));
    }
  });

  /// Mischt so, dass Platz s genau hands[s] bekommt (reihum austeilen).
  List<PlayingCard> deckFor(List<List<PlayingCard>> hands) {
    final pool = fullDeck()
      ..removeWhere((c) => hands.any((h) => h.contains(c)));
    final filled = [
      for (final h in hands) [...h, for (var i = h.length; i < 8; i++) pool.removeAt(0)],
    ];
    return [for (var i = 0; i < 32; i++) filled[i % 4][i ~/ 4]];
  }

  test('Swap: alle Karten ohne Unterbrechung gelegt (+1, gezählt)', () {
    final g = sortedGame4();
    // Seat 0 (alle Karo) spielt aus, die anderen schieben immer.
    while (g.hands[0].isNotEmpty) {
      if (g.currentPlayer == 0) {
        g.play(0, [g.hands[0].first]);
      } else {
        g.pass(g.currentPlayer);
      }
    }
    expect(g.swapsThisRound, {0: 1});
    playOut(g);
    expect(g.finishOrder.first, 0);
    expect(g.roundPoints[0], 3);
    expect(g.scores[0], 3);
    expect(g.swapCounts, [1, 0, 0, 0]);
  });

  test('Kein Swap, wenn zwischendurch jemand anderes gelegt hat', () {
    final g = sortedGame4();
    g.play(0, [c(Rank.sieben, Suit.karo)]);
    g.play(1, [c(Rank.acht, Suit.herz)]); // Unterbrechung
    g.pass(2);
    g.pass(3);
    g.play(0, [c(Rank.neun, Suit.karo)]);
    // Ab jetzt schieben alle anderen, Seat 0 legt den Rest.
    while (g.hands[0].isNotEmpty) {
      if (g.currentPlayer == 0) {
        g.play(0, [g.hands[0].first]);
      } else {
        g.pass(g.currentPlayer);
      }
    }
    expect(g.finishOrder.first, 0);
    expect(g.swapsThisRound, isEmpty);
    playOut(g);
    expect(g.roundPoints[0], 2);
    expect(g.swapCounts, [0, 0, 0, 0]);
  });

  test('Swap: der Arsch der Vorrunde wird Präsi (auch mit Unterbrechung)', () {
    final g = sortedGame4();
    playOut(g);
    final arsch = g.finishOrder.last;
    final other = (arsch + 1) % 4;
    final arschHand = [
      c(Rank.sieben, Suit.karo),
      for (final s in Suit.values) c(Rank.ass, s),
      c(Rank.koenig, Suit.karo),
      c(Rank.koenig, Suit.herz),
      c(Rank.koenig, Suit.pik),
    ];
    final hands = List.generate(4, (s) => <PlayingCard>[]);
    hands[arsch] = arschHand;
    hands[other] = [c(Rank.acht, Suit.karo)];
    g.startRound(deck: deckFor(hands));
    expect(g.currentPlayer, arsch);
    g.play(arsch, [c(Rank.sieben, Suit.karo)]);
    g.play(other, [c(Rank.acht, Suit.karo)]); // Unterbrechung
    while (g.currentPlayer != arsch) {
      g.pass(g.currentPlayer);
    }
    g.play(arsch, [c(Rank.ass, Suit.karo)]); // Ass: Stich vorbei, er spielt aus
    while (g.hands[arsch].isNotEmpty) {
      if (g.currentPlayer == arsch) {
        g.play(arsch, [g.hands[arsch].last]);
      } else {
        g.pass(g.currentPlayer);
      }
    }
    expect(g.finishOrder.first, arsch);
    expect(g.swapsThisRound, {arsch: 1}, reason: 'Arsch wird Präsi = Swap');
    final before = g.scores[arsch];
    playOut(g);
    expect(g.roundPoints[arsch], 3);
    expect(g.scores[arsch], before + 3);
    expect(g.swapCounts[arsch], 1);
  });

  test('Doppel-Swap: Arsch wird ohne Unterbrechung Präsi (+2)', () {
    final g = sortedGame4();
    playOut(g);
    final arsch = g.finishOrder.last;
    final swapsBefore = g.swapCounts[arsch];
    final hands = List.generate(4, (s) => <PlayingCard>[]);
    hands[arsch] = [
      for (final s in Suit.values) c(Rank.ass, s),
      for (final s in Suit.values) c(Rank.koenig, s),
    ];
    g.startRound(deck: deckFor(hands));
    // Erst die Asse (beenden jeden Stich), dann die Könige – die kann keiner
    // mehr schlagen; die anderen schieben nur.
    while (g.hands[arsch].isNotEmpty) {
      if (g.currentPlayer == arsch) {
        g.play(arsch, [g.hands[arsch].last]);
      } else {
        g.pass(g.currentPlayer);
      }
    }
    expect(g.swapsThisRound, {arsch: 2});
    final before = g.scores[arsch];
    playOut(g);
    expect(g.roundPoints[arsch], 4, reason: 'Präsi +2, Doppel-Swap +2');
    expect(g.scores[arsch], before + 4);
    expect(g.swapCounts[arsch], swapsBefore + 2);
  });

  test('Alte Spielstände (Swaps als Liste) lassen sich laden', () {
    final g = sortedGame4();
    final json = g.toJson()..['swapsThisRound'] = [2];
    final loaded = ArschGame.fromJson(json);
    expect(loaded.swapsThisRound, {2: 1});
  });

  test('Swap-Zähler überstehen Speichern und Laden', () {
    final g = sortedGame4();
    while (g.hands[0].isNotEmpty) {
      g.currentPlayer == 0 ? g.play(0, [g.hands[0].first]) : g.pass(g.currentPlayer);
    }
    playOut(g);
    final copy = ArschGame.fromJson(
        jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>);
    expect(copy.swapCounts, [1, 0, 0, 0]);
    expect(copy.roundPoints, g.roundPoints);
    expect(copy.swapsThisRound, {0: 1});
  });
}
