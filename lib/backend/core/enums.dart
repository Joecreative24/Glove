// enums.dart
// Strongly-typed enums for every "status / type" field in the database.
//
// Each enum exposes:
//   • `.wire`            → the exact String stored in Firestore
//   • `Enum.fromWire(s)` → parses a Firestore String back to the enum
//
// Storing typed enums in code (instead of loose strings) prevents typos
// and makes the analytics / UI layers safe to refactor.

// ─────────────────────────────────────────────────────────────────────────────
//  Authentication
// ─────────────────────────────────────────────────────────────────────────────

/// How the account was created.
enum AuthProvider {
  emailPassword, // 'email/password'
  google; // 'google'

  String get wire => switch (this) {
        AuthProvider.emailPassword => 'email/password',
        AuthProvider.google => 'google',
      };

  static AuthProvider fromWire(String? v) => switch (v) {
        'google' => AuthProvider.google,
        _ => AuthProvider.emailPassword,
      };
}

/// Lifecycle state of a user account.
enum AccountStatus {
  active,
  suspended,
  disabled;

  String get wire => name; // 'active' | 'suspended' | 'disabled'

  static AccountStatus fromWire(String? v) => AccountStatus.values
      .firstWhere((e) => e.name == v, orElse: () => AccountStatus.active);
}

/// Authorisation role.
enum UserRole {
  user,
  admin;

  String get wire => name;

  static UserRole fromWire(String? v) =>
      UserRole.values.firstWhere((e) => e.name == v, orElse: () => UserRole.user);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Device / glove
// ─────────────────────────────────────────────────────────────────────────────

/// Live link state between the phone and the glove.
enum ConnectionStatus {
  connected,
  disconnected,
  lost;

  String get wire => name;

  static ConnectionStatus fromWire(String? v) => ConnectionStatus.values
      .firstWhere((e) => e.name == v, orElse: () => ConnectionStatus.disconnected);
}

/// Battery bucket derived from `batteryLevel`.
enum BatteryStatus {
  normal,
  low,
  critical;

  String get wire => name;

  static BatteryStatus fromWire(String? v) => BatteryStatus.values
      .firstWhere((e) => e.name == v, orElse: () => BatteryStatus.normal);

  /// Maps a raw 0–100 battery percentage to a status bucket.
  ///   • <= 5  → critical
  ///   • <= 20 → low
  ///   • else  → normal
  static BatteryStatus fromLevel(int level) {
    if (level <= 5) return BatteryStatus.critical;
    if (level <= 20) return BatteryStatus.low;
    return BatteryStatus.normal;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Connection log
// ─────────────────────────────────────────────────────────────────────────────

/// A single entry in the device connection history.
enum ConnectionEventType {
  connected, // 'connected'
  disconnected, // 'disconnected'
  connectionLost, // 'connection_lost'
  connectionRestored; // 'connection_restored'

  String get wire => switch (this) {
        ConnectionEventType.connected => 'connected',
        ConnectionEventType.disconnected => 'disconnected',
        ConnectionEventType.connectionLost => 'connection_lost',
        ConnectionEventType.connectionRestored => 'connection_restored',
      };

  static ConnectionEventType fromWire(String? v) => switch (v) {
        'disconnected' => ConnectionEventType.disconnected,
        'connection_lost' => ConnectionEventType.connectionLost,
        'connection_restored' => ConnectionEventType.connectionRestored,
        _ => ConnectionEventType.connected,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
//  Translation session
// ─────────────────────────────────────────────────────────────────────────────

/// Lifecycle of a translation session.
enum SessionStatus {
  active,
  completed,
  interrupted;

  String get wire => name;

  static SessionStatus fromWire(String? v) => SessionStatus.values
      .firstWhere((e) => e.name == v, orElse: () => SessionStatus.active);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Realtime message
// ─────────────────────────────────────────────────────────────────────────────

/// What kind of payload a realtime message carries.
enum MessageType {
  translation,
  alert,
  system;

  String get wire => name;

  static MessageType fromWire(String? v) => MessageType.values
      .firstWhere((e) => e.name == v, orElse: () => MessageType.translation);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Alerts
// ─────────────────────────────────────────────────────────────────────────────

/// Category of an alert. Drives the icon, colour, and grouping in the UI.
enum AlertType {
  batteryLow, // 'battery_low'
  batteryCritical, // 'battery_critical'
  connectionLost, // 'connection_lost'
  connectionRestored, // 'connection_restored'
  deviceConnected, // 'device_connected'
  deviceDisconnected, // 'device_disconnected'
  emergencySos; // 'emergency_sos'  (powers the SOS tab)

  String get wire => switch (this) {
        AlertType.batteryLow => 'battery_low',
        AlertType.batteryCritical => 'battery_critical',
        AlertType.connectionLost => 'connection_lost',
        AlertType.connectionRestored => 'connection_restored',
        AlertType.deviceConnected => 'device_connected',
        AlertType.deviceDisconnected => 'device_disconnected',
        AlertType.emergencySos => 'emergency_sos',
      };

  static AlertType fromWire(String? v) => switch (v) {
        'battery_critical' => AlertType.batteryCritical,
        'connection_lost' => AlertType.connectionLost,
        'connection_restored' => AlertType.connectionRestored,
        'device_connected' => AlertType.deviceConnected,
        'device_disconnected' => AlertType.deviceDisconnected,
        'emergency_sos' => AlertType.emergencySos,
        _ => AlertType.batteryLow,
      };
}

/// Visual / priority severity for an alert.
enum AlertSeverity {
  low,
  medium,
  high,
  critical;

  String get wire => name;

  static AlertSeverity fromWire(String? v) => AlertSeverity.values
      .firstWhere((e) => e.name == v, orElse: () => AlertSeverity.low);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Shared constants
// ─────────────────────────────────────────────────────────────────────────────

/// Language labels used across gestures and messages.
class AppLanguage {
  AppLanguage._();

  /// Stored on gesture readings.
  static const arabicSignLanguage = 'Arabic Sign Language';

  /// Stored on translated realtime messages.
  static const arabic = 'Arabic';
}

/// The only device type this app supports today.
const String kDeviceTypeSmartGlove = 'smart_glove';
