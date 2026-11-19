import 'dart:async';
import 'dart:math';

import 'package:arsch_shared/arsch_shared.dart';
import 'package:material_ui/material_ui.dart';

import '../game_client.dart';
import '../models.dart';
import '../widgets/card_widget.dart';
import '../widgets/share_room.dart';

String _signed(int n) => n > 0 ? '+$n' : '$n';

String _cardCount(int n) => n == 1 ? '1 Karte' : '$n Karten';

/// Der Spieltisch.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.client});

  final GameClient client;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  /// IDs der auf der Hand ausgewählten Karten.
  final Set<int> _selected = {};

  /// Aktualisiert die Anzeige der restlichen Bedenkzeit.
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  void _toggle(PlayingCard card, TableState s) {
    setState(() {
      if (_selected.remove(card.id)) return;
      if (s.isDiscarding) {
        // Beim Zurücklegen: zwei beliebige Karten; eine dritte ersetzt die
        // zuerst gewählte.
        if (_selected.length >= discardCount) _selected.remove(_selected.first);
        _selected.add(card.id);
        return;
      }
      // Nur gleiche Werte können zusammen gelegt werden: eine Karte mit
      // anderem Wert ersetzt die bisherige Auswahl.
      final othersDiffer = s.hand
          .where((h) => _selected.contains(h.id))
          .any((h) => h.rank != card.rank);
      if (othersDiffer) _selected.clear();
      _selected.add(card.id);
    });
  }

  Future<void> _confirmLeave() async {
    if (widget.client.state?.isSpectator ?? true) {
      widget.client.leave();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Spiel verlassen?'),
        content:
            const Text('Die anderen können ohne dich nicht weiterspielen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Bleiben'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Verlassen'),
          ),
        ],
      ),
    );
    if (leave == true) widget.client.leave();
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    final s = client.state!;
    final n = s.players.length;
    final theme = Theme.of(context);

    _selected.removeWhere((id) => !s.hand.any((c) => c.id == id));
    final selectedCards =
        s.hand.where((c) => _selected.contains(c.id)).toList();
    final canPlay = s.isMyTurn &&
        s.isPlaying &&
        validatePlay(selectedCards, s.pile) == null;
    // Wer schon Karten ausgewählt hat, will legen – nicht schieben.
    final canPass =
        s.isMyTurn && s.isPlaying && s.pile.isNotEmpty && _selected.isEmpty;
    final mustDiscard = s.isMyTurn && s.isDiscarding;
    final canDiscard = mustDiscard && selectedCards.length == discardCount;
    final offline = s.players.where((p) => !p.connected).toList();
    // Spieler sehen die anderen im Uhrzeigersinn ab dem linken Nachbarn,
    // Zuschauer sehen alle.
    final shownSeats = s.isSpectator
        ? [for (var i = 0; i < n; i++) i]
        : [for (var i = 1; i < n; i++) (s.you + i) % n];

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Kopfzeile
                Padding(
                  padding: const EdgeInsets.only(left: 16, right: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Raum ${s.code}  ·  Runde ${s.round}'
                          '${s.spectatorCount > 0 ? '  ·  ${s.spectatorCount} 👀' : ''}',
                          style: theme.textTheme.titleSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ShareRoomButton(client: client),
                      IconButton(
                        icon: const Icon(Icons.logout),
                        tooltip: s.isSpectator
                            ? 'Zuschauen beenden'
                            : 'Spiel verlassen',
                        onPressed: _confirmLeave,
                      ),
                    ],
                  ),
                ),
                // Mitspieler, im Uhrzeigersinn ab dem linken Nachbarn
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final seat in shownSeats)
                        Expanded(
                          child: _PlayerChip(
                            player: s.players[seat],
                            active: s.roundRunning && s.current == seat,
                            playerCount: n,
                          ),
                        ),
                    ],
                  ),
                ),
                // Was seit dem eigenen letzten Zug passiert ist
                if (s.roundRunning && s.recent.isNotEmpty)
                  _RecentMoves(state: s),
                // Tischmitte
                Expanded(child: _TableCenter(state: s)),
                if (client.reconnecting || offline.isNotEmpty)
                  _ConnectionBanner(
                    text: client.reconnecting
                        ? 'Verbindung verloren – verbinde neu …'
                        : '${offline.map((p) => p.name).join(', ')} '
                            '${offline.length == 1 ? 'ist' : 'sind'} getrennt. '
                            'Warte auf Rückkehr …',
                    onAbort: client.reconnecting || s.isSpectator
                        ? null
                        : client.abortGame,
                  ),
                // Eigener Bereich
                _TurnBanner(state: s),
                const SizedBox(height: 8),
                if (s.isSpectator)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Du schaust zu.',
                      style: theme.textTheme.titleMedium,
                    ),
                  )
                else if (s.me.place == null && s.roundRunning) ...[
                  if (mustDiscard)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (s.pickedUp.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('Aus der Mitte aufgenommen: ',
                                      style: theme.textTheme.bodyMedium),
                                  for (final c in s.pickedUp)
                                    _MiniCard(card: c),
                                ],
                              ),
                            ),
                          FilledButton(
                            onPressed: canDiscard
                                ? () {
                                    client.discard(selectedCards);
                                    setState(_selected.clear);
                                  }
                                : null,
                            child: Text(selectedCards.length == discardCount
                                ? 'Diese $discardCount Karten zurücklegen'
                                : 'Wähle $discardCount Karten zum Zurücklegen '
                                    '(${selectedCards.length}/$discardCount)'),
                          ),
                        ],
                      ),
                    )
                  else if (s.isPlaying)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: canPass
                                  ? () {
                                      setState(_selected.clear);
                                      client.pass();
                                    }
                                  : null,
                              child: const Text('Ich schiebe'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: canPlay
                                  ? () {
                                      client.playCards(selectedCards);
                                      setState(_selected.clear);
                                    }
                                  : null,
                              child: const Text('Legen'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: _Hand(
                      hand: s.hand,
                      selected: _selected,
                      onTap: (card) => _toggle(card, s),
                    ),
                  ),
                ] else if (s.me.place != null)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Du bist ${titleFor(s.me.place!, n)}!',
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                // Runde vorbei und Ergebnis geschlossen: weiter oder Ergebnis zeigen.
                if (s.roundFinished && !client.showResult)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        if (client.lastResult != null)
                          Expanded(
                            child: OutlinedButton(
                              onPressed: client.reopenResult,
                              child: const Text('Ergebnis'),
                            ),
                          ),
                        if (!s.isSpectator) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: s.phase == 'gameOver'
                                  ? client.newGame
                                  : client.nextRound,
                              child: Text(s.phase == 'gameOver'
                                  ? 'Zum Warteraum'
                                  : 'Nächste Runde'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (!s.isSpectator)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Text(
                      '${s.me.name}  ·  '
                      '${s.me.place == null ? '${_cardCount(s.me.cardCount)}  ·  ' : ''}'
                      '${_signed(s.me.score)} Punkte',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Anzeige eines Mitspielers am oberen Rand.
class _PlayerChip extends StatelessWidget {
  const _PlayerChip({
    required this.player,
    required this.active,
    required this.playerCount,
  });

  final PlayerInfo player;
  final bool active;
  final int playerCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial =
        player.name.isEmpty ? '?' : player.name.characters.first.toUpperCase();
    final place = player.place;
    return Opacity(
      opacity: player.connected ? 1 : 0.45,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: active ? Colors.amber : Colors.transparent,
                width: 3,
              ),
            ),
            child: Badge(
              // Anzahl der Handkarten, solange der Spieler noch Karten hat.
              isLabelVisible: place == null,
              label: Text('${player.cardCount}'),
              backgroundColor: Colors.amber.shade700,
              textColor: Colors.black,
              offset: const Offset(4, -4),
              child: CircleAvatar(
                radius: 22,
                backgroundColor: Colors.white24,
                child: player.isBot
                    ? const Icon(Icons.smart_toy_outlined)
                    : Text(initial,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
          Text(
            player.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge,
          ),
          Text(
            place != null
                ? '${titleFor(place, playerCount)}${player.roundSwaps > 0 ? ' ${player.swapStars}' : ''}'
                : !player.connected
                    ? '${player.cardCount} · getrennt'
                    : _cardCount(player.cardCount),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: place != null ? Colors.amber : null,
            ),
          ),
          Text('${_signed(player.score)} Pkt.',
              style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Tischmitte: zuletzt gelegte Karten, letzter Spielzug, Restkarten.
class _TableCenter extends StatelessWidget {
  const _TableCenter({required this.state});

  final TableState state;

  String? _lastActionText() {
    final seat = state.lastSeat;
    if (seat == null) return null;
    final who = seat == state.you ? 'Du' : state.players[seat].name;
    if (state.lastCards.isEmpty) {
      return seat == state.you ? 'Du schiebst.' : '$who: „Ich schiebe“';
    }
    final verb = seat == state.you ? 'legst' : 'legt';
    return '$who $verb ${state.lastCards.length}× ${state.lastCards.first.rank.label}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trickOver = state.pile.isEmpty && state.previousPile.isNotEmpty;
    final shown = trickOver ? state.previousPile : state.pile;
    final lastText = _lastActionText();
    final pileOwner = state.pilePlayer;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (lastText != null)
          Text(lastText, style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        SizedBox(
          height: 70 * cardAspect,
          child: shown.isEmpty
              ? Center(
                  child: Text('Der Tisch ist leer.',
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(color: Colors.white54)),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final card in shown)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child:
                            CardFace(card: card, width: 70, dimmed: trickOver),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        Text(
          trickOver
              ? 'Stich beendet – es wird neu ausgespielt.'
              : pileOwner != null
                  ? 'Gelegt von ${pileOwner == state.you ? 'dir' : state.players[pileOwner].name}'
                  : '',
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
        ),
        if (state.middleCount > 0) ...[
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < state.middleCount; i++)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2),
                  child: CardBack(width: 26),
                ),
              const SizedBox(width: 8),
              Text(
                state.middleCount == 1
                    ? '1 Karte verdeckt'
                    : '${state.middleCount} Karten verdeckt',
                style:
                    theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Restliche Bedenkzeit, z.B. „noch 23 Std. Zeit“ – danach wird geschoben.
String? _timeLeft(DateTime? deadline) {
  if (deadline == null) return null;
  final left = deadline.difference(DateTime.now());
  if (left.inHours >= 1) return 'noch ${left.inHours} Std. Zeit';
  final minutes = max(1, (left.inSeconds / 60).ceil());
  return 'noch $minutes Min. Zeit';
}

/// Zeigt an, wer gerade dran ist.
class _TurnBanner extends StatelessWidget {
  const _TurnBanner({required this.state});

  final TableState state;

  @override
  Widget build(BuildContext context) {
    if (!state.roundRunning) return const SizedBox.shrink();
    final String text;
    if (state.isDiscarding) {
      text = state.isMyTurn
          ? 'Du bist Arsch: Du hast die $discardCount Karten aus der Mitte. '
              'Lege $discardCount Karten zurück.'
          : '${state.players[state.current].name} (Arsch) legt '
              '$discardCount Karten zurück in die Mitte …';
    } else if (state.isMyTurn) {
      final k = state.pile.length;
      text = k == 0
          ? 'Du spielst aus!'
          : k == 1
              ? 'Du bist dran: eine höhere Karte legen oder schieben'
              : 'Du bist dran: $k höhere Karten legen oder schieben';
    } else {
      text = '${state.players[state.current].name} ist dran …';
    }
    final left = _timeLeft(state.turnDeadline);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: state.isMyTurn ? Colors.amber : Colors.black26,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        left == null ? text : '$text\n$left',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: state.isMyTurn ? Colors.black : Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({required this.text, this.onAbort});

  final String text;
  final VoidCallback? onAbort;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF8E2A2A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(child: Text(text)),
          if (onAbort != null)
            TextButton(onPressed: onAbort, child: const Text('Abbrechen')),
        ],
      ),
    );
  }
}

/// Die eigenen Handkarten, aufgefächert. Ausgewählte Karten stehen höher.
class _Hand extends StatelessWidget {
  const _Hand({
    required this.hand,
    required this.selected,
    required this.onTap,
  });

  final List<PlayingCard> hand;
  final Set<int> selected;
  final void Function(PlayingCard card) onTap;

  @override
  Widget build(BuildContext context) {
    const cardWidth = 62.0;
    const lift = 18.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = hand.length;
        final step = count <= 1
            ? 0.0
            : min(cardWidth + 6,
                (constraints.maxWidth - cardWidth) / (count - 1));
        final total = count == 0 ? 0.0 : cardWidth + step * (count - 1);
        final left = (constraints.maxWidth - total) / 2;
        return SizedBox(
          width: constraints.maxWidth,
          height: cardWidth * cardAspect + lift,
          child: Stack(
            children: [
              for (var i = 0; i < count; i++)
                AnimatedPositioned(
                  key: ValueKey(hand[i].id),
                  duration: const Duration(milliseconds: 120),
                  left: left + i * step,
                  top: selected.contains(hand[i].id) ? 0 : lift,
                  child: GestureDetector(
                    onTap: () => onTap(hand[i]),
                    child: CardFace(
                      card: hand[i],
                      width: cardWidth,
                      selected: selected.contains(hand[i].id),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Was seit dem eigenen letzten Zug gelegt bzw. geschoben wurde.
class _RecentMoves extends StatelessWidget {
  const _RecentMoves({required this.state});

  final TableState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall?.copyWith(color: Colors.white70);
    final rows = <Widget>[];
    for (final m in state.recent) {
      final who = m.seat == state.you ? 'Du' : state.players[m.seat].name;
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 96,
              child: Text(who,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium),
            ),
            if (m.isPass)
              Text(m.timedOut ? 'schiebt (Zeit abgelaufen)' : 'schiebt',
                  style: small)
            else ...[
              for (final c in m.cards) _MiniCard(card: c),
              if (m.timedOut) Text('(Zeit abgelaufen)', style: small),
            ],
          ],
        ),
      ));
      if (m.endsTrick) {
        rows.add(Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(children: [
            const Expanded(child: Divider(endIndent: 8)),
            Text('Stich vorbei', style: small),
            const Expanded(child: Divider(indent: 8)),
          ]),
        ));
      }
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state.isSpectator ? 'Letzte Züge' : 'Seit deinem letzten Zug',
            style: theme.textTheme.labelMedium?.copyWith(color: Colors.amber),
          ),
          const SizedBox(height: 2),
          // Höchstens ein paar Zeilen hoch; die neuesten Züge stehen unten.
          ConstrainedBox(
            constraints:
                BoxConstraints(maxHeight: state.isSpectator ? 320 : 132),
            child: SingleChildScrollView(
              reverse: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: rows,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kleine Karte für das Zugprotokoll, z.B. „D♥“.
class _MiniCard extends StatelessWidget {
  const _MiniCard({required this.card});

  final PlayingCard card;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFFFDFBF5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${card.rank.short}${card.suit.symbol}',
        style: TextStyle(
          color: card.suit.isRed
              ? const Color(0xFFC62828)
              : const Color(0xFF1B1B1B),
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }
}
