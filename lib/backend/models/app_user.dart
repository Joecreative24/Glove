// app_user.dart
// Maps to a document in  users/{uid}.
//
// The full personal profile of a person who uses the glove. One AppUser
// owns many Devices, Sessions, Alerts, etc. (User 1-to-many everything).

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/enums.dart';
import '../core/firestore_utils.dart';

class AppUser {
  final String uid;
  final String fullName;
  final String email;
  final String uniqueUsername;
  final String? phoneNumber;
  final String? photoUrl;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;
  final AuthProviderType authProvider;
  final UserRole role;
  final int totalDevices;
  final int totalSessions;
  final String? lastConnectedDevice;
  final AccountStatus accountStatus;

  const AppUser({
    required this.uid,
    required this.fullName,
    required this.email,
    required this.uniqueUsername,
    this.phoneNumber,
    this.photoUrl,
    this.createdAt,
    this.lastLoginAt,
    this.authProvider = AuthProviderType.emailPassword,
    this.role = UserRole.user,
    this.totalDevices = 0,
    this.totalSessions = 0,
    this.lastConnectedDevice,
    this.accountStatus = AccountStatus.active,
  });

  factory AppUser.fromMap(String id, Map<String, dynamic> m) => AppUser(
        uid: readString(m['uid'], id),
        fullName: readString(m['fullName']),
        email: readString(m['email']),
        uniqueUsername: readString(m['uniqueUsername']),
        phoneNumber: m['phoneNumber'] as String?,
        photoUrl: m['photoUrl'] as String?,
        createdAt: readDate(m['createdAt']),
        lastLoginAt: readDate(m['lastLoginAt']),
        authProvider: AuthProviderType.fromWire(m['authProvider'] as String?),
        role: UserRole.fromWire(m['role'] as String?),
        totalDevices: readInt(m['totalDevices']),
        totalSessions: readInt(m['totalSessions']),
        lastConnectedDevice: m['lastConnectedDevice'] as String?,
        accountStatus: AccountStatus.fromWire(m['accountStatus'] as String?),
      );

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      AppUser.fromMap(doc.id, doc.data() ?? const {});

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'fullName': fullName,
        'email': email,
        'uniqueUsername': uniqueUsername,
        'phoneNumber': phoneNumber,
        'photoUrl': photoUrl,
        'createdAt': toTs(createdAt),
        'lastLoginAt': toTs(lastLoginAt),
        'authProvider': authProvider.wire,
        'role': role.wire,
        'totalDevices': totalDevices,
        'totalSessions': totalSessions,
        'lastConnectedDevice': lastConnectedDevice,
        'accountStatus': accountStatus.wire,
      };

  AppUser copyWith({
    String? fullName,
    String? email,
    String? uniqueUsername,
    String? phoneNumber,
    String? photoUrl,
    DateTime? lastLoginAt,
    int? totalDevices,
    int? totalSessions,
    String? lastConnectedDevice,
    AccountStatus? accountStatus,
  }) =>
      AppUser(
        uid: uid,
        fullName: fullName ?? this.fullName,
        email: email ?? this.email,
        uniqueUsername: uniqueUsername ?? this.uniqueUsername,
        phoneNumber: phoneNumber ?? this.phoneNumber,
        photoUrl: photoUrl ?? this.photoUrl,
        createdAt: createdAt,
        lastLoginAt: lastLoginAt ?? this.lastLoginAt,
        authProvider: authProvider,
        role: role,
        totalDevices: totalDevices ?? this.totalDevices,
        totalSessions: totalSessions ?? this.totalSessions,
        lastConnectedDevice: lastConnectedDevice ?? this.lastConnectedDevice,
        accountStatus: accountStatus ?? this.accountStatus,
      );
}
