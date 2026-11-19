import 'package:material_ui/material_ui.dart';

import '../game_client.dart';

/// Startbildschirm: Namen eingeben, Spiel erstellen oder beitreten.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.client});

  final GameClient client;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final _name = TextEditingController(text: widget.client.name);
  late final _server = TextEditingController(text: widget.client.serverUrl);
  final _code = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _server.dispose();
    _code.dispose();
    super.dispose();
  }

  bool _checkName() {
    if (_name.text.trim().isNotEmpty) return true;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          const SnackBar(content: Text('Bitte gib zuerst deinen Namen ein.')));
    return false;
  }

  void _create() {
    if (!_checkName()) return;
    widget.client.setServerUrl(_server.text);
    widget.client.createRoom(_name.text);
  }

  void _join() {
    if (!_checkName()) return;
    if (_code.text.trim().length != 4) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text('Der Raum-Code hat vier Buchstaben.')));
      return;
    }
    widget.client.setServerUrl(_server.text);
    widget.client.joinRoom(_code.text, _name.text);
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    final theme = Theme.of(context);
    // Einladungslink ohne Namen: Code und Server übernehmen.
    final pending = client.pendingCode;
    if (pending != null) {
      client.pendingCode = null;
      _code.text = pending;
      _server.text = client.serverUrl;
    }

    if (client.reconnecting) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Verbinde mit laufendem Spiel …'),
              const SizedBox(height: 16),
              TextButton(
                  onPressed: client.leave, child: const Text('Abbrechen')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset(
                    'assets/logo.png',
                    height: 140,
                    semanticLabel: 'Arsch-Logo',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Arsch',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displayLarge
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  Text(
                    'Das Kartenspiel für 4 oder 5 Spieler',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 40),
                  TextField(
                    controller: _name,
                    maxLength: 16,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Dein Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: client.busy ? null : _create,
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Neues Spiel erstellen'),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _code,
                          maxLength: 4,
                          textCapitalization: TextCapitalization.characters,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Raum-Code',
                            border: OutlineInputBorder(),
                            counterText: '',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.tonal(
                        onPressed: client.busy ? null : _join,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text('Beitreten'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (client.busy)
                    const Center(child: CircularProgressIndicator()),
                  ExpansionTile(
                    title: const Text('Server-Einstellungen'),
                    tilePadding: EdgeInsets.zero,
                    children: [
                      TextField(
                        controller: _server,
                        autocorrect: false,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'Server-Adresse',
                          hintText: 'wss://mein-server.de',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
