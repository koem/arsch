import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../game_client.dart';

/// Teilt einen Einladungslink zum aktuellen Raum (z.B. per Messenger).
/// Läuft das Spiel schon, können Eingeladene zuschauen.
class ShareRoomButton extends StatelessWidget {
  const ShareRoomButton({super.key, required this.client});

  final GameClient client;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.share),
      tooltip: 'Einladungslink teilen',
      onPressed: () {
        final code = client.state?.code;
        if (code == null) return;
        final link = client.shareLink;
        final box = context.findRenderObject() as RenderBox?;
        SharePlus.instance.share(ShareParams(
          subject: 'Arsch – Raum $code',
          text: 'Spiel „Arsch“ mit mir! Raum-Code: $code'
              '${link == null ? '' : '\n$link'}',
          // Für iPad: von wo das Teilen-Fenster aufgeht.
          sharePositionOrigin:
              box == null ? null : box.localToGlobal(Offset.zero) & box.size,
        ));
      },
    );
  }
}
