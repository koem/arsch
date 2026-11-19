# Arsch-Server auf der Box installieren

Voraussetzung: Linux auf x86_64 (`uname -m` zeigt `x86_64`) mit Docker.
(Auf einem Raspberry Pi/ARM läuft dieses Image nicht – dann im Projektordner auf der Box
`docker build -f Dockerfile.server -t arsch-server .` ausführen.)

## 1. Docker installieren (falls noch nicht da)

    sudo apt install -y docker.io

## 2. Image auf die Box kopieren und laden

Auf dem Entwicklungsrechner:

    scp arsch-server.tar.gz docker-compose.yml BENUTZER@BOX:~/

Auf der Box:

    gunzip -c ~/arsch-server.tar.gz | sudo docker load

## 3. Starten

    sudo docker run -d --name arsch-server --restart unless-stopped \
      -p 2284:2284 -v arsch-data:/data arsch-server:latest

(oder mit Compose, falls installiert: `sudo docker compose up -d` im Ordner mit der docker-compose.yml)

Prüfen:

    sudo docker logs arsch-server        # "Arsch-Server läuft auf Port 2284"
    curl http://localhost:2284           # "Arsch-Server läuft. Räume: 0"

## 4. Erreichbar machen

- Firewall auf der Box (falls aktiv): `sudo ufw allow 2284/tcp`
- Router: Portfreigabe **TCP 2284** → Box, Port 2284. Der Box eine feste lokale IP geben.
- koem2.mooo.com muss auf die aktuelle öffentliche IP zeigen (DynDNS-Update bei FreeDNS/afraid.org,
  im Router oder per Cronjob).
- Test von außen (Handy ohne WLAN): http://koem2.mooo.com:2284

## Update auf eine neue Version

    gunzip -c ~/arsch-server.tar.gz | sudo docker load
    sudo docker rm -f arsch-server
    (Befehl aus Schritt 3 erneut ausführen)

Die Spielstände liegen im Volume `arsch-data` und bleiben dabei erhalten
(beim Stoppen speichert der Server noch einmal).
