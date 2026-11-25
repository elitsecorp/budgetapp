import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Simple key-value settings, loaded once before `runApp`.
class SettingsStore {
  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static String getString(String key, String fallback) =>
      _prefs.getString(key) ?? fallback;
  static bool getBool(String key, bool fallback) =>
      _prefs.getBool(key) ?? fallback;
  static double getDouble(String key, double fallback) =>
      _prefs.getDouble(key) ?? fallback;

  static Future<bool> setString(String key, String value) =>
      _prefs.setString(key, value);
  static Future<bool> setBool(String key, bool value) =>
      _prefs.setBool(key, value);
  static Future<bool> setDouble(String key, double value) =>
      _prefs.setDouble(key, value);
}

class AppSettings {
  final String ownerName;
  final String ownerPhone;
  final String apkUrl;
  final String serverUrl;
  final bool excludeTransfers;
  final double maxAmount; // 0 = no limit
  final bool contactLookup;

  const AppSettings({
    this.ownerName = '',
    this.ownerPhone = '',
    this.apkUrl = '',
    this.serverUrl = 'https://httpbin.org/post',
    this.excludeTransfers = false,
    this.maxAmount = 0,
    this.contactLookup = false,
  });

  AppSettings copyWith({
    String? ownerName,
    String? ownerPhone,
    String? apkUrl,
    String? serverUrl,
    bool? excludeTransfers,
    double? maxAmount,
    bool? contactLookup,
  }) =>
      AppSettings(
        ownerName: ownerName ?? this.ownerName,
        ownerPhone: ownerPhone ?? this.ownerPhone,
        apkUrl: apkUrl ?? this.apkUrl,
        serverUrl: serverUrl ?? this.serverUrl,
        excludeTransfers: excludeTransfers ?? this.excludeTransfers,
        maxAmount: maxAmount ?? this.maxAmount,
        contactLookup: contactLookup ?? this.contactLookup,
      );
}

const _kOwnerName = 'owner_name';
const _kOwnerPhone = 'owner_phone';
const _kApkUrl = 'apk_url';
const _kServerUrl = 'server_url';
const _kExcludeTransfers = 'exclude_transfers';
const _kMaxAmount = 'max_amount';
const _kContactLookup = 'contact_lookup';

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => AppSettings(
        ownerName: SettingsStore.getString(_kOwnerName, ''),
        ownerPhone: SettingsStore.getString(_kOwnerPhone, ''),
        apkUrl: SettingsStore.getString(_kApkUrl, ''),
        serverUrl: SettingsStore.getString(_kServerUrl, 'https://httpbin.org/post'),
        excludeTransfers:
            SettingsStore.getBool(_kExcludeTransfers, false),
        maxAmount: SettingsStore.getDouble(_kMaxAmount, 0),
        contactLookup: SettingsStore.getBool(_kContactLookup, false),
      );

  Future<void> _persist(Future<bool> Function() write) async {
    await write();
    // Re-read from prefs so state and storage never diverge.
    ref.invalidateSelf();
  }

  Future<void> setOwnerName(String v) =>
      _persist(() => SettingsStore.setString(_kOwnerName, v.trim()));

  Future<void> setOwnerPhone(String v) =>
      _persist(() => SettingsStore.setString(_kOwnerPhone, v.trim()));

  Future<void> setApkUrl(String v) =>
      _persist(() => SettingsStore.setString(_kApkUrl, v.trim()));

  Future<void> setServerUrl(String v) =>
      _persist(() => SettingsStore.setString(_kServerUrl, v.trim()));

  Future<void> setExcludeTransfers(bool v) =>
      _persist(() => SettingsStore.setBool(_kExcludeTransfers, v));

  Future<void> setMaxAmount(double v) =>
      _persist(() => SettingsStore.setDouble(_kMaxAmount, v));

  Future<void> setContactLookup(bool v) =>
      _persist(() => SettingsStore.setBool(_kContactLookup, v));
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
