// firestore_utils.dart
// Small, dependency-free helpers for converting between Firestore values
// and Dart types. Keeping this logic in one place means every model
// parses Timestamps, numbers, and maps the same safe way.

import 'package:cloud_firestore/cloud_firestore.dart';

/// Reads a [DateTime] from a Firestore value that may be a [Timestamp],
/// an int (epoch millis), or null.
DateTime? readDate(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return null;
}

/// Like [readDate] but never null — falls back to the Unix epoch.
DateTime readDateOr(dynamic value, [DateTime? fallback]) =>
    readDate(value) ?? (fallback ?? DateTime.fromMillisecondsSinceEpoch(0));

/// Reads an int safely from dynamic Firestore data (handles num/double/String).
int readInt(dynamic value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

/// Reads a double safely (confidence scores, durations, averages).
double readDouble(dynamic value, [double fallback = 0]) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

/// Reads a bool safely.
bool readBool(dynamic value, [bool fallback = false]) {
  if (value is bool) return value;
  if (value is String) return value.toLowerCase() == 'true';
  return fallback;
}

/// Reads a String safely (null → fallback).
String readString(dynamic value, [String fallback = '']) =>
    value is String ? value : (value?.toString() ?? fallback);

/// Converts a nullable [DateTime] to a Firestore-friendly [Timestamp].
Timestamp? toTs(DateTime? dt) => dt == null ? null : Timestamp.fromDate(dt);

/// Server-managed timestamp sentinel (resolved by Firestore on write).
FieldValue get serverNow => FieldValue.serverTimestamp();

/// Strips null values out of a write map so we never overwrite existing
/// fields with null during partial updates.
Map<String, dynamic> withoutNulls(Map<String, dynamic> data) {
  data.removeWhere((_, v) => v == null);
  return data;
}
