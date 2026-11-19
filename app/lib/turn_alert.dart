import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';

/// Meldet „Du bist dran!“: im Vordergrund per Vibration, im Hintergrund
/// (App noch verbunden, aber nicht sichtbar) als Benachrichtigung.
///
/// Zusätzlich wird eine Erinnerung kurz vor Ablauf der Bedenkzeit beim
/// Betriebssystem eingeplant – die kommt auch, wenn die App geschlossen ist.
///
/// Ist die App ganz geschlossen, wenn man dran kommt, erfährt sie davon
/// nichts – dafür wären Push-Nachrichten (Firebase/APNs) nötig.
class TurnAlert with WidgetsBindingObserver {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _askedPermission = false;

  static const _turnId = 1;
  static const _reminderId = 2;
  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'turn',
      'Du bist dran',
      channelDescription: 'Meldet, wenn du im Spiel am Zug bist.',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
    ),
  );

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_notification'),
          // Erlaubnis erst fragen, wenn man einen Raum betritt.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      _ready = true;
    } catch (_) {
      // Ohne Benachrichtigungen geht es auch.
    }
  }

  /// Fragt einmal pro App-Start nach der Erlaubnis (Android 13+, iOS).
  Future<void> requestPermission() async {
    if (!_ready || _askedPermission) return;
    _askedPermission = true;
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, sound: true);
  }

  bool get _inForeground =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  /// [isNew]: gerade dran gekommen (sonst hat sich nur die Frist geändert).
  void myTurn(TableState state, {required bool isNew}) {
    if (isNew) {
      if (_inForeground) {
        HapticFeedback.heavyImpact();
      } else if (_ready) {
        _plugin.show(
          id: _turnId,
          title: 'Du bist dran!',
          body: 'Raum ${state.code} – tippe, um weiterzuspielen.',
          notificationDetails: _details,
        );
      }
    }
    _scheduleReminder(state);
  }

  void _scheduleReminder(TableState state) {
    if (!_ready) return;
    final deadline = state.turnDeadline;
    if (deadline == null || state.reminderBefore == Duration.zero) return;
    final at = deadline.subtract(state.reminderBefore);
    if (!at.isAfter(DateTime.now())) return;
    final left = state.reminderBefore;
    final leftText = left.inHours >= 1
        ? 'Noch ${left.inHours} ${left.inHours == 1 ? 'Stunde' : 'Stunden'}'
        : 'Noch ${left.inMinutes} Minuten';
    _plugin.zonedSchedule(
      id: _reminderId,
      // Ein fester Zeitpunkt; die Zeitzone spielt dafür keine Rolle.
      scheduledDate: tz.TZDateTime.from(at, tz.UTC),
      title: '$leftText, dann wird für dich geschoben!',
      body: 'Raum ${state.code}: Du bist dran.',
      notificationDetails: _details,
      // Ungenau (ggf. einige Minuten später) braucht keine Sonderrechte.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  void turnOver() {
    if (!_ready) return;
    _plugin.cancel(id: _turnId);
    _plugin.cancel(id: _reminderId);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Die „Du bist dran“-Meldung ist erledigt, wenn man die App öffnet.
    // Die Erinnerung bleibt, solange man noch nicht gezogen hat.
    if (state == AppLifecycleState.resumed && _ready) {
      _plugin.cancel(id: _turnId);
    }
  }

  void dispose() => WidgetsBinding.instance.removeObserver(this);
}
