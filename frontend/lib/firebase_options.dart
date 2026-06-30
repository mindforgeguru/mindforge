// Generated from google-services.json and GoogleService-Info.plist
// DO NOT commit API keys to public repos.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDYmYmBqhgnQQKtPhLpzd7xnrnxQGFpE0M',
    appId: '1:98913884574:web:cfed0dd53dc9e927421e8f',
    messagingSenderId: '98913884574',
    projectId: 'mindforge-b2324',
    authDomain: 'mindforge-b2324.firebaseapp.com',
    storageBucket: 'mindforge-b2324.firebasestorage.app',
    measurementId: 'G-70FQQSSX1Q',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCZ7yTGCVV-klJtoan9whSmGBkMMgIASMw',
    appId: '1:98913884574:android:37f141462ea1d0e6421e8f',
    messagingSenderId: '98913884574',
    projectId: 'mindforge-b2324',
    storageBucket: 'mindforge-b2324.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBqeTY2qzb4f4yATvI2dIOW6TW3uAAQz0A',
    appId: '1:98913884574:ios:2b41b0a2ce745b7f421e8f',
    messagingSenderId: '98913884574',
    projectId: 'mindforge-b2324',
    storageBucket: 'mindforge-b2324.firebasestorage.app',
    iosBundleId: 'com.mindforge.mindforge',
  );
}
