// File generated for Shift Planner app.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAU8Ues0snNOc1IDL48TfKzoZMFIHZdchI',
    appId: '1:521754376184:web:bf6d7ed8f73dfd2399480d',
    messagingSenderId: '521754376184',
    projectId: 'shift-c7549',
    storageBucket: 'shift-c7549.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAU8Ues0snNOc1IDL48TfKzoZMFIHZdchI',
    appId: '1:521754376184:android:bf6d7ed8f73dfd2399480d',
    messagingSenderId: '521754376184',
    projectId: 'shift-c7549',
    storageBucket: 'shift-c7549.firebasestorage.app',
  );
}
