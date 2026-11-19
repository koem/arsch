import 'dart:async';
import 'dart:convert';

import 'package:arsch_shared/arsch_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'models.dart';

/// Hält die Verbindung zum Spielserver und den aktuellen Spielstand.
class GameClient extends ChangeNotifier {
  /// Standard-Serveradresse. Beim Bauen überschreibbar mit
  ///   flutter run --dart-define=ARSCH_SERVER=ws://10.0.2.2:8080
  /// (10.0.2.2 ist aus dem Android-Emulator der eigene Rechner).
  static const defaultServerUrl = String.fromEnvironment('ARSCH_SERVER',
      defaultValue: 'ws://koem2.mooo.com:2284');

  String serverUrl = defaultServerUrl;
  String name = '';

  /// null = nicht in einem Raum (Startbildschirm).
  TableState? state;
  bool busy = false;
  bool reconnecting = false;

  /// Wird für Fehlermeldungen aufgerufen (z.B. um eine Snackbar zu zeigen).
  void Function(String message)? onMessage;

  /// Wird aufgerufen, wenn man am Zug ist: [isNew] beim Wechsel zu „du bist
  /// dran“, sonst wenn sich die Frist geändert hat (z.B. nach dem Zurücklegen).
  void Function(TableState state, {required bool isNew})? onMyTurn;
  void Function()? onTurnOver;

  /// Wird beim Betreten eines Raums aufgerufen.
  void Function()? onJoined;

  /// Raum-Code aus einem Einladungslink, der ins Eingabefeld soll.
  String? pendingCode;

  /// Gespeicherte Einstellungen sind geladen (vorher keinen Startbildschirm zeigen).
  bool initialized = false;

  /// Spielstand am Ende der letzten Runde. Er bleibt sichtbar, bis der Spieler
  /// ihn schließt – auch wenn die nächste Runde schon läuft.
  TableState? lastResult;
  bool showResult = false;

  void dismissResult() {
    showResult = false;
    notifyListeners();
  }

  void reopenResult() {
    showResult = lastResult != null;
    notifyListeners();
  }

  SharedPreferences? _prefs;
  WebSocketChannel? _channel;
  String? _code;
  String? _token;
  Timer? _retry;

  /// Zählt Verbindungsversuche; Ereignisse alter Verbindungen werden ignoriert.
  int _generation = 0;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    serverUrl = prefs.getString('serverUrl') ?? defaultServerUrl;
    name = prefs.getString('name') ?? '';
    _code = prefs.getString('code');
    _token = prefs.getString('token');
    if (_code != null && _token != null) {
      // Die App wurde während eines Spiels geschlossen: zurück an den Tisch.
      reconnecting = true;
      _open(_rejoinMessage());
    }
    initialized = true;
    notifyListeners();
  }

  Map<String, dynamic> _rejoinMessage() =>
      {'type': 'rejoin', 'code': _code, 'token': _token};

  void setServerUrl(String url) {
    serverUrl = url.trim().isEmpty ? defaultServerUrl : url.trim();
    _prefs?.setString('serverUrl', serverUrl);
  }

  void _setName(String value) {
    name = value.trim();
    _prefs?.setString('name', name);
  }

  void createRoom(String playerName) {
    _setName(playerName);
    busy = true;
    notifyListeners();
    _open({'type': 'create', 'name': name});
  }

  void joinRoom(String code, String playerName) {
    _setName(playerName);
    busy = true;
    notifyListeners();
    _open({'type': 'join', 'code': code.trim().toUpperCase(), 'name': name});
  }

  /// Einladungslink zum aktuellen Raum, z.B. https://mein-server.de/r/ABCD.
  Uri? get shareLink {
    final code = state?.code;
    if (code == null) return null;
    final server = Uri.tryParse(serverUrl);
    if (server == null || server.host.isEmpty) return null;
    return Uri(
      scheme: server.scheme == 'wss' ? 'https' : 'http',
      host: server.host,
      port: server.hasPort ? server.port : null,
      path: '/r/$code',
    );
  }

  /// Verarbeitet einen Einladungslink arsch://join?code=ABCD&server=ws://...
  void handleLink(Uri uri) {
    if (uri.scheme != 'arsch' || uri.host != 'join') return;
    final code = (uri.queryParameters['code'] ?? '').trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{4}$').hasMatch(code)) return;
    final current = state;
    if (current != null || _code != null) {
      if (current?.code != code && _code != code) {
        onMessage
            ?.call('Verlasse zuerst deinen Raum, um Raum $code beizutreten.');
      }
      return;
    }
    final server = uri.queryParameters['server'];
    if (server != null && server.startsWith(RegExp(r'wss?://'))) {
      setServerUrl(server);
    }
    // Nicht sofort beitreten: Der Raum-Code kommt ins Eingabefeld, der
    // Spieler tippt selbst auf „Beitreten“.
    pendingCode = code;
    onMessage?.call(name.isEmpty
        ? 'Raum $code: Gib deinen Namen ein und tippe auf „Beitreten“.'
        : 'Raum $code: Tippe auf „Beitreten“.');
    notifyListeners();
  }

  void addBot() => _send({'type': 'addBot'});
  void removeBot(int seat) => _send({'type': 'removeBot', 'seat': seat});
  void startGame() => _send({'type': 'start'});
  void playCards(List<PlayingCard> cards) => _send({
        'type': 'play',
        'cards': [for (final c in cards) c.id]
      });
  void pass() => _send({'type': 'pass'});
  void discard(List<PlayingCard> cards) => _send({
        'type': 'discard',
        'cards': [for (final c in cards) c.id]
      });
  void nextRound() => _send({'type': 'nextRound'});
  void newGame() => _send({'type': 'newGame'});
  void abortGame() => _send({'type': 'abort'});

  /// Raum verlassen und zum Startbildschirm zurückkehren.
  void leave() {
    _send({'type': 'leave'});
    _reset();
    notifyListeners();
  }

  void _reset() {
    _generation++;
    _retry?.cancel();
    _channel?.sink.close();
    _channel = null;
    _code = null;
    _token = null;
    _prefs?.remove('code');
    _prefs?.remove('token');
    state = null;
    busy = false;
    reconnecting = false;
    lastResult = null;
    showResult = false;
    onTurnOver?.call();
  }

  void _send(Map<String, dynamic> message) {
    _channel?.sink.add(jsonEncode(message));
  }

  Future<void> _open(Map<String, dynamic> firstMessage) async {
    final gen = ++_generation;
    _retry?.cancel();
    _channel?.sink.close();
    _channel = null;
    try {
      final channel = WebSocketChannel.connect(Uri.parse(serverUrl));
      await channel.ready.timeout(const Duration(seconds: 8));
      if (gen != _generation) {
        channel.sink.close();
        return;
      }
      _channel = channel;
      channel.stream.listen(
        (data) => _onData(gen, data),
        onDone: () => _onClosed(gen),
        onError: (_) => _onClosed(gen),
        cancelOnError: true,
      );
      channel.sink.add(jsonEncode(firstMessage));
    } catch (_) {
      _onClosed(gen);
    }
  }

  void _onData(int gen, dynamic data) {
    if (gen != _generation || data is! String) return;
    handleMessage(jsonDecode(data) as Map<String, dynamic>);
  }

  /// Verarbeitet eine Nachricht des Servers (öffentlich für Tests).
  @visibleForTesting
  void handleMessage(Map<String, dynamic> msg) {
    switch (msg['type']) {
      case 'joined':
        _code = msg['code'] as String;
        _token = msg['token'] as String;
        _prefs?.setString('code', _code!);
        _prefs?.setString('token', _token!);
        onJoined?.call();
      case 'state':
        final previous = state;
        final wasMyTurn = previous?.isMyTurn ?? false;
        final next = TableState.fromJson(msg);
        state = next;
        // Runde gerade zu Ende: Ergebnis festhalten und anzeigen.
        final wasOver = previous != null && previous.roundFinished;
        if (next.roundFinished && !wasOver) {
          lastResult = next;
          showResult = true;
        }
        if (next.isMyTurn) {
          final oldDeadline = previous?.turnDeadline;
          final newDeadline = next.turnDeadline;
          final deadlineMoved = oldDeadline == null ||
              newDeadline == null ||
              newDeadline.difference(oldDeadline).inSeconds.abs() > 10;
          if (!wasMyTurn || deadlineMoved) {
            onMyTurn?.call(next, isNew: !wasMyTurn);
          }
        } else if (wasMyTurn) {
          onTurnOver?.call();
        }
        busy = false;
        reconnecting = false;
        notifyListeners();
      case 'error':
        busy = false;
        onMessage?.call(msg['message'] as String? ?? 'Unbekannter Fehler.');
        if (msg['reason'] == 'rejoin_failed' || state == null) {
          // Kein gültiger Raum: Verbindung wieder abbauen.
          _reset();
        }
        notifyListeners();
    }
  }

  void _onClosed(int gen) {
    if (gen != _generation) return;
    _generation++;
    _channel = null;
    busy = false;
    if (_code != null && _token != null) {
      // Wir sitzen an einem Tisch: automatisch neu verbinden.
      reconnecting = true;
      _retry = Timer(const Duration(seconds: 2), () => _open(_rejoinMessage()));
    } else {
      state = null;
      onMessage?.call('Keine Verbindung zum Server ($serverUrl).');
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _generation++;
    _retry?.cancel();
    _channel?.sink.close();
    super.dispose();
  }
}
