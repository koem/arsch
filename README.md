# Arsch – Multiplayer-Kartenspiel für Android und iOS

Drei Teile, alle in Dart:

| Ordner    | Inhalt |
|-----------|--------|
| `shared/` | Die Spielregeln (Karten, Stiche, Punkte). Wird von App und Server benutzt. |
| `server/` | Der Spielserver (WebSocket). Er teilt aus, prüft jeden Zug und schickt jedem Spieler nur seine eigenen Karten. |
| `app/`    | Die Flutter-App für Android und iOS. |

## Einrichten

Voraussetzung: [Flutter](https://docs.flutter.dev/get-started/install) ist installiert (bringt Dart mit).
Für iOS brauchst du zusätzlich einen Mac mit Xcode.

```bash
# 1. Regeln testen
cd shared
dart pub get
dart test

# 2. Server starten (läuft dann auf Port 8080)
cd ../server
dart pub get
dart run bin/server.dart

# 3. App: Android- und iOS-Projektordner einmalig erzeugen, dann starten
cd ../app
flutter create --project-name arsch --org de.example --platforms android,ios .
rm -f test/widget_test.dart        # Beispieltest von Flutter, passt nicht zu dieser App
flutter pub get
flutter run
```

`de.example` bitte durch deine eigene Kennung ersetzen (z.B. `de.deinname`); sie wird Teil der App-ID in den Stores.

### Server-Adresse

Die App fragt den Server unter der Adresse an, die auf dem Startbildschirm unter
„Server-Einstellungen“ steht. Voreingestellt ist **`ws://koem2.mooo.com:2284`**.

- Lokal testen im Android-Emulator: `ws://10.0.2.2:8080` (eigener Rechner)
- iOS-Simulator: `ws://localhost:8080`
- Anderer fester Standard beim Bauen: `flutter build apk --dart-define=ARSCH_SERVER=ws://…`

Eine einmal eingetragene Adresse merkt sich die App; der Standard gilt für neue Installationen.

### Server betreiben (koem2.mooo.com:2284)

Auf dem Server-Rechner im Projektordner:

```bash
docker compose up -d      # baut das Image und startet den Server auf Port 2284
docker compose logs -f    # Log ansehen
```

- **Router:** Portfreigabe **TCP 2284** → Server-Rechner, Port 2284 (kein UDP nötig).
  Dem Server-Rechner im Router eine feste lokale IP geben.
- **Wechselnde IP:** `koem2.mooo.com` muss automatisch auf die aktuelle IP zeigen
  (DynDNS-Update im Router oder per Skript bei FreeDNS/afraid.org).
- **Test von außen** (z.B. Handy ohne WLAN): `http://koem2.mooo.com:2284` zeigt „Arsch-Server läuft“.
- **Spielstände** liegen im Docker-Volume `arsch-data` und überstehen Neustarts und Updates.
  Update: neuen Code holen, `docker compose up -d --build`.
- **Verschlüsselung (optional, wss://):** Mit einem Zertifikat für koem2.mooo.com (PEM) die Variablen
  `TLS_CERT`/`TLS_KEY` setzen (siehe `docker-compose.yml`), dann in der App `wss://koem2.mooo.com:2284`.
  Ohne Zertifikat läuft die Verbindung unverschlüsselt (Spielstand, Namen, Sitzungs-Token – keine Passwörter).

### Vor der Veröffentlichung

- **Server hosten:** `docker build -f Dockerfile.server -t arsch-server .` im Hauptordner,
  dann den Container bei einem Anbieter deiner Wahl laufen lassen, mit einem Volume für
  den Spielstand: `docker run -p 2284:2284 -v arsch-data:/data arsch-server`. Der Server speichert
  alle Räume in `/data/rooms.json` (ohne Docker: `./data/rooms.json`, änderbar mit `DATA_DIR`) und
  lädt sie beim Start wieder – laufende Spiele überstehen so Neustarts und Updates.
  Für `wss://` entweder `TLS_CERT`/`TLS_KEY` setzen oder einen Reverse-Proxy mit TLS davorschalten.
  (Unverschlüsseltes `ws://` funktioniert in der Release-App – getestet auf Android 16 –, weil die
  Verbindung über Dart-Sockets läuft und nicht unter die Cleartext-Sperre von Android/iOS fällt.)
- **Android:** In `app/android/app/src/main/AndroidManifest.xml` die Zeile
  `<uses-permission android:name="android.permission.INTERNET"/>` ergänzen
  (in Debug-Builds ist sie automatisch da, in Release-Builds nicht) und
  `android:label` auf `Arsch` setzen.
- **iOS:** In `app/ios/Runner/Info.plist` den `CFBundleDisplayName` auf `Arsch` setzen.
- Der Name „Arsch“ kann bei der Store-Prüfung (vor allem bei Apple) Rückfragen auslösen.

## Spielablauf in der App

1. Ein Spieler tippt „Neues Spiel erstellen“ und bekommt einen vierstelligen Raum-Code.
2. Die anderen geben den Code ein und treten bei.
3. Sobald 4 oder 5 Spieler da sind, startet der Gastgeber.
4. Karten antippen (mehrere mit gleichem Wert möglich), dann „Legen“ – oder „Ich schiebe“.

Bricht die Verbindung ab oder wird die App geschlossen, kehrt man automatisch an seinen Platz zurück.
Solange ein Spieler getrennt ist, wartet das Spiel; jeder kann es dann abbrechen (zurück in den Warteraum).

## Umgesetzte Regeln

- 32 Karten (7, 8, 9, 10, Bube, Dame, König, Ass in Karo, Herz, Pik, Kreuz). Farben sind egal.
- Reihum austeilen, alle gleich viele: zu fünft 6 Karten (2 bleiben verdeckt in der Mitte), zu viert 8 Karten.
- Erste Runde: Wer die niedrigste Karte hat, beginnt (Karo 7, sonst Herz 7, Pik 7, Kreuz 7, Karo 8 …).
- Ausspielen: beliebig viele Karten mit gleichem Wert. Danach: gleich viele Karten mit höherem Wert oder schieben.
- Ein Stich endet, wenn Asse gelegt wurden oder alle anderen nacheinander geschoben haben.
  Wer zuletzt gelegt hat, spielt neu aus.
- Reihenfolge des Fertigwerdens: Präsi (+2), Vize-Präsi (+1), Mitte (0), Vize-Arsch (−1), Arsch (−2).
- Der Arsch beginnt die nächste Runde. Bei +20 oder −20 Punkten ist das Spiel vorbei.
- **Swap:** Jede dieser Bedingungen allein ist ein Swap (+1 Punkt extra, gelber Stern ★):
  - Ein Spieler legt alle seine Karten, ohne dass zwischendurch ein anderer Karten gelegt hat
    (Schieben zählt nicht).
  - Der Arsch der Vorrunde wird Präsi.

  Treffen beide zu, ist es ein **Doppel-Swap**: +2 Punkte, ★★. Die Rundenübersicht zeigt die
  Swaps jedes Spielers im ganzen Spiel.
- Jeder Spieler hat 24 Stunden Zeit für seinen Zug. Danach wird für ihn „Ich schiebe“ gesagt.
  3 Stunden vor Ablauf erinnert ihn die App mit einer Benachrichtigung.
- Zu fünft nimmt der Arsch der Vorrunde vor Beginn der neuen Runde die 2 Karten aus der Mitte
  auf die Hand und legt danach 2 beliebige Karten verdeckt zurück (auch die gerade aufgenommenen).
  So hat er die Chance, 2 schlechte Karten loszuwerden. Erst danach wird gespielt.

### Annahmen, wo die Regeln nichts sagen

Diese Punkte habe ich selbst festgelegt; sie lassen sich in `shared/lib/src/game.dart` leicht ändern:

- **Zu viert** gibt es keine „Mitte“: Präsi +2, Vize-Präsi +1, Vize-Arsch −1, Arsch −2.
- Wer anfängt, muss die niedrigste Karte **nicht** ausspielen, er darf frei wählen.
- Wer geschoben hat, darf im selben Stich später wieder legen, solange der Stich noch läuft.
- Wer ausspielt (leerer Tisch), muss legen und kann nicht schieben.
- Wird jemand mit seinen letzten Karten fertig und gewinnt damit den Stich,
  spielt der nächste Spieler links von ihm aus.
- Läuft die Zeit ab, während man **ausspielt** (dort darf man nicht schieben), wird automatisch
  die niedrigste Karte gelegt. Muss der Arsch noch zurücklegen, gehen seine 2 niedrigsten Karten zurück.
- Räume werden aufgeräumt: leere Warteräume nach 15 Minuten, Spiele zwischen zwei Runden oder am
  Ende nach 3 Tagen ohne verbundenen Spieler. Eine laufende Runde wird nie gelöscht.
- Die verdeckten Karten in der Mitte bleiben die ganze Runde aus dem Spiel (nachdem der Arsch
  getauscht hat). Nur der Arsch sieht, welche Karten er aufgenommen hat.
- Am Spielende gewinnt, wer die meisten Punkte hat.
