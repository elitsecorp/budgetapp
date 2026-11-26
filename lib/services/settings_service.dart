import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../parsers/extractors.dart';

/// Simple key-value settings, loaded once before `runApp`.
class SettingsStore {
  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    // Sender → institution labels must be live before the first parse.
    final raw = _prefs.getString('sender_labels');
    if (raw != null && raw.isNotEmpty) {
      try {
        senderLabels
          ..clear()
          ..addAll((jsonDecode(raw) as Map).map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          ));
      } catch (_) {
        // Corrupt map — ignore and start fresh.
      }
    }
  }

  static String getString(String key, String fallback) =>
      _prefs.getString(key) ?? fallback;

  /// Like [getString], but a stored empty string also falls back — so a
  /// previously-cleared field picks up a newly added default URL.
  static String getNonEmptyString(String key, String fallback) {
    final v = _prefs.getString(key);
    return (v == null || v.trim().isEmpty) ? fallback : v;
  }
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

  /// User-created categories (persisted as a JSON list).
  static List<String> customCategoryList() {
    final raw = _prefs.getString(_kCustomCategories);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List).map((e) => e.toString()).toList();
    } catch (_) {
      return [];
    }
  }
}

class AppSettings {
  final String ownerName;
  final String ownerPhone;
  final String apkUrl;
  final String serverUrl;
  final String serverApiKey;
  final bool excludeTransfers;
  final double maxAmount; // 0 = no limit
  final bool contactLookup;
  final List<String> customCategories;

  /// Stable "always newest" release link — GitHub redirects it to whatever
  /// asset is attached to the latest published release.
  static const defaultApkUrl =
      'https://github.com/elitsecorp/budgetapp/releases/latest/download/budget-app.apk';

  /// Default sync endpoint (Render deployment).
  static const defaultServerUrl =
      'https://budgetapp-1-q2v0.onrender.com/api/sync';

  const AppSettings({
    this.ownerName = '',
    this.ownerPhone = '',
    this.apkUrl = defaultApkUrl,
    this.serverUrl = defaultServerUrl,
    this.serverApiKey = '',
    this.excludeTransfers = false,
    this.maxAmount = 0,
    this.contactLookup = false,
    this.customCategories = const [],
  });

  AppSettings copyWith({
    String? ownerName,
    String? ownerPhone,
    String? apkUrl,
    String? serverUrl,
    String? serverApiKey,
    bool? excludeTransfers,
    double? maxAmount,
    bool? contactLookup,
    List<String>? customCategories,
  }) =>
      AppSettings(
        ownerName: ownerName ?? this.ownerName,
        ownerPhone: ownerPhone ?? this.ownerPhone,
        apkUrl: apkUrl ?? this.apkUrl,
        serverUrl: serverUrl ?? this.serverUrl,
        serverApiKey: serverApiKey ?? this.serverApiKey,
        excludeTransfers: excludeTransfers ?? this.excludeTransfers,
        maxAmount: maxAmount ?? this.maxAmount,
        contactLookup: contactLookup ?? this.contactLookup,
        customCategories: customCategories ?? this.customCategories,
      );
}

const _kOwnerName = 'owner_name';
const _kOwnerPhone = 'owner_phone';
const _kApkUrl = 'apk_url';
const _kServerUrl = 'server_url';
const _kServerApiKey = 'server_api_key';
const _kExcludeTransfers = 'exclude_transfers';
const _kMaxAmount = 'max_amount';
const _kContactLookup = 'contact_lookup';
const _kCustomCategories = 'custom_categories';

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => AppSettings(
        ownerName: SettingsStore.getString(_kOwnerName, ''),
        ownerPhone: SettingsStore.getString(_kOwnerPhone, ''),
        apkUrl:
            SettingsStore.getNonEmptyString(_kApkUrl, AppSettings.defaultApkUrl),
        serverUrl: SettingsStore.getNonEmptyString(
            _kServerUrl, AppSettings.defaultServerUrl),
        serverApiKey: SettingsStore.getString(_kServerApiKey, ''),
        excludeTransfers:
            SettingsStore.getBool(_kExcludeTransfers, false),
        maxAmount: SettingsStore.getDouble(_kMaxAmount, 0),
        contactLookup: SettingsStore.getBool(_kContactLookup, false),
        customCategories: SettingsStore.customCategoryList(),
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

  Future<void> setServerApiKey(String v) =>
      _persist(() => SettingsStore.setString(_kServerApiKey, v.trim()));

  Future<void> setExcludeTransfers(bool v) =>
      _persist(() => SettingsStore.setBool(_kExcludeTransfers, v));

  Future<void> setMaxAmount(double v) =>
      _persist(() => SettingsStore.setDouble(_kMaxAmount, v));

  Future<void> setContactLookup(bool v) =>
      _persist(() => SettingsStore.setBool(_kContactLookup, v));

  /// Assigns (or clears, with a blank label) the institution name for a
  /// sender — parsed transactions are relabelled by the caller.
  Future<void> setSenderLabel(String sender, String label) async {
    final key = sender.toLowerCase();
    if (label.trim().isEmpty) {
      senderLabels.remove(key);
    } else {
      senderLabels[key] = label.trim();
    }
    await SettingsStore.setString(
      'sender_labels',
      jsonEncode({for (final e in senderLabels.entries) e.key: e.value}),
    );
    ref.invalidateSelf();
  }

  /// Persists a user-created category (no-op if it already exists).
  Future<void> addCustomCategory(String name) async {
    final list = SettingsStore.customCategoryList();
    if (!list.contains(name)) {
      list.add(name);
      await SettingsStore.setString(_kCustomCategories, jsonEncode(list));
    }
    ref.invalidateSelf();
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
