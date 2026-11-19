import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:arsch_shared/arsch_shared.dart';

/// Arsch-Spielserver.
///
/// Start:  dart run bin/server.dart      (Port über Umgebungsvariable PORT, Standard 8080)
///
/// Weitere Umgebungsvariablen (in Sekunden, vor allem zum Testen):
///   TURN_TIMEOUT       Bedenkzeit pro Zug, danach wird automatisch geschoben (Standard 86400 = 24 h)
///   TURN_REMINDER      so lange vor Ablauf erinnert die App (Standard 10800 = 3 h)
///   FINISHED_GAME      Spiel zwischen zwei Runden oder am Ende, bei dem kein Mensch verbunden ist,
///                      wird danach gelöscht (Standard 259200 = 3 Tage). Laufende Runden werden nie
///                      gelöscht – sie laufen über die Bedenkzeit von selbst zu Ende.
///   TLS_CERT, TLS_KEY  Pfade zu Zertifikat (Kette) und Schlüssel im PEM-Format. Wenn gesetzt,
///                      läuft der Server verschlüsselt (wss://), sonst unverschlüsselt (ws://).
///   DATA_DIR           Ordner für den Spielstand (Standard ./data). Alle Räume werden dort in
///                      rooms.json gespeichert und beim Start wieder geladen.
///
/// Protokoll (JSON über WebSocket):
///   Client -> Server
///     {type: create, name}            neuen Raum anlegen
///     {type: join, code, name}        Raum beitreten (läuft das Spiel schon: zuschauen)
///     {type: rejoin, code, token}     nach Verbindungsabbruch zurückkehren
///     {type: addBot}                  Computergegner hinzufügen (nur Gastgeber, in der Lobby)
///     {type: removeBot, seat}         Computergegner entfernen (nur Gastgeber, in der Lobby)
///     {type: start}                   Spiel starten (nur Gastgeber, 4 oder 5 Spieler)
///     {type: discard, cards: [ids]}   Arsch legt 2 Karten zurück in die Mitte (Phase discarding)
///     {type: play, cards: [ids]}      Karten legen
///     {type: pass}                    "Ich schiebe"
///     {type: nextRound}               nächste Runde austeilen
///     {type: newGame}                 nach Spielende zurück in die Lobby
///     {type: abort}                   laufendes Spiel abbrechen, zurück in die Lobby
///     {type: leave}                   Raum verlassen
///   Server -> Client
///     {type: joined, code, token}
///     {type: state, ...}              kompletter Spielstand aus Sicht des Empfängers
///                                     (Zuschauer: you = -1, spectator = true, keine Handkarten)
///
///   HTTP GET /r/<CODE> liefert eine Einladungsseite mit Link arsch://join?code=..&server=..
///     {type: error, message, reason?}

final Map<String, Room> rooms = {};
final Random _rnd = Random.secure();

const _emptyRoomTimeout = Duration(minutes: 15);

Duration _envSeconds(String name, int fallback) => Duration(
    seconds: int.tryParse(Platform.environment[name] ?? '') ?? fallback);

/// Bedenkzeit pro Zug. Danach gilt der Zug als „Ich schiebe“.
final Duration _turnTimeout = _envSeconds('TURN_TIMEOUT', 24 * 3600);

/// So lange vor Ablauf der Bedenkzeit erinnert die App den Spieler.
final Duration _turnReminder = _envSeconds('TURN_REMINDER', 3 * 3600);

/// Ein Spiel zwischen zwei Runden oder am Ende, bei dem niemand mehr
/// verbunden ist, bleibt so lange erhalten.
final Duration _finishedGameTimeout =
    _envSeconds('FINISHED_GAME', 3 * 24 * 3600);

final File _saveFile = File(
    '${Platform.environment['DATA_DIR'] ?? 'data'}${Platform.pathSeparator}rooms.json');
Timer? _saveTimer;

/// Speichert alle Räume kurz nach der letzten Änderung.
void _scheduleSave() {
  _saveTimer ??= Timer(const Duration(milliseconds: 300), () {
    _saveTimer = null;
    _saveNow();
  });
}

/// Schreibt alle Räume atomar (erst in eine temporäre Datei, dann umbenennen).
void _saveNow() {
  try {
    _saveFile.parent.createSync(recursive: true);
    final tmp = File('${_saveFile.path}.tmp');
    tmp.writeAsStringSync(jsonEncode({
      'version': 1,
      'rooms': [for (final r in rooms.values) r.toJson()],
    }), flush: true);
    tmp.renameSync(_saveFile.path);
  } catch (e) {
    stderr.writeln('Speichern fehlgeschlagen: $e');
  }
}

/// Lädt die gespeicherten Räume. Eine kaputte Datei wird beiseitegelegt.
void _load() {
  if (!_saveFile.existsSync()) return;
  try {
    final data = jsonDecode(_saveFile.readAsStringSync()) as Map<String, dynamic>;
    for (final j in data['rooms'] as List) {
      final r = Room.fromJson(j as Map<String, dynamic>);
      rooms[r.code] = r;
    }
    for (final r in rooms.values.toList()) {
      r.broadcast(); // startet Bots, Bedenkzeiten und Aufräumen wieder
    }
    stdout.writeln('${rooms.length} gespeicherte Räume geladen.');
  } catch (e) {
    final broken = '${_saveFile.path}.broken-${DateTime.now().millisecondsSinceEpoch}';
    stderr.writeln('Spielstand nicht lesbar ($e), verschoben nach $broken');
    rooms.clear();
    _saveFile.renameSync(broken);
  }
}

/// Bedenkzeit der Computergegner, damit Menschen den Zügen folgen können.
const _botDelay = Duration(milliseconds: 1200);

Future<void> main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  _load();
  // Beim Beenden (z.B. docker stop) noch einmal speichern.
  for (final signal in [ProcessSignal.sigterm, ProcessSignal.sigint]) {
    signal.watch().listen((_) {
      _saveNow();
      exit(0);
    });
  }
  // IPv4 und IPv6 (manche Anschlüsse sind von außen nur per IPv6 erreichbar).
  // Mit TLS_CERT/TLS_KEY (PEM-Dateien) direkt verschlüsselt: wss:// statt ws://.
  final cert = Platform.environment['TLS_CERT'];
  final key = Platform.environment['TLS_KEY'];
  final HttpServer server;
  if (cert != null && key != null) {
    final context = SecurityContext()
      ..useCertificateChain(cert)
      ..usePrivateKey(key);
    server = await HttpServer.bindSecure(
        InternetAddress.anyIPv6, port, context,
        v6Only: false);
    stdout.writeln('Arsch-Server läuft auf Port $port (TLS, wss://)');
  } else {
    server = await HttpServer.bind(InternetAddress.anyIPv6, port, v6Only: false);
    stdout.writeln('Arsch-Server läuft auf Port $port');
  }

  await for (final request in server) {
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      try {
        final ws = await WebSocketTransformer.upgrade(request);
        ws.pingInterval = const Duration(seconds: 20);
        Connection(ws);
      } catch (e) {
        stderr.writeln('WebSocket-Upgrade fehlgeschlagen: $e');
      }
    } else if (request.uri.pathSegments.length == 2 &&
        request.uri.pathSegments[0] == 'r') {
      _invitePage(request);
    } else {
      request.response
        ..headers.contentType = ContentType.text
        ..write('Arsch-Server läuft. Räume: ${rooms.length}');
      unawaited(request.response.close());
    }
  }
}

/// Einladungsseite für geteilte Links: öffnet die App über arsch://join.
void _invitePage(HttpRequest request) {
  final code = request.uri.pathSegments[1].toUpperCase();
  final res = request.response..headers.contentType = ContentType.html;
  if (!RegExp(r'^[A-Z]{4}$').hasMatch(code)) {
    res
      ..statusCode = HttpStatus.notFound
      ..write('Ungültiger Raum-Code.');
    unawaited(res.close());
    return;
  }
  // Adresse des Servers so, wie der Einladende sie benutzt hat.
  final host = request.headers.value('x-forwarded-host') ??
      request.headers.host ??
      'localhost';
  final port = request.headers.value('x-forwarded-host') == null &&
          request.headers.port != null
      ? ':${request.headers.port}'
      : '';
  // Nur Zeichen, die in Hostnamen vorkommen (der Wert stammt aus der Anfrage).
  if (!RegExp(r'^[A-Za-z0-9.\-\[\]:]+$').hasMatch('$host$port')) {
    res
      ..statusCode = HttpStatus.badRequest
      ..write('Ungültiger Host.');
    unawaited(res.close());
    return;
  }
  final secure = request.headers.value('x-forwarded-proto') == 'https' ||
      request.requestedUri.scheme == 'https';
  final server = '${secure ? 'wss' : 'ws'}://$host$port';
  final app = Uri(
      scheme: 'arsch',
      host: 'join',
      queryParameters: {'code': code, 'server': server}).toString();
  // Android/Chrome öffnet Apps zuverlässiger über intent://-Links. Ohne
  // Paketnamen bleibt die Seite stehen, wenn die App nicht installiert ist.
  final androidApp =
      'intent://join?${Uri(queryParameters: {'code': code, 'server': server}).query}'
      '#Intent;scheme=arsch;end';
  final room = rooms[code];
  final status = room == null
      ? 'Diesen Raum gibt es (noch) nicht.'
      : room.game == null
          ? 'Im Warteraum: ${room.players.length} von 5 Spielern.'
          : 'Das Spiel läuft schon – du kannst zuschauen.';
  const esc = HtmlEscape(HtmlEscapeMode.attribute);
  res.write('''<!doctype html>
<html lang="de"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Arsch – Raum $code</title>
<style>
body{font-family:sans-serif;background:#0f3d24;color:#eee;text-align:center;padding:2em 1em}
a.btn{display:inline-block;margin:1.5em 0;padding:.9em 1.6em;border-radius:2em;
background:#a5d6a7;color:#0f3d24;font-weight:bold;text-decoration:none;font-size:1.2em}
code{font-size:2em;letter-spacing:.3em}
</style></head><body>
<h1>Arsch</h1>
<p>Du bist zu einem Spiel eingeladen.</p>
<p>Raum-Code<br><code>$code</code></p>
<p>${esc.convert(status)}</p>
<a class="btn" id="open" href="${esc.convert(app)}">In der App öffnen</a>
<p>Klappt das nicht? Öffne die App, trage unter „Server-Einstellungen“
<b>${esc.convert(server)}</b> ein und tritt mit dem Code bei.</p>
<script>
  // Direkt die App öffnen; der Knopf bleibt als Rückfall.
  var android = /Android/i.test(navigator.userAgent);
  var target = android ? ${jsonEncode(androidApp)} : ${jsonEncode(app)};
  document.getElementById('open').href = target;
  window.location.href = target;
</script>
</body></html>''');
  unawaited(res.close());
}

String _newRoomCode() {
  const letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  while (true) {
    final code =
        List.generate(4, (_) => letters[_rnd.nextInt(letters.length)]).join();
    if (!rooms.containsKey(code)) return code;
  }
}

String _newToken() => List.generate(
    16, (_) => _rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

String _cleanName(Object? raw) {
  var name = (raw is String ? raw : '').trim();
  if (name.isEmpty) throw GameRuleException('Bitte gib einen Namen ein.');
  if (name.length > 16) name = name.substring(0, 16);
  return name;
}

class Player {
  Player(this.name, this.conn)
      : token = _newToken(),
        isBot = false;
  Player.bot(this.name)
      : token = _newToken(),
        isBot = true;
  Player.fromJson(Map<String, dynamic> j)
      : name = j['name'] as String,
        token = j['token'] as String,
        isBot = j['bot'] as bool? ?? false;

  Map<String, dynamic> toJson() => {'name': name, 'token': token, 'bot': isBot};
  final String name;
  final String token;
  final bool isBot;
  Connection? conn;

  /// Computergegner sind immer "da".
  bool get connected => isBot || conn != null;
}

class Room {
  Room(this.code);

  /// Gespeicherter Raum; niemand ist verbunden.
  Room.fromJson(Map<String, dynamic> j) : code = j['code'] as String {
    players.addAll([
      for (final p in j['players'] as List)
        Player.fromJson(p as Map<String, dynamic>)
    ]);
    spectators.addAll([
      for (final p in j['spectators'] as List? ?? const [])
        Player.fromJson(p as Map<String, dynamic>)
    ]);
    final g = j['game'];
    if (g != null) game = ArschGame.fromJson(g as Map<String, dynamic>);
    _turnKey = j['turnKey'] as String?;
    final deadline = j['turnDeadline'] as int?;
    if (deadline != null) {
      _turnDeadline = DateTime.fromMillisecondsSinceEpoch(deadline);
    }
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'players': [for (final p in players) p.toJson()],
        'spectators': [for (final p in spectators) p.toJson()],
        'game': game?.toJson(),
        'turnKey': _turnKey,
        'turnDeadline': _turnDeadline?.millisecondsSinceEpoch,
      };

  final String code;

  /// Der Index in dieser Liste ist der Sitzplatz. Platz 0 ist der Gastgeber.
  /// Während eines laufenden Spiels wird die Liste nicht verändert.
  final List<Player> players = [];
  ArschGame? game;
  Timer? _cleanup;
  Duration? _cleanupAfter;
  Timer? _botTimer;

  /// Bedenkzeit des Menschen, der gerade am Zug ist.
  Timer? _turnTimer;
  DateTime? _turnDeadline;
  String? _turnKey;

  /// Wer beitritt, während das Spiel läuft, schaut zu.
  final List<Player> spectators = [];

  Iterable<Player> get humans => players.where((p) => !p.isBot);

  /// Fügt einen Menschen hinzu. Menschen sitzen immer vor den Bots, damit
  /// Platz 0 (der Gastgeber) ein Mensch ist. Ist der Raum voll, macht ein
  /// Bot Platz.
  void addHuman(Player p) {
    if (players.length >= 5) {
      final bot = players.lastIndexWhere((q) => q.isBot);
      if (bot < 0) throw GameRuleException('Der Raum ist voll.');
      players.removeAt(bot);
    }
    final firstBot = players.indexWhere((q) => q.isBot);
    players.insert(firstBot < 0 ? players.length : firstBot, p);
  }

  void addBot() {
    if (players.length >= 5) throw GameRuleException('Der Raum ist voll.');
    final taken = {for (final p in players) p.name};
    var n = 1;
    while (taken.contains('Bot $n')) {
      n++;
    }
    players.add(Player.bot('Bot $n'));
  }

  void broadcast() {
    _updateTurnClock();
    for (var i = 0; i < players.length; i++) {
      players[i].conn?.send(stateFor(i));
    }
    if (spectators.isNotEmpty) {
      final view = stateFor(-1);
      for (final s in spectators) {
        s.conn?.send(view);
      }
    }
    if (game == null && humans.isEmpty) {
      // Nur noch Bots in der Lobby: Raum auflösen.
      players.clear();
    }
    if (players.isEmpty) {
      _close();
      return;
    }
    _updateCleanup();
    _scheduleBot();
    _scheduleSave();
  }

  /// Räumt verlassene Räume auf: leere Warteräume nach 15 Minuten, Spiele
  /// zwischen zwei Runden oder am Ende nach [_finishedGameTimeout].
  /// Eine laufende Runde wird nie gelöscht – über die Bedenkzeit und die Bots
  /// läuft sie von selbst zu Ende.
  void _updateCleanup() {
    final g = game;
    final Duration? after;
    if (humans.any((p) => p.connected)) {
      after = null;
    } else if (g == null) {
      after = _emptyRoomTimeout;
    } else if (g.phase == GamePhase.playing ||
        g.phase == GamePhase.discarding) {
      after = null;
    } else {
      after = _finishedGameTimeout;
    }
    // Der Zähler läuft ab dem Moment, in dem diese Lage eingetreten ist;
    // weitere Nachrichten (z.B. Zuschauer) setzen ihn nicht zurück.
    if (after == _cleanupAfter) return;
    _cleanup?.cancel();
    _cleanupAfter = after;
    _cleanup = after == null ? null : Timer(after, _close);
  }

  void _close() {
    _cleanup?.cancel();
    _botTimer?.cancel();
    _turnTimer?.cancel();
    if (rooms[code] == this) rooms.remove(code);
    _scheduleSave();
  }

  /// Startet die Bedenkzeit neu, sobald ein anderer Mensch (oder derselbe
  /// mit einem neuen Zug) dran ist. Bei Ablauf wird für ihn geschoben.
  void _updateTurnClock() {
    final g = game;
    final running = g != null &&
        (g.phase == GamePhase.playing || g.phase == GamePhase.discarding);
    if (!running || players[g.currentPlayer].isBot) {
      _turnTimer?.cancel();
      _turnTimer = null;
      _turnDeadline = null;
      _turnKey = null;
      return;
    }
    final key =
        '${g.roundNumber}/${g.phase.name}/${g.log.length}/${g.currentPlayer}';
    if (key == _turnKey && _turnTimer != null) return;
    if (key != _turnKey || _turnDeadline == null) {
      _turnKey = key;
      _turnDeadline = DateTime.now().add(_turnTimeout);
    }
    // Nach einem Neustart läuft die gespeicherte Restzeit weiter.
    final left = _turnDeadline!.difference(DateTime.now());
    _turnTimer?.cancel();
    final seat = g.currentPlayer;
    _turnTimer = Timer(left.isNegative ? Duration.zero : left, () {
      if (rooms[code] != this || game != g || _turnKey != key) return;
      try {
        g.timeoutMove(seat);
      } on GameRuleException catch (e) {
        stderr.writeln('Zeitablauf-Zug abgelehnt: $e');
        return;
      }
      broadcast();
    });
  }

  /// Ist ein Bot am Zug, zieht er nach kurzer Bedenkzeit.
  void _scheduleBot() {
    _botTimer?.cancel();
    _botTimer = null;
    final g = game;
    if (g == null) return;
    if (g.phase != GamePhase.playing && g.phase != GamePhase.discarding) return;
    if (!players[g.currentPlayer].isBot) return;
    final seat = g.currentPlayer;
    final moveCount = g.log.length;
    _botTimer = Timer(_botDelay, () {
      if (rooms[code] != this || game != g) return;
      if (g.currentPlayer != seat || g.log.length != moveCount) return;
      if (g.phase == GamePhase.discarding) {
        g.discard(seat, botDiscard(g.hands[seat]));
        broadcast();
        return;
      }
      if (g.phase != GamePhase.playing) return;
      final cards = botMove(g.hands[seat], g.pile);
      try {
        cards.isEmpty ? g.pass(seat) : g.play(seat, cards);
      } on GameRuleException catch (e) {
        stderr.writeln('Bot-Zug abgelehnt ($e), Bot schiebt bzw. spielt aus.');
        g.pile.isEmpty ? g.play(seat, [g.hands[seat].first]) : g.pass(seat);
      }
      broadcast();
    });
  }

  void backToLobby() {
    _botTimer?.cancel();
    _turnTimer?.cancel();
    _turnKey = null;
    _turnDeadline = null;
    game = null;
    players.removeWhere((p) => !p.connected);
    seatSpectators();
    broadcast();
  }

  /// In der Lobby setzen sich Zuschauer an freie Plätze (Bots machen dafür
  /// Platz), in der Reihenfolge, in der sie gekommen sind.
  void seatSpectators() {
    if (game != null) return;
    spectators.removeWhere((s) => !s.connected);
    while (spectators.isNotEmpty) {
      try {
        addHuman(spectators.first);
      } on GameRuleException {
        break;
      }
      spectators.removeAt(0);
    }
  }

  /// Spielstand aus Sicht von Platz [seat]; -1 = Zuschauer.
  Map<String, dynamic> stateFor(int seat) {
    final g = game;
    final last = g?.lastAction;
    return {
      'type': 'state',
      'code': code,
      'phase': g == null ? 'lobby' : g.phase.name,
      'you': seat,
      'spectator': seat < 0,
      'spectators': spectators.where((s) => s.connected).length,
      'players': [
        for (var i = 0; i < players.length; i++)
          {
            'name': players[i].name,
            'connected': players[i].connected,
            'bot': players[i].isBot,
            'cardCount': g?.hands[i].length ?? 0,
            'score': g?.scores[i] ?? 0,
            'place': g?.placeOf(i),
            // Swaps im ganzen Spiel; Swaps dieser Runde (1 = Swap, 2 = Doppel-Swap).
            'swaps': g?.swapCounts[i] ?? 0,
            'roundSwaps': g?.swapsThisRound[i] ?? 0,
            // Punkte der zuletzt beendeten Runde (inkl. Swap-Bonus).
            'roundPoints': g?.roundPoints[i] ?? 0,
          },
      ],
      if (g != null) ...{
        'hand': seat < 0 ? [] : [for (final c in g.hands[seat]) c.id],
        'pile': [for (final c in g.pile) c.id],
        'previousPile': [for (final c in g.previousPile) c.id],
        'pilePlayer': g.lastPlayer,
        'current': g.currentPlayer,
        'middleCount': g.middle.length,
        'round': g.roundNumber,
        // Bedenkzeit des Menschen, der dran ist (relativ, wegen Uhrzeit-Abweichungen).
        if (_turnDeadline != null) ...{
          'turnSecondsLeft':
              _turnDeadline!.difference(DateTime.now()).inSeconds,
          'reminderSecondsBefore': _turnReminder.inSeconds,
        },
        // Nur der Arsch sieht, welche Karten er aus der Mitte aufgenommen hat.
        if (g.phase == GamePhase.discarding && seat == g.currentPlayer)
          'pickedUp': [for (final c in g.pickedUp) c.id],
        // Spieler: seit dem eigenen letzten Zug. Zuschauer: die ganze Runde.
        'recent': [
          for (final a in g.movesSince(seat, max: seat < 0 ? null : 12))
            {
              'seat': a.seat,
              'cards': [for (final c in a.cards) c.id],
              'endsTrick': a.endsTrick,
              'timedOut': a.timedOut,
            },
        ],
        'lastAction': last == null
            ? null
            : {
                'seat': last.seat,
                'cards': [for (final c in last.cards) c.id],
              },
      },
    };
  }
}

class Connection {
  Connection(this.ws) {
    ws.listen(_onData,
        onDone: _onDone, onError: (_) => _onDone(), cancelOnError: true);
  }

  final WebSocket ws;
  Room? room;
  Player? player;
  bool _closed = false;

  void send(Map<String, dynamic> message) {
    if (ws.readyState == WebSocket.open) ws.add(jsonEncode(message));
  }

  void _error(String message, {String? reason}) => send({
        'type': 'error',
        'message': message,
        if (reason != null) 'reason': reason,
      });

  void _onData(dynamic data) {
    try {
      if (data is! String) return;
      final msg = jsonDecode(data);
      if (msg is! Map<String, dynamic>) return;
      _handle(msg);
    } on GameRuleException catch (e) {
      _error(e.message);
    } catch (e) {
      _error('Ungültige Nachricht.');
    }
  }

  void _onDone() {
    if (_closed) return;
    _closed = true;
    _detach(leaving: false);
  }

  /// Löst diese Verbindung von ihrem Raum. In der Lobby verschwindet der
  /// Spieler, im laufenden Spiel bleibt sein Platz für eine Rückkehr frei.
  /// [leaving]: bewusst verlassen (statt Verbindungsabbruch). Getrennte
  /// Zuschauer bleiben eingetragen, damit sie zurückkehren können.
  void _detach({bool leaving = true}) {
    final r = room;
    final p = player;
    room = null;
    player = null;
    if (r == null || p == null || p.conn != this) return;
    if (r.spectators.contains(p)) {
      if (leaving) {
        r.spectators.remove(p);
      } else {
        p.conn = null;
      }
      r.broadcast();
      return;
    }
    if (r.game == null) {
      r.players.remove(p);
      r.seatSpectators();
    } else {
      p.conn = null;
    }
    r.broadcast();
  }

  void _enter(Room r, Player p) {
    room = r;
    player = p;
    send({'type': 'joined', 'code': r.code, 'token': p.token});
    r.broadcast();
  }

  /// Raum des Absenders, wenn er Gastgeber ist und noch kein Spiel läuft.
  Room _hostInLobby() {
    final r = room;
    final p = player;
    if (r == null || p == null) throw GameRuleException('Du bist in keinem Raum.');
    if (r.game != null) throw GameRuleException('Das Spiel läuft bereits.');
    if (r.players.indexOf(p) != 0) {
      throw GameRuleException('Nur der Gastgeber kann das tun.');
    }
    return r;
  }

  /// Raum, Sitzplatz und laufendes Spiel des Absenders.
  (Room, int, ArschGame) _inGame() {
    final r = room;
    final p = player;
    final g = r?.game;
    if (r == null || p == null || g == null) {
      throw GameRuleException('Es läuft kein Spiel.');
    }
    final seat = r.players.indexOf(p);
    if (seat < 0) throw GameRuleException('Du schaust nur zu.');
    return (r, seat, g);
  }

  void _handle(Map<String, dynamic> msg) {
    switch (msg['type']) {
      case 'create':
        final name = _cleanName(msg['name']);
        _detach();
        final r = Room(_newRoomCode());
        rooms[r.code] = r;
        final p = Player(name, this);
        r.players.add(p);
        _enter(r, p);

      case 'join':
        final name = _cleanName(msg['name']);
        final code = (msg['code'] as String? ?? '').trim().toUpperCase();
        final r = rooms[code];
        if (r == null) throw GameRuleException('Raum nicht gefunden.');
        // Läuft das Spiel schon oder sitzen schon 5 Menschen am Tisch: zuschauen.
        if (r.game != null || r.humans.length >= 5) {
          r.spectators.removeWhere((s) => !s.connected);
          if (r.spectators.length >= 20) {
            throw GameRuleException('Es schauen schon zu viele zu.');
          }
          _detach();
          final p = Player(name, this);
          r.spectators.add(p);
          _enter(r, p);
          return;
        }
        _detach();
        final p = Player(name, this);
        r.addHuman(p);
        _enter(r, p);

      case 'rejoin':
        final r = rooms[(msg['code'] as String? ?? '').toUpperCase()];
        final token = msg['token'];
        final matches = [...?r?.players, ...?r?.spectators]
            .where((p) => p.token == token);
        if (r == null || matches.isEmpty) {
          _error('Das Spiel existiert nicht mehr.', reason: 'rejoin_failed');
          return;
        }
        final p = matches.first;
        final old = p.conn;
        if (old != null && old != this) {
          old.room = null;
          old.player = null;
          unawaited(old.ws.close());
        }
        p.conn = this;
        _enter(r, p);

      case 'addBot':
        final r = _hostInLobby();
        r.addBot();
        r.broadcast();

      case 'removeBot':
        final r = _hostInLobby();
        final seat = msg['seat'];
        if (seat is! int || seat < 0 || seat >= r.players.length ||
            !r.players[seat].isBot) {
          throw GameRuleException('Dieser Platz ist kein Bot.');
        }
        r.players.removeAt(seat);
        r.broadcast();

      case 'start':
        final r = _hostInLobby();
        if (r.players.length < 4) {
          throw GameRuleException('Es werden 4 oder 5 Spieler benötigt.');
        }
        r.game = ArschGame(r.players.length)..startRound();
        r.broadcast();

      case 'play':
        final (r, seat, g) = _inGame();
        final ids = (msg['cards'] as List).cast<int>();
        g.play(seat, [for (final id in ids) PlayingCard.fromId(id)]);
        r.broadcast();

      case 'discard':
        final (r, seat, g) = _inGame();
        final ids = (msg['cards'] as List).cast<int>();
        g.discard(seat, [for (final id in ids) PlayingCard.fromId(id)]);
        r.broadcast();

      case 'pass':
        final (r, seat, g) = _inGame();
        g.pass(seat);
        r.broadcast();

      case 'nextRound':
        final (r, _, g) = _inGame();
        g.startRound();
        r.broadcast();

      case 'newGame':
        final (r, _, g) = _inGame();
        if (g.phase != GamePhase.gameOver) {
          throw GameRuleException('Das Spiel ist noch nicht vorbei.');
        }
        r.backToLobby();

      case 'abort':
        final (r, seat, _) = _inGame();
        if (seat != 0 && r.players.every((p) => p.connected)) {
          throw GameRuleException('Nur der Gastgeber kann das Spiel abbrechen.');
        }
        r.backToLobby();

      case 'leave':
        _detach();

      default:
        _error('Unbekannte Nachricht.');
    }
  }
}
