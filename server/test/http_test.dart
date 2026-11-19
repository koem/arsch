// Einladungsseite, IPv6 und verschlüsselte Verbindung (wss://).
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('unverschlüsselt', () {
    late TestServer server;
    setUp(() async => server = await TestServer.start());
    tearDown(() => server.dispose());

    test('Einladungsseite verlinkt die App und öffnet sie sofort', () async {
      final host = await Client.create(server, 'Host');
      final page = await server.get('/r/${host.code!.toLowerCase()}');
      final server_ = Uri.encodeComponent(server.wsUrl);
      expect(page, contains('arsch://join?code=${host.code}&amp;server=$server_'));
      expect(page, contains('intent://join?code=${host.code}&server=$server_'
          '#Intent;scheme=arsch;end'));
      expect(page, contains('window.location.href = target'));
      expect(page, contains('Im Warteraum: 1 von 5 Spielern.'));
    });

    test('Ungültiger Code: 404; verdächtiger Host-Header: 400', () async {
      expect((await server.getWithStatus('/r/<x>')).$1, 404);
      final (status, _) = await server
          .getWithStatus('/r/ABCD', headers: {'X-Forwarded-Host': 'evil</script><x>'});
      expect(status, 400);
    });

    test('Erreichbar über IPv4 und IPv6', () async {
      for (final host in ['127.0.0.1', '[::1]']) {
        final client = HttpClient();
        final response =
            await (await client.getUrl(Uri.parse('http://$host:${server.port}/'))).close();
        expect(await response.transform(utf8.decoder).join(), startsWith('Arsch-Server läuft'));
        client.close();
      }
    });
  });

  group('mit TLS', () {
    late TestServer server;
    late Directory certDir;
    setUp(() async {
      certDir = await Directory.systemTemp.createTemp('arsch_tls');
      final result = await Process.run('openssl', [
        'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
        '-subj', '/CN=localhost',
        '-keyout', '${certDir.path}/key.pem', '-out', '${certDir.path}/cert.pem',
      ]);
      expect(result.exitCode, 0, reason: 'openssl wird für diesen Test gebraucht');
      server = await TestServer.start(env: {
        'TLS_CERT': '${certDir.path}/cert.pem',
        'TLS_KEY': '${certDir.path}/key.pem',
      });
    });
    tearDown(() async {
      await server.dispose();
      certDir.deleteSync(recursive: true);
    });

    test('wss:// funktioniert, Einladung verweist auf wss://', () async {
      expect(server.output.toString(), contains('(TLS, wss://)'));
      final http = HttpClient()..badCertificateCallback = (_, __, ___) => true;
      final ws = await WebSocket.connect('wss://localhost:${server.port}',
          customClient: http);
      ws.add(jsonEncode({'type': 'create', 'name': 'TLS'}));
      final state = await ws
          .map((d) => jsonDecode(d as String) as Map<String, dynamic>)
          .firstWhere((m) => m['type'] == 'state');
      expect(state['phase'], 'lobby');
      await ws.close();

      final request =
          await http.getUrl(Uri.parse('https://localhost:${server.port}/r/ABCD'));
      final page = await (await request.close()).transform(utf8.decoder).join();
      expect(page, contains('server=wss%3A%2F%2Flocalhost%3A${server.port}'));
      http.close();
    });
  });
}
