import 'package:arsch_shared/arsch_shared.dart';
import 'package:material_ui/material_ui.dart';

/// Seitenverhältnis einer Spielkarte (Höhe / Breite).
const double cardAspect = 1.45;

/// Vorderseite einer Karte.
class CardFace extends StatelessWidget {
  const CardFace({
    super.key,
    required this.card,
    this.width = 62,
    this.selected = false,
    this.dimmed = false,
  });

  final PlayingCard card;
  final double width;
  final bool selected;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final color =
        card.suit.isRed ? const Color(0xFFC62828) : const Color(0xFF1B1B1B);
    return Opacity(
      opacity: dimmed ? 0.4 : 1,
      child: Container(
        width: width,
        height: width * cardAspect,
        decoration: BoxDecoration(
          color: const Color(0xFFFDFBF5),
          borderRadius: BorderRadius.circular(width * 0.12),
          border: Border.all(
            color: selected ? Colors.amber : Colors.black26,
            width: selected ? 3 : 1,
          ),
          boxShadow: const [
            BoxShadow(
                color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              left: width * 0.09,
              top: width * 0.04,
              child: Column(
                children: [
                  Text(
                    card.rank.short,
                    style: TextStyle(
                      color: color,
                      fontSize: width * 0.3,
                      fontWeight: FontWeight.bold,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    card.suit.symbol,
                    style: TextStyle(
                        color: color, fontSize: width * 0.26, height: 1.0),
                  ),
                ],
              ),
            ),
            Align(
              alignment: const Alignment(0.35, 0.5),
              child: Text(
                card.suit.symbol,
                style: TextStyle(color: color, fontSize: width * 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rückseite einer Karte.
class CardBack extends StatelessWidget {
  const CardBack({super.key, this.width = 62});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: width * cardAspect,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7B1F2B), Color(0xFF3A0F16)],
        ),
        borderRadius: BorderRadius.circular(width * 0.12),
        border: Border.all(color: const Color(0xFFFDFBF5), width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
    );
  }
}
