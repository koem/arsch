import 'dart:math';

import 'package:arsch_shared/arsch_shared.dart';
import 'package:material_ui/material_ui.dart';

import '../game_client.dart';

String _signed(int n) => n > 0 ? '+$n' : '$n';

/// Ergebnis der letzten Runde bzw. des Spiels. Bleibt stehen, bis der Spieler
/// es schließt – auch wenn die nächste Runde oder ein neues Spiel schon läuft.
class ResultOverlay extends StatelessWidget {
  const ResultOverlay({super.key, required this.client});

  final GameClient client;

  @override
  Widget build(BuildContext context) {
    final result = client.lastResult!;
    final live = client.state;
    final theme = Theme.of(context);
    final n = result.players.length;
    final gameOver = result.phase == 'gameOver';
    final ranked = [...result.players]
      ..sort((a, b) => (a.place ?? n).compareTo(b.place ?? n));
    final best = result.players.map((p) => p.score).reduce(max);
    final winners = result.players
        .where((p) => p.score == best)
        .map((p) => p.name)
        .join(' und ');

    // Was man von hier aus noch tun kann, hängt vom aktuellen Stand ab.
    final stillHere =
        live != null && !live.isSpectator && live.code == result.code;
    final canNextRound =
        stillHere && live.phase == 'roundOver' && live.round == result.round;
    final canBackToLobby = stillHere && live.phase == 'gameOver';
    final movedOn = live != null && !live.roundFinished;

    const header = TextStyle(fontSize: 12, color: Colors.white60);
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black54,
        child: Center(
          child: Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    gameOver
                        ? 'Spiel vorbei!'
                        : 'Runde ${result.round} beendet',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  if (gameOver) ...[
                    const SizedBox(height: 4),
                    Text('Sieg für $winners',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(color: Colors.amber)),
                  ],
                  const SizedBox(height: 16),
                  const Row(
                    children: [
                      SizedBox(width: 96),
                      Expanded(child: SizedBox()),
                      SizedBox(
                          width: 44,
                          child: Text('Runde',
                              textAlign: TextAlign.right, style: header)),
                      SizedBox(
                          width: 58,
                          child: Text('Gesamt',
                              textAlign: TextAlign.right, style: header)),
                      SizedBox(
                          width: 48,
                          child: Text('Swaps',
                              textAlign: TextAlign.right, style: header)),
                    ],
                  ),
                  for (final p in ranked)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 96,
                            child: Text(
                              p.place == null ? '' : titleFor(p.place!, n),
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.fade,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(p.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ),
                                if (p.roundSwaps > 0) ...[
                                  const SizedBox(width: 4),
                                  Text(p.swapStars,
                                      style:
                                          const TextStyle(color: Colors.amber)),
                                ],
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 44,
                            child: Text(
                              p.place == null ? '' : _signed(p.roundPoints),
                              textAlign: TextAlign.right,
                            ),
                          ),
                          SizedBox(
                            width: 58,
                            child: Text(
                              _signed(p.score),
                              textAlign: TextAlign.right,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          SizedBox(
                            width: 48,
                            child: Text(
                              p.swaps == 0 ? '–' : '${p.swaps} ★',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  color: p.swaps == 0 ? null : Colors.amber),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (result.players.any((p) => p.roundSwaps > 0)) ...[
                    const SizedBox(height: 8),
                    Text(
                        '★ Swap: +$swapBonus Punkt extra  ·  '
                        '★★ Doppel-Swap: +${2 * swapBonus}',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.amber)),
                  ],
                  if (movedOn) ...[
                    const SizedBox(height: 12),
                    Text(
                      live.inLobby
                          ? 'Ihr seid inzwischen im Warteraum.'
                          : 'Runde ${live.round} läuft schon.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (canNextRound)
                    FilledButton(
                      onPressed: () {
                        client.dismissResult();
                        client.nextRound();
                      },
                      child: const Text('Nächste Runde'),
                    )
                  else if (canBackToLobby)
                    FilledButton(
                      onPressed: () {
                        client.dismissResult();
                        client.newGame();
                      },
                      child: const Text('Zurück zum Warteraum'),
                    ),
                  TextButton(
                    onPressed: client.dismissResult,
                    child: const Text('Schließen'),
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
