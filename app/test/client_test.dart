import 'package:arsch/game_client.dart';
import 'package:arsch/models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _state({int you = 0, String phase = 'playing'}) => {
      'type': 'state',
      'code': 'KQFB',
      'phase': phase,
      'you': you,
      'spectators': 2,
      'players': [
        for (var i = 0; i < 4; i++)
          {
            'name': i == 0 ? 'Anna' : 'Bot $i',
            'connected': true,
            'bot': i > 0,
            'cardCount': 8 - i,
            'score': 0,
            'place': null,
          },
      ],
      'hand': you < 0 ? <int>[] : [0, 4, 8],
      'pile': [12],
      'previousPile': <int>[],
      'pilePlayer': 1,
      'current': 0,
      'middleCount': 0,
      'round': 1,
      'recent': [
        {'seat': 1, 'cards': [12], 'endsTrick': false},
        {'seat': 2, 'cards': <int>[], 'endsTrick': true},
      ],
    };

void main() {
  test('Spielstand mit Bots, Zuschauern und Zugprotokoll', () {
    final s = TableState.fromJson(_state());
    expect(s.players[1].isBot, isTrue);
    expect(s.players[0].isBot, isFalse);
    expect(s.players[3].cardCount, 5);
    expect(s.spectatorCount, 2);
    expect(s.recent.length, 2);
    expect(s.recent.first.cards.single.id, 12);
    expect(s.recent.last.isPass, isTrue);
    expect(s.recent.last.endsTrick, isTrue);
    expect(s.isMyTurn, isTrue);
  });

  test('Zuschauer ist nie am Zug', () {
    final s = TableState.fromJson(_state(you: -1)..['current'] = 0);
    expect(s.isSpectator, isTrue);
    expect(s.isMyTurn, isFalse);
  });

  test('Einladungslink aus der Serveradresse', () {
    final c = GameClient();
    c.state = TableState.fromJson(_state());
    c.serverUrl = 'wss://arsch.example.de';
    expect(c.shareLink.toString(), 'https://arsch.example.de/r/KQFB');
    c.serverUrl = 'ws://192.168.1.5:8080';
    expect(c.shareLink.toString(), 'http://192.168.1.5:8080/r/KQFB');
    c.state = null;
    expect(c.shareLink, isNull);
  });

  test('Einladungslink ohne Namen: Code und Server merken', () {
    final c = GameClient();
    final messages = <String>[];
    c.onMessage = messages.add;
    c.handleLink(Uri.parse(
        'arsch://join?code=kqfb&server=${Uri.encodeComponent('ws://10.0.0.7:8080')}'));
    expect(c.pendingCode, 'KQFB');
    expect(c.serverUrl, 'ws://10.0.0.7:8080');
    expect(messages, hasLength(1));
    // Fremde oder kaputte Links werden ignoriert.
    c.pendingCode = null;
    c.handleLink(Uri.parse('https://example.com/r/KQFB'));
    c.handleLink(Uri.parse('arsch://join?code=<script>'));
    expect(c.pendingCode, isNull);
  });

  test('Zurücklegen: der Arsch ist am Zug und sieht die aufgenommenen Karten', () {
    final s = TableState.fromJson(_state()
      ..['phase'] = 'discarding'
      ..['pickedUp'] = [28, 31]);
    expect(s.isDiscarding, isTrue);
    expect(s.roundRunning, isTrue);
    expect(s.isMyTurn, isTrue);
    expect(s.pickedUp.map((c) => c.id), [28, 31]);
    final other = TableState.fromJson(_state()..['phase'] = 'discarding'..['current'] = 2);
    expect(other.isMyTurn, isFalse);
    expect(other.pickedUp, isEmpty);
  });

  test('Bedenkzeit: Frist und Erinnerung aus dem Spielstand', () {
    final s = TableState.fromJson(_state()
      ..['turnSecondsLeft'] = 7200
      ..['reminderSecondsBefore'] = 3600);
    final left = s.turnDeadline!.difference(DateTime.now()).inSeconds;
    expect(left, inInclusiveRange(7195, 7200));
    expect(s.reminderBefore, const Duration(hours: 1));
    expect(TableState.fromJson(_state()).turnDeadline, isNull);
  });

  test('Zug abgelaufen wird im Verlauf markiert', () {
    final s = TableState.fromJson(_state()
      ..['recent'] = [
        {'seat': 1, 'cards': <int>[], 'endsTrick': false, 'timedOut': true},
      ]);
    expect(s.recent.single.timedOut, isTrue);
  });

  test('„Du bist dran“ nur beim Wechsel, Erinnerung neu bei neuer Frist', () {
    final c = GameClient();
    final calls = <String>[];
    c.onMyTurn = (s, {required isNew}) => calls.add(isNew ? 'new' : 'moved');
    c.onTurnOver = () => calls.add('over');
    Map<String, dynamic> st(int current, int? secondsLeft, [String phase = 'playing']) =>
        _state()
          ..['current'] = current
          ..['phase'] = phase
          ..['turnSecondsLeft'] = secondsLeft;
    c.handleMessage(st(2, 86400)); // jemand anderes
    c.handleMessage(st(0, 86400, 'discarding')); // ich (Zurücklegen)
    c.handleMessage(st(0, 86399, 'discarding')); // gleiche Frist: nichts
    c.handleMessage(st(0, 86400)); // ich spiele aus: neue Frist, aber kein neuer Alarm
    c.handleMessage(st(0, 86000)); // Frist um > 10 s anders: Erinnerung neu planen
    c.handleMessage(st(1, 86400)); // nächster ist dran
    expect(calls, ['new', 'moved', 'over']);
  });

  test('Einladungslink mit bekanntem Namen: nur Code eintragen, nicht beitreten', () {
    final c = GameClient()..name = 'Anna';
    final messages = <String>[];
    c.onMessage = messages.add;
    c.handleLink(Uri.parse('arsch://join?code=ABCD&server=ws%3A%2F%2Fh%3A1'));
    expect(c.pendingCode, 'ABCD');
    expect(c.busy, isFalse, reason: 'kein Verbindungsaufbau');
    expect(c.state, isNull);
    expect(messages.single, contains('Beitreten'));
  });

  test('Ergebnis bleibt sichtbar, bis es geschlossen wird', () {
    final c = GameClient();
    c.handleMessage(_state()..['round'] = 1);
    expect(c.showResult, isFalse);
    c.handleMessage(_state(phase: 'roundOver')..['round'] = 1);
    expect(c.showResult, isTrue);
    expect(c.lastResult!.round, 1);
    // Die nächste Runde läuft schon – das Ergebnis bleibt.
    c.handleMessage(_state()..['round'] = 2);
    expect(c.showResult, isTrue);
    expect(c.lastResult!.phase, 'roundOver');
    c.dismissResult();
    expect(c.showResult, isFalse);
    c.reopenResult();
    expect(c.showResult, isTrue);
    c.dismissResult();
    // Weitere Nachrichten derselben beendeten Runde öffnen es nicht erneut.
    c.handleMessage(_state(phase: 'roundOver')..['round'] = 2);
    expect(c.showResult, isTrue, reason: 'neue Runde beendet');
    c.dismissResult();
    c.handleMessage(_state(phase: 'roundOver')..['round'] = 2);
    expect(c.showResult, isFalse);
  });

  test('Swaps im Spielstand', () {
    final s = TableState.fromJson(_state(phase: 'roundOver')
      ..['players'] = [
        for (var i = 0; i < 4; i++)
          {
            'name': 'P$i',
            'connected': true,
            'cardCount': 0,
            'score': 3,
            'place': i,
            'swaps': i == 0 ? 2 : 0,
            'roundSwaps': i == 0 ? 2 : 0,
            'roundPoints': i == 0 ? 4 : 0,
          },
      ]);
    expect(s.players[0].roundSwaps, 2);
    expect(s.players[0].swapStars, '★★');
    expect(s.players[0].swaps, 2);
    expect(s.players[0].roundPoints, 4);
    expect(s.players[1].swapStars, '');
    expect(s.roundFinished, isTrue);
  });
}
