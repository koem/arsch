import 'package:material_ui/material_ui.dart';

import '../game_client.dart';
import '../widgets/share_room.dart';

/// Warteraum: zeigt den Raum-Code und wer schon da ist.
class LobbyScreen extends StatelessWidget {
  const LobbyScreen({super.key, required this.client});

  final GameClient client;

  @override
  Widget build(BuildContext context) {
    final state = client.state!;
    final theme = Theme.of(context);
    final isHost = state.you == 0;
    final count = state.players.length;
    final canStart = count >= 4;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Warteraum'),
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Raum verlassen',
          onPressed: client.leave,
        ),
        actions: [ShareRoomButton(client: client)],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Raum-Code',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium),
              SelectableText(
                state.code,
                textAlign: TextAlign.center,
                style: theme.textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 12,
                ),
              ),
              Text(
                'Gib diesen Code an deine Mitspieler weiter\noder teile den Link (oben rechts).',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              Text(
                'Spieler ($count von 5)'
                '${state.spectatorCount > 0 ? '  ·  ${state.spectatorCount} schauen zu' : ''}',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: [
                    for (var i = 0; i < count; i++)
                      Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            child: state.players[i].isBot
                                ? const Icon(Icons.smart_toy_outlined)
                                : Text('${i + 1}'),
                          ),
                          title: Text(state.players[i].name),
                          subtitle: i == 0
                              ? const Text('Gastgeber')
                              : state.players[i].isBot
                                  ? const Text('Computer')
                                  : null,
                          trailing: i == state.you
                              ? const Text('Du')
                              : isHost && state.players[i].isBot
                                  ? IconButton(
                                      icon: const Icon(Icons.close),
                                      tooltip: 'Bot entfernen',
                                      onPressed: () => client.removeBot(i),
                                    )
                                  : null,
                        ),
                      ),
                    if (isHost && count < 5)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: OutlinedButton.icon(
                          onPressed: client.addBot,
                          icon: const Icon(Icons.smart_toy_outlined),
                          label: const Text('Bot hinzufügen'),
                        ),
                      ),
                  ],
                ),
              ),
              if (client.reconnecting)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text('Verbindung verloren – verbinde neu …',
                      textAlign: TextAlign.center),
                ),
              if (state.isSpectator)
                const Text(
                  'Der Tisch ist voll – du schaust zu.\n'
                  'Wird ein Platz frei, setzt du dich automatisch.',
                  textAlign: TextAlign.center,
                )
              else ...[
                Text(
                  canStart
                      ? (count == 4
                          ? 'Ihr könnt zu viert starten – zu fünft ist es am schönsten.'
                          : 'Alle da!')
                      : 'Es fehlen noch ${4 - count} Spieler (mindestens 4).'
                          '${isHost ? '\nLade jemanden ein oder füge Bots hinzu.' : ''}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                if (isHost)
                  FilledButton(
                    onPressed: canStart ? client.startGame : null,
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Spiel starten'),
                    ),
                  )
                else
                  const Text(
                    'Der Gastgeber startet das Spiel.',
                    textAlign: TextAlign.center,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
