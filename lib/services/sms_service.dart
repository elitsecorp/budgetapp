/// Bridge to the native Android SMS code (MethodChannel/EventChannel) plus
/// runtime permission handling.
library;

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/models.dart';

class SmsService {
  static const _method = MethodChannel('budget_app/sms');
  static const _events = EventChannel('budget_app/sms_events');

  /// READ_SMS is part of the SMS permission group; granting it also grants
  /// RECEIVE_SMS (both are declared in the manifest).
  Future<bool> hasPermission() async {
    try {
      return await _method.invokeMethod<bool>('hasReadSmsPermission') ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<PermissionStatus> requestPermission() => Permission.sms.request();

  Future<bool> get isPermanentlyDenied =>
      Permission.sms.status.then((s) => s.isPermanentlyDenied);

  Future<void> openSystemSettings() => openAppSettings();

  /// Live stream of incoming SMS (also receives messages that arrived while
  /// the app was closed, via the native queue).
  Stream<SmsMessage> get incoming => _events
      .receiveBroadcastStream()
      .map((e) => SmsMessage.fromMap(e as Map));

  /// Messages queued by SmsReceiver while Dart was not listening.
  Future<List<SmsMessage>> drainPending() async {
    try {
      final raw = await _method.invokeMethod<List<dynamic>>('drainPending');
      return (raw ?? const [])
          .map((e) => SmsMessage.fromMap(e as Map))
          .toList();
    } on PlatformException {
      return const [];
    }
  }

  /// Reads device inbox history (requires READ_SMS). Newest first.
  Future<List<SmsMessage>> fetchInbox({int limit = 2000}) async {
    try {
      final raw = await _method.invokeMethod<List<dynamic>>(
        'getInbox',
        {'limit': limit},
      );
      return (raw ?? const [])
          .map((e) => SmsMessage.fromMap(e as Map))
          .toList();
    } on PlatformException {
      return const [];
    }
  }
}
