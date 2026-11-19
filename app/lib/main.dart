import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'game_client.dart';
import 'screens/game_screen.dart';
import 'screens/home_screen.dart';
import 'screens/lobby_screen.dart';
import 'turn_alert.dart';
import 'widgets/result_overlay.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const ArschApp());
}

class ArschApp extends StatefulWidget {
  const ArschApp({super.key});

  @override
  State<ArschApp> createState() => _ArschAppState();
}

class _ArschAppState extends State<ArschApp> {
  final _client = GameClient();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final _turnAlert = TurnAlert();
  StreamSubscription<Uri>? _links;
  String? _lastLink;

  @override
  void initState() {
    super.initState();
    _client.onMessage = (message) {
      _messengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    };
    _client.onMyTurn = _turnAlert.myTurn;
    _client.onTurnOver = _turnAlert.turnOver;
    _client.onJoined = _turnAlert.requestPermission;
    _start();
  }

  Future<void> _start() async {
    await _turnAlert.init();
    await _client.init();
    // Einladungslinks (arsch://join?...), beim Start und während die App läuft.
    final appLinks = AppLinks();
    _links = appLinks.uriLinkStream.listen(_onLink);
    final initial = await appLinks.getInitialLink();
    if (initial != null) _onLink(initial);
  }

  void _onLink(Uri uri) {
    // Der Startlink kann über beide Wege ankommen – nur einmal behandeln.
    if (uri.toString() == _lastLink) return;
    _lastLink = uri.toString();
    _client.handleLink(uri);
  }

  @override
  void dispose() {
    _links?.cancel();
    _turnAlert.dispose();
    _client.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Arsch',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _messengerKey,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D32),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0F3D24),
      ),
      home: ListenableBuilder(
        listenable: _client,
        builder: (context, _) {
          // Erst die gespeicherten Einstellungen (Name, Server) laden.
          if (!_client.initialized) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          final state = _client.state;
          final Widget screen = state == null
              ? HomeScreen(client: _client)
              : state.inLobby
                  ? LobbyScreen(client: _client)
                  : GameScreen(client: _client);
          // Das Ergebnis der letzten Runde bleibt über allem stehen, bis der
          // Spieler es schließt.
          return Stack(
            children: [
              screen,
              if (_client.showResult && _client.lastResult != null)
                ResultOverlay(client: _client),
            ],
          );
        },
      ),
    );
  }
}
