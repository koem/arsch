/// Hilfen für die Server-Tests: echten Server als Prozess starten und per
/// WebSocket mitspielen.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Das kompilierte Server-Programm. Wird nur neu gebaut, wenn sich der
/// Quellcode (Server oder Regeln) seit dem letzten Bauen geändert hat.
Future<String> serverExe() async {
  final out = File('${Directory.systemTemp.path}/arsch_server_test/arsch-server');
  final sources = [
    ...Directory('bin').listSync(recursive: true),
    ...Directory('../shared/lib').listSync(recursive: true),
  ].whereType<File>();
  final newest = sources
      .map((f) => f.lastModifiedSync())
      .reduce((a, b) => a.isAfter(b) ? a : b);
  if (out.existsSync() && out.lastModifiedSync().isAfter(newest)) {
    return out.path;
  }
  out.parent.createSync(recursive: true);
  // Testdateien laufen parallel: erst in eine eigene Datei bauen, dann
  // umbenennen (atomar), damit sich die Läufe nicht in die Quere kommen.
  final tmp = '${out.path}.$pid.${DateTime.now().microsecondsSinceEpoch}';
  final result = await Process.run(Platform.resolvedExecutable,
      ['compile', 'exe', 'bin/server.dart', '-o', tmp]);
  if (result.exitCode != 0) {
    throw StateError('Server bauen fehlgeschlagen:\n${result.stderr}');
  }
  File(tmp).renameSync(out.path);
  return out.path;
}

Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

/// Ein laufender Server-Prozess mit eigenem Port und Datenordner.
class TestServer {
  TestServer._(this.port, this.dataDir, this.env);

  final int port;
  final Directory dataDir;
  final Map<String, String> env;
  late Process _process;
  final output = StringBuffer();

  String get wsUrl => 'ws://localhost:$port';
  String get httpUrl => 'http://localhost:$port';

  /// [env]: zusätzliche Umgebungsvariablen, z.B. TURN_TIMEOUT.
  static Future<TestServer> start({Map<String, String> env = const {}}) async {
    final dir = await Directory.systemTemp.createTemp('arsch_test_data');
    final server = TestServer._(await _freePort(), dir, env);
    await server._launch();
    return server;
  }

  Future<void> _launch() async {
    _process = await Process.start(await serverExe(), [], environment: {
      ...env,
      'PORT': '$port',
      'DATA_DIR': dataDir.path,
    });
    final ready = Completer<void>();
    _process.stdout.transform(utf8.decoder).listen((line) {
      output.write(line);
      if (line.contains('läuft auf Port') && !ready.isCompleted) {
        ready.complete();
      }
    });
    _process.stderr.transform(utf8.decoder).listen(output.write);
    await ready.future.timeout(const Duration(seconds: 30));
  }

  /// Beendet den Server ([signal] SIGKILL = ohne Speichern beim Beenden).
  Future<void> stop({ProcessSignal signal = ProcessSignal.sigterm}) async {
    _process.kill(signal);
    await _process.exitCode;
  }

  /// Neustart mit denselben Daten.
  Future<void> restart({ProcessSignal signal = ProcessSignal.sigterm}) async {
    await stop(signal: signal);
    await _launch();
  }

  Future<void> dispose() async {
    _process.kill(ProcessSignal.sigkill);
    await _process.exitCode;
    if (dataDir.existsSync()) dataDir.deleteSync(recursive: true);
  }

  /// Anzahl der Räume laut Statusseite.
  Future<int> roomCount() async => int.parse((await get('/')).split(': ').last.trim());

  Future<String> get(String path, {Map<String, String> headers = const {}}) async {
    final (_, body) = await getWithStatus(path, headers: headers);
    return body;
  }

  Future<(int, String)> getWithStatus(String path,
      {Map<String, String> headers = const {}}) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse('$httpUrl$path'));
      headers.forEach(request.headers.set);
      final response = await request.close();
      return (response.statusCode, await response.transform(utf8.decoder).join());
    } finally {
      client.close();
    }
  }
}

/// Ein Spieler bzw. Zuschauer, der per WebSocket verbunden ist.
class Client {
  Client._(this.ws) {
    ws.listen(_onData, onError: (_) {}, onDone: () => closed = true);
  }

  final WebSocket ws;
  Map<String, dynamic>? last;
  String? code;
  String? token;
  bool closed = false;
  final errors = <String>[];
  final _states = StreamController<Map<String, dynamic>>.broadcast();

  /// Alle weiteren Spielstände.
  Stream<Map<String, dynamic>> get states => _states.stream;

  static Future<Client> connect(TestServer server, Map<String, dynamic> first) async {
    final client = Client._(await WebSocket.connect(server.wsUrl));
    client.send(first);
    await settle();
    return client;
  }

  static Future<Client> create(TestServer s, String name) =>
      connect(s, {'type': 'create', 'name': name});

  static Future<Client> join(TestServer s, String code, String name) =>
      connect(s, {'type': 'join', 'code': code, 'name': name});

  void _onData(dynamic data) {
    final m = jsonDecode(data as String) as Map<String, dynamic>;
    switch (m['type']) {
      case 'joined':
        code = m['code'] as String;
        token = m['token'] as String;
      case 'state':
        last = m;
        if (!_states.isClosed) _states.add(m);
      case 'error':
        errors.add(m['message'] as String);
    }
  }

  void send(Map<String, dynamic> message) => ws.add(jsonEncode(message));

  /// Wartet auf einen Spielstand, für den [test] zutrifft (auch den aktuellen).
  Future<Map<String, dynamic>> waitFor(bool Function(Map<String, dynamic>) test,
      {Duration timeout = const Duration(seconds: 20)}) {
    final current = last;
    if (current != null && test(current)) return Future.value(current);
    return states.firstWhere(test).timeout(timeout);
  }

  List<String> get names => [for (final p in last!['players'] as List) p['name'] as String];

  Future<void> close() async {
    await ws.close();
    await _states.close();
  }
}

Future<void> settle([int ms = 300]) => Future.delayed(Duration(milliseconds: ms));

List<int> handOf(Map<String, dynamic> s) => (s['hand'] as List).cast<int>()..sort();

bool myTurn(Map<String, dynamic> s) => s['current'] == s['you'];

bool isBot(Map<String, dynamic> s, int seat) =>
    (s['players'] as List)[seat]['bot'] as bool;

/// Einfacher Mensch: spielt die niedrigste Karte aus, sonst schiebt er.
void simpleMove(Client c, Map<String, dynamic> s) {
  final hand = handOf(s);
  (s['pile'] as List).isEmpty
      ? c.send({'type': 'play', 'cards': [hand.first]})
      : c.send({'type': 'pass'});
}

/// Spielt wie die Bots: kleinste erlaubte Kombination, sonst schieben.
void botLikeMove(Client c, Map<String, dynamic> s) {
  final pile = (s['pile'] as List).cast<int>();
  final byRank = <int, List<int>>{};
  for (final id in handOf(s)) {
    byRank.putIfAbsent(id ~/ 4, () => []).add(id);
  }
  final ranks = byRank.keys.toList()..sort();
  if (pile.isEmpty) {
    c.send({'type': 'play', 'cards': byRank[ranks.first]});
    return;
  }
  final options =
      ranks.where((r) => r > pile.first ~/ 4 && byRank[r]!.length >= pile.length);
  options.isEmpty
      ? c.send({'type': 'pass'})
      : c.send({
          'type': 'play',
          'cards': byRank[options.first]!.take(pile.length).toList()
        });
}

/// Lässt [c] bei jedem eigenen Zug automatisch [move] spielen.
StreamSubscription<void> autoPlay(
    Client c, void Function(Client, Map<String, dynamic>) move) {
  void act(Map<String, dynamic> s) {
    if (s['phase'] == 'playing' && myTurn(s)) {
      Future.delayed(const Duration(milliseconds: 30), () => move(c, s));
    }
  }

  final sub = c.states.listen(act);
  if (c.last != null) act(c.last!);
  return sub;
}
