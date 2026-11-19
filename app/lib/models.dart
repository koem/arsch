import 'package:arsch_shared/arsch_shared.dart';

List<PlayingCard> _cards(Object? raw) => [
      for (final id in (raw as List? ?? const [])) PlayingCard.fromId(id as int)
    ];

class PlayerInfo {
  PlayerInfo.fromJson(Map<String, dynamic> j)
      : name = j['name'] as String,
        connected = j['connected'] as bool,
        isBot = j['bot'] as bool? ?? false,
        cardCount = j['cardCount'] as int,
        score = j['score'] as int,
        place = j['place'] as int?,
        swaps = j['swaps'] as int? ?? 0,
        roundSwaps = j['roundSwaps'] as int? ?? 0,
        roundPoints = j['roundPoints'] as int? ?? 0;

  final String name;
  final bool connected;
  final bool isBot;
  final int cardCount;
  final int score;

  /// Platzierung in der laufenden Runde (0 = Präsi) oder null, wenn noch Karten da sind.
  final int? place;

  /// Swaps im ganzen Spiel.
  final int swaps;

  /// Swaps in dieser Runde: 1 = Swap, 2 = Doppel-Swap (je ein gelber Stern).
  final int roundSwaps;

  /// Sterne für die Swaps dieser Runde, z.B. „★★“ beim Doppel-Swap.
  String get swapStars => '★' * roundSwaps;

  /// Punkte der zuletzt beendeten Runde (inkl. Swap-Bonus).
  final int roundPoints;
}

/// Ein Spielzug: [seat] legt [cards] (leer = „Ich schiebe“).
class MoveInfo {
  MoveInfo.fromJson(Map<String, dynamic> j)
      : seat = j['seat'] as int,
        cards = _cards(j['cards']),
        endsTrick = j['endsTrick'] as bool? ?? false,
        timedOut = j['timedOut'] as bool? ?? false;

  final int seat;
  final List<PlayingCard> cards;

  /// Mit diesem Zug war der Stich vorbei.
  final bool endsTrick;

  /// Die Bedenkzeit war abgelaufen; der Server hat den Zug gemacht.
  final bool timedOut;

  bool get isPass => cards.isEmpty;
}

/// Der Spielstand, wie ihn der Server an diesen Spieler schickt.
class TableState {
  TableState.fromJson(Map<String, dynamic> j)
      : code = j['code'] as String,
        phase = j['phase'] as String,
        you = j['you'] as int,
        spectatorCount = j['spectators'] as int? ?? 0,
        players = [
          for (final p in j['players'] as List)
            PlayerInfo.fromJson(p as Map<String, dynamic>)
        ],
        hand = _cards(j['hand']),
        pickedUp = _cards(j['pickedUp']),
        pile = _cards(j['pile']),
        previousPile = _cards(j['previousPile']),
        pilePlayer = j['pilePlayer'] as int?,
        current = j['current'] as int? ?? 0,
        middleCount = j['middleCount'] as int? ?? 0,
        round = j['round'] as int? ?? 0,
        turnDeadline = j['turnSecondsLeft'] == null
            ? null
            : DateTime.now()
                .add(Duration(seconds: j['turnSecondsLeft'] as int)),
        reminderBefore =
            Duration(seconds: j['reminderSecondsBefore'] as int? ?? 0),
        lastSeat = (j['lastAction'] as Map<String, dynamic>?)?['seat'] as int?,
        lastCards =
            _cards((j['lastAction'] as Map<String, dynamic>?)?['cards']),
        recent = [
          for (final m in j['recent'] as List? ?? const [])
            MoveInfo.fromJson(m as Map<String, dynamic>)
        ];

  final String code;

  /// 'lobby', 'discarding', 'playing', 'roundOver' oder 'gameOver'.
  final String phase;

  /// Eigener Sitzplatz; -1 = Zuschauer.
  final int you;
  final int spectatorCount;
  final List<PlayerInfo> players;
  final List<PlayingCard> hand;

  /// Nur für den Arsch beim Zurücklegen: die Karten, die er aus der Mitte bekommen hat.
  final List<PlayingCard> pickedUp;
  final List<PlayingCard> pile;
  final List<PlayingCard> previousPile;
  final int? pilePlayer;
  final int current;
  final int middleCount;
  final int round;

  /// Bis wann der Mensch, der dran ist, ziehen muss (sonst wird für ihn
  /// geschoben). Null bei Bots und außerhalb einer Runde.
  final DateTime? turnDeadline;

  /// So lange vor [turnDeadline] soll die App erinnern.
  final Duration reminderBefore;

  /// Letzter Spielzug: wer ([lastSeat]) und was ([lastCards], leer = geschoben).
  final int? lastSeat;
  final List<PlayingCard> lastCards;

  /// Was seit dem eigenen letzten Zug passiert ist (Zuschauer: die letzten Züge).
  final List<MoveInfo> recent;

  bool get inLobby => phase == 'lobby';

  /// Runde vorbei: Ergebnis steht fest ('roundOver' oder 'gameOver').
  bool get roundFinished => phase == 'roundOver' || phase == 'gameOver';
  bool get isPlaying => phase == 'playing';

  /// Der Arsch legt gerade 2 Karten zurück in die Mitte ([current] ist der Arsch).
  bool get isDiscarding => phase == 'discarding';

  /// Die Runde läuft (Zurücklegen oder Spielen).
  bool get roundRunning => isPlaying || isDiscarding;
  bool get isSpectator => you < 0;

  /// Man ist am Zug – beim Spielen oder als Arsch beim Zurücklegen.
  bool get isMyTurn => !isSpectator && roundRunning && current == you;

  /// Nur für Spieler, nicht für Zuschauer.
  PlayerInfo get me => players[you];
}
