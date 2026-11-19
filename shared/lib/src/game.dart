import 'dart:math';

import 'card.dart';

/// Bei dieser Punktzahl (plus oder minus) ist das Spiel vorbei.
const int targetScore = 20;

const _titles5 = ['Präsi', 'Vize-Präsi', 'Mitte', 'Vize-Arsch', 'Arsch'];
const _titles4 = ['Präsi', 'Vize-Präsi', 'Vize-Arsch', 'Arsch'];
const _points5 = [2, 1, 0, -1, -2];
const _points4 = [2, 1, -1, -2];

/// Titel für eine Platzierung (0 = als Erster fertig).
String titleFor(int place, int playerCount) =>
    (playerCount == 5 ? _titles5 : _titles4)[place];

/// Punkte für eine Platzierung (0 = als Erster fertig).
int pointsFor(int place, int playerCount) =>
    (playerCount == 5 ? _points5 : _points4)[place];

/// [discarding]: Bei 5 Spielern hat der Arsch der Vorrunde die beiden Karten
/// aus der Mitte aufgenommen und muss zwei Karten zurücklegen, bevor es losgeht.
enum GamePhase { discarding, playing, roundOver, gameOver }

/// So viele Karten legt der Arsch zurück in die Mitte.
const int discardCount = 2;

/// Extrapunkte für einen Swap.
const int swapBonus = 1;

class GameRuleException implements Exception {
  GameRuleException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Ein Spielzug. Leere [cards] bedeutet "Ich schiebe".
class LastAction {
  LastAction(this.seat, this.cards);
  final int seat;
  final List<PlayingCard> cards;

  /// Mit diesem Zug war der Stich vorbei (Ass gelegt oder alle haben geschoben).
  bool endsTrick = false;

  /// Der Spieler hat seine Bedenkzeit überschritten; der Zug wurde für ihn gemacht.
  bool timedOut = false;

  bool get isPass => cards.isEmpty;

  Map<String, dynamic> toJson() => {
        'seat': seat,
        'cards': _ids(cards),
        if (endsTrick) 'endsTrick': true,
        if (timedOut) 'timedOut': true,
      };

  factory LastAction.fromJson(Map<String, dynamic> j) =>
      LastAction(j['seat'] as int, _cards(j['cards']))
        ..endsTrick = j['endsTrick'] as bool? ?? false
        ..timedOut = j['timedOut'] as bool? ?? false;
}

List<int> _ids(List<PlayingCard> cards) => [for (final c in cards) c.id];

List<PlayingCard> _cards(Object? ids) =>
    [for (final id in ids as List) PlayingCard.fromId(id as int)];

/// Prüft, ob [cards] auf [pile] (die zuletzt gelegten Karten, leer beim
/// Ausspielen) gelegt werden dürfen. Gibt null zurück, wenn alles passt,
/// sonst eine Fehlermeldung.
String? validatePlay(List<PlayingCard> cards, List<PlayingCard> pile) {
  if (cards.isEmpty) return 'Wähle mindestens eine Karte aus.';
  if (cards.any((c) => c.rank != cards.first.rank)) {
    return 'Du kannst nur Karten mit gleichem Wert zusammen legen.';
  }
  if (pile.isEmpty) return null;
  if (cards.length != pile.length) {
    return pile.length == 1
        ? 'Du musst genau eine Karte legen.'
        : 'Du musst genau ${pile.length} Karten legen.';
  }
  if (cards.first.rank.index <= pile.first.rank.index) {
    return 'Du musst einen höheren Wert legen.';
  }
  return null;
}

/// Ein komplettes Spiel "Arsch" über mehrere Runden.
///
/// Sitzplätze sind 0..playerCount-1; der nächste Spieler (links) ist
/// jeweils der mit der nächsthöheren Nummer.
class ArschGame {
  ArschGame(this.playerCount, {Random? random})
      : _random = random ?? Random.secure(),
        scores = List.filled(playerCount, 0),
        hands = List.generate(playerCount, (_) => <PlayingCard>[]) {
    if (playerCount != 4 && playerCount != 5) {
      throw ArgumentError('Es können nur 4 oder 5 Spieler teilnehmen.');
    }
  }

  final int playerCount;
  final Random _random;

  /// Kompletter Spielstand zum Speichern (z.B. damit ein Server-Neustart
  /// laufende Spiele nicht verliert). Gegenstück: [ArschGame.fromJson].
  Map<String, dynamic> toJson() => {
        'playerCount': playerCount,
        'hands': [for (final h in hands) _ids(h)],
        'middle': _ids(middle),
        'scores': scores,
        'pile': _ids(pile),
        'previousPile': _ids(previousPile),
        'lastPlayer': lastPlayer,
        'currentPlayer': currentPlayer,
        'passes': _passes,
        'finishOrder': finishOrder,
        'phase': phase.name,
        'roundNumber': roundNumber,
        'log': [for (final a in log) a.toJson()],
        // lastAction ist immer der letzte Eintrag im Protokoll (oder null).
        'pickedUp': _ids(pickedUp),
        'previousArsch': previousArsch,
        'swapsThisRound': {
          for (final e in swapsThisRound.entries) '${e.key}': e.value
        },
        'swapCounts': swapCounts,
        'roundPoints': roundPoints,
      };

  factory ArschGame.fromJson(Map<String, dynamic> j, {Random? random}) {
    final g = ArschGame(j['playerCount'] as int, random: random);
    g.hands = [for (final h in j['hands'] as List) _cards(h)];
    g.middle = _cards(j['middle']);
    final scores = (j['scores'] as List).cast<int>();
    for (var i = 0; i < g.playerCount; i++) {
      g.scores[i] = scores[i];
    }
    g.pile = _cards(j['pile']);
    g.previousPile = _cards(j['previousPile']);
    g.lastPlayer = j['lastPlayer'] as int?;
    g.currentPlayer = j['currentPlayer'] as int;
    g._passes = j['passes'] as int;
    g.finishOrder = (j['finishOrder'] as List).cast<int>().toList();
    g.phase = GamePhase.values.byName(j['phase'] as String);
    g.roundNumber = j['roundNumber'] as int;
    g.log = [
      for (final a in j['log'] as List)
        LastAction.fromJson(a as Map<String, dynamic>)
    ];
    g.lastAction = g.log.isEmpty ? null : g.log.last;
    g.pickedUp = _cards(j['pickedUp']);
    // Ältere Spielstände kennen noch keine Swaps.
    g.previousArsch = j['previousArsch'] as int?;
    final swaps = j['swapsThisRound'];
    g.swapsThisRound = swaps is Map
        ? {
            for (final e in swaps.entries)
              int.parse(e.key as String): e.value as int
          }
        // Ältere Spielstände: Liste der Plätze mit einfachem Swap.
        : {for (final seat in (swaps as List? ?? const []).cast<int>()) seat: 1};
    for (final (key, list) in [
      ('swapCounts', g.swapCounts),
      ('roundPoints', g.roundPoints)
    ]) {
      final values = (j[key] as List?)?.cast<int>();
      for (var i = 0; values != null && i < g.playerCount; i++) {
        list[i] = values[i];
      }
    }
    return g;
  }

  List<List<PlayingCard>> hands;

  /// Restkarten, die verdeckt in der Mitte liegen.
  List<PlayingCard> middle = [];

  final List<int> scores;

  /// Die zuletzt gelegten Karten des laufenden Stichs (leer = es wird neu ausgespielt).
  List<PlayingCard> pile = [];

  /// Die letzten Karten des vorigen Stichs (nur zur Anzeige).
  List<PlayingCard> previousPile = [];

  /// Wer [pile] gelegt hat.
  int? lastPlayer;

  int currentPlayer = 0;
  int _passes = 0;

  /// Sitzplätze in der Reihenfolge, in der die Spieler fertig wurden.
  List<int> finishOrder = [];

  GamePhase phase = GamePhase.roundOver;
  int roundNumber = 0;
  LastAction? lastAction;

  /// Alle Spielzüge der laufenden Runde, in Reihenfolge.
  List<LastAction> log = [];

  /// Die Karten aus der Mitte, die der Arsch in dieser Runde aufgenommen hat
  /// (nur ihm zeigen).
  List<PlayingCard> pickedUp = [];

  /// Der Arsch der Vorrunde (null in Runde 1). Wird er Präsi, ist das ein Swap.
  int? previousArsch;

  /// Swaps dieser Runde pro Platz: 1 = Swap, 2 = Doppel-Swap (beide Bedingungen).
  /// Jeder Swap gibt [swapBonus] Punkte extra.
  Map<int, int> swapsThisRound = {};

  /// Anzahl der Swaps pro Spieler im ganzen Spiel.
  late final List<int> swapCounts = List.filled(playerCount, 0);

  /// Punkte der zuletzt beendeten Runde pro Spieler (inkl. Swap-Bonus).
  late final List<int> roundPoints = List.filled(playerCount, 0);

  /// Die Züge, die seit dem letzten eigenen Zug (Legen oder Schieben) von
  /// [seat] in dieser Runde passiert sind – höchstens die letzten [max].
  /// Für einen Platz, der nicht mitspielt (z.B. -1), ist das die ganze Runde.
  List<LastAction> movesSince(int seat, {int? max = 12}) {
    final start = log.lastIndexWhere((a) => a.seat == seat) + 1;
    final moves = log.sublist(start);
    return max == null || moves.length <= max
        ? moves
        : moves.sublist(moves.length - max);
  }

  bool _isActive(int seat) => hands[seat].isNotEmpty;

  int get _activeCount => hands.where((h) => h.isNotEmpty).length;

  /// Platzierung eines Spielers in der laufenden Runde oder null.
  int? placeOf(int seat) {
    final i = finishOrder.indexOf(seat);
    return i < 0 ? null : i;
  }

  /// Startet die erste bzw. nächste Runde. [deck] ist nur für Tests gedacht.
  void startRound({List<PlayingCard>? deck}) {
    if (phase == GamePhase.gameOver) {
      throw GameRuleException('Das Spiel ist bereits vorbei.');
    }
    if (phase == GamePhase.playing || phase == GamePhase.discarding) {
      throw GameRuleException('Die Runde läuft noch.');
    }
    // Ab der zweiten Runde beginnt der Arsch der Vorrunde.
    final int? arsch = roundNumber == 0 ? null : finishOrder.last;
    previousArsch = arsch;
    swapsThisRound = {};

    final cards = deck ?? (fullDeck()..shuffle(_random));
    final perPlayer = cards.length ~/ playerCount;
    hands = List.generate(playerCount, (_) => <PlayingCard>[]);
    for (var i = 0; i < perPlayer * playerCount; i++) {
      hands[i % playerCount].add(cards[i]);
    }
    middle = cards.sublist(perPlayer * playerCount);
    for (final h in hands) {
      h.sort();
    }

    pile = [];
    previousPile = [];
    lastPlayer = null;
    lastAction = null;
    log = [];
    _passes = 0;
    finishOrder = [];
    roundNumber++;
    currentPlayer = arsch ?? _seatWithLowestCard();
    pickedUp = [];
    phase = GamePhase.playing;

    // Zu fünft nimmt der Arsch die Karten aus der Mitte auf und legt danach
    // zwei Karten seiner Wahl zurück.
    if (arsch != null && middle.isNotEmpty) {
      pickedUp = middle;
      hands[arsch]
        ..addAll(middle)
        ..sort();
      middle = [];
      phase = GamePhase.discarding;
    }
  }

  /// Der Arsch [seat] legt [cards] verdeckt zurück in die Mitte.
  void discard(int seat, List<PlayingCard> cards) {
    if (phase != GamePhase.discarding) {
      throw GameRuleException('Gerade wird nichts zurückgelegt.');
    }
    if (seat != currentPlayer) {
      throw GameRuleException('Nur der Arsch legt Karten zurück.');
    }
    if (cards.length != discardCount) {
      throw GameRuleException('Lege genau $discardCount Karten zurück.');
    }
    if (cards.toSet().length != cards.length ||
        cards.any((c) => !hands[seat].contains(c))) {
      throw GameRuleException('Diese Karten hast du nicht auf der Hand.');
    }
    hands[seat].removeWhere(cards.contains);
    middle = List.of(cards)..sort();
    pickedUp = [];
    phase = GamePhase.playing;
  }

  int _seatWithLowestCard() {
    var best = 0;
    for (var s = 1; s < playerCount; s++) {
      if (hands[s].first.id < hands[best].first.id) best = s;
    }
    return best;
  }

  int _nextActive(int seat) {
    for (var i = 1; i <= playerCount; i++) {
      final s = (seat + i) % playerCount;
      if (_isActive(s)) return s;
    }
    return seat;
  }

  void _checkTurn(int seat) {
    if (phase == GamePhase.discarding) {
      throw GameRuleException(
          'Zuerst legt der Arsch $discardCount Karten zurück in die Mitte.');
    }
    if (phase != GamePhase.playing) {
      throw GameRuleException('Gerade läuft keine Runde.');
    }
    if (seat != currentPlayer) {
      throw GameRuleException('Du bist nicht dran.');
    }
  }

  /// Spieler [seat] legt [cards].
  void play(int seat, List<PlayingCard> cards) {
    _checkTurn(seat);
    if (cards.toSet().length != cards.length ||
        cards.any((c) => !hands[seat].contains(c))) {
      throw GameRuleException('Diese Karten hast du nicht auf der Hand.');
    }
    final error = validatePlay(cards, pile);
    if (error != null) throw GameRuleException(error);

    hands[seat].removeWhere(cards.contains);
    pile = List.of(cards)..sort();
    lastPlayer = seat;
    _passes = 0;
    lastAction = LastAction(seat, pile);
    log.add(lastAction!);

    if (hands[seat].isEmpty) {
      finishOrder.add(seat);
      final swaps = _swapsOf(seat);
      if (swaps > 0) swapsThisRound[seat] = swaps;
      if (_activeCount == 1) {
        // Der letzte Spieler mit Karten ist der Arsch.
        finishOrder.add(_nextActive(seat));
        _endRound();
        return;
      }
    }

    if (cards.first.rank == Rank.ass) {
      _endTrick();
    } else {
      currentPlayer = _nextActive(seat);
    }
  }

  /// Die Bedenkzeit von [seat] ist abgelaufen: Es wird so getan, als hätte er
  /// „Ich schiebe“ gesagt. Wer ausspielt, kann nicht schieben – für ihn wird
  /// die niedrigste Karte gelegt. Muss der Arsch noch zurücklegen, gehen seine
  /// zwei niedrigsten Karten zurück in die Mitte.
  void timeoutMove(int seat) {
    if (phase == GamePhase.discarding) {
      discard(seat, botDiscard(hands[seat]));
      return;
    }
    _checkTurn(seat);
    final before = log.length;
    if (pile.isEmpty) {
      play(seat, [hands[seat].first]);
    } else {
      pass(seat);
    }
    if (log.length > before) log[before].timedOut = true;
  }

  /// Spieler [seat] sagt "Ich schiebe".
  void pass(int seat) {
    _checkTurn(seat);
    if (pile.isEmpty) {
      throw GameRuleException('Du spielst aus und kannst nicht schieben.');
    }
    _passes++;
    lastAction = LastAction(seat, const []);
    log.add(lastAction!);
    // Der Stich endet, wenn alle anderen noch aktiven Spieler nacheinander
    // geschoben haben.
    final others = _activeCount - (_isActive(lastPlayer!) ? 1 : 0);
    if (_passes >= others) {
      _endTrick();
    } else {
      currentPlayer = _nextActive(seat);
    }
  }

  void _endTrick() {
    final winner = lastPlayer!;
    if (log.isNotEmpty) log.last.endsTrick = true;
    previousPile = pile;
    pile = [];
    lastPlayer = null;
    _passes = 0;
    // Wer zuletzt gelegt hat, spielt neu aus. Ist er schon fertig,
    // kommt der nächste Spieler links von ihm dran.
    currentPlayer = _isActive(winner) ? winner : _nextActive(winner);
  }

  /// [seat] ist gerade fertig geworden. Jede dieser Bedingungen ist ein Swap,
  /// beide zusammen ein Doppel-Swap (Rückgabe 2):
  /// - er hat alle seine Karten gelegt, ohne dass zwischendurch ein anderer
  ///   Karten gelegt hat (Schieben zählt nicht);
  /// - er war Arsch der Vorrunde und wird Präsi.
  int _swapsOf(int seat) {
    final first = log.indexWhere((a) => a.seat == seat && !a.isPass);
    final uninterrupted =
        log.skip(first).every((a) => a.isPass || a.seat == seat);
    final arschToPraesi = finishOrder.length == 1 && seat == previousArsch;
    return (uninterrupted ? 1 : 0) + (arschToPraesi ? 1 : 0);
  }

  void _endRound() {
    for (var place = 0; place < finishOrder.length; place++) {
      final seat = finishOrder[place];
      final swaps = swapsThisRound[seat] ?? 0;
      roundPoints[seat] = pointsFor(place, playerCount) + swaps * swapBonus;
      scores[seat] += roundPoints[seat];
      swapCounts[seat] += swaps;
    }
    phase = scores.any((s) => s.abs() >= targetScore)
        ? GamePhase.gameOver
        : GamePhase.roundOver;
  }
}

/// Ein einfacher Computergegner: Er spielt die kleinste erlaubte Kombination
/// und schiebt, wenn er nicht höher legen kann. Beim Ausspielen legt er alle
/// Karten seines niedrigsten Werts. Gibt eine leere Liste für "Ich schiebe" zurück.
List<PlayingCard> botMove(List<PlayingCard> hand, List<PlayingCard> pile) {
  if (hand.isEmpty) return const [];
  final byRank = <Rank, List<PlayingCard>>{};
  for (final c in [...hand]..sort()) {
    byRank.putIfAbsent(c.rank, () => []).add(c);
  }
  final ranks = byRank.keys.toList()..sort((a, b) => a.index.compareTo(b.index));
  if (pile.isEmpty) return byRank[ranks.first]!;
  for (final r in ranks) {
    final cards = byRank[r]!;
    if (r.index > pile.first.rank.index && cards.length >= pile.length) {
      return cards.sublist(0, pile.length);
    }
  }
  return const [];
}

/// Welche Karten ein Computergegner als Arsch zurücklegt: die niedrigsten.
List<PlayingCard> botDiscard(List<PlayingCard> hand) =>
    ([...hand]..sort()).take(discardCount).toList();
