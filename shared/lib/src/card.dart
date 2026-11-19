/// Farben. Sie spielen im Spiel keine Rolle, nur bei der Frage,
/// welche Karte die "niedrigste" ist (Karo 7 vor Herz 7 usw.).
enum Suit {
  karo('♦', 'Karo'),
  herz('♥', 'Herz'),
  pik('♠', 'Pik'),
  kreuz('♣', 'Kreuz');

  const Suit(this.symbol, this.label);
  final String symbol;
  final String label;

  bool get isRed => this == Suit.karo || this == Suit.herz;
}

/// Kartenwerte, aufsteigend: Sieben ist die niedrigste, Ass die höchste.
enum Rank {
  sieben('7', 'Sieben'),
  acht('8', 'Acht'),
  neun('9', 'Neun'),
  zehn('10', 'Zehn'),
  bube('B', 'Bube'),
  dame('D', 'Dame'),
  koenig('K', 'König'),
  ass('A', 'Ass');

  const Rank(this.short, this.label);
  final String short;
  final String label;
}

class PlayingCard implements Comparable<PlayingCard> {
  const PlayingCard(this.rank, this.suit);

  /// Karten werden im Netzwerk als Zahl 0..31 übertragen.
  /// 0 = Karo 7 (niedrigste Karte), 31 = Kreuz Ass.
  factory PlayingCard.fromId(int id) {
    RangeError.checkValueInInterval(id, 0, 31, 'id');
    return PlayingCard(Rank.values[id ~/ 4], Suit.values[id % 4]);
  }

  final Rank rank;
  final Suit suit;

  int get id => rank.index * 4 + suit.index;

  @override
  int compareTo(PlayingCard other) => id.compareTo(other.id);

  @override
  bool operator ==(Object other) => other is PlayingCard && other.id == id;

  @override
  int get hashCode => id;

  @override
  String toString() => '${suit.label} ${rank.label}';
}

/// Alle 32 Karten, aufsteigend sortiert.
List<PlayingCard> fullDeck() => [for (var i = 0; i < 32; i++) PlayingCard.fromId(i)];
