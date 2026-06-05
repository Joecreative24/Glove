// storage_service.dart
// Profile-photo uploads to Cloud Storage at
//   profile_photos/{uid}/avatar.jpg
// Returns a download URL you can store on the user profile's `photoUrl`.

import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  final FirebaseStorage _storage;
  StorageService({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  Reference _avatarRef(String uid) =>
      _storage.ref('profile_photos/$uid/avatar.jpg');

  /// Uploads a photo from a local file and returns its download URL.
  Future<String> uploadProfilePhotoFile(String uid, File file) async {
    final ref = _avatarRef(uid);
    await ref.putFile(
      file,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return ref.getDownloadURL();
  }

  /// Uploads a photo from in-memory bytes (handy on Web). Returns the URL.
  Future<String> uploadProfilePhotoBytes(String uid, Uint8List bytes) async {
    final ref = _avatarRef(uid);
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  /// Removes the stored avatar (ignores "not found").
  Future<void> deleteProfilePhoto(String uid) async {
    try {
      await _avatarRef(uid).delete();
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') rethrow;
    }
  }
}
