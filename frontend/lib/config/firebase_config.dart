import 'package:firebase_core/firebase_core.dart';

import '../firebase_options.dart';

class AppFirebaseConfig {
  static const String apiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: '',
  );
  static const String appId = String.fromEnvironment(
    'FIREBASE_APP_ID',
    defaultValue: '',
  );
  static const String messagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
    defaultValue: '',
  );
  static const String projectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: '',
  );
  static const String authDomain = String.fromEnvironment(
    'FIREBASE_AUTH_DOMAIN',
    defaultValue: '',
  );
  static const String storageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
    defaultValue: '',
  );
  static const String iosBundleId = String.fromEnvironment(
    'FIREBASE_IOS_BUNDLE_ID',
    defaultValue: '',
  );
  static const String androidClientId = String.fromEnvironment(
    'FIREBASE_ANDROID_CLIENT_ID',
    defaultValue: '',
  );
  static const String iosClientId = String.fromEnvironment(
    'FIREBASE_IOS_CLIENT_ID',
    defaultValue: '',
  );
  static const String measurementId = String.fromEnvironment(
    'FIREBASE_MEASUREMENT_ID',
    defaultValue: '',
  );
  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );

  static bool get hasRuntimeOverride =>
      apiKey.isNotEmpty &&
      appId.isNotEmpty &&
      messagingSenderId.isNotEmpty &&
      projectId.isNotEmpty;

  static bool get hasGeneratedOptions {
    try {
      DefaultFirebaseOptions.currentPlatform;
      return true;
    } on UnsupportedError {
      return false;
    }
  }

  static bool get isConfigured => hasRuntimeOverride || hasGeneratedOptions;

  static FirebaseOptions get currentOptions {
    if (hasRuntimeOverride) {
      return FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: messagingSenderId,
        projectId: projectId,
        authDomain: authDomain.isEmpty ? null : authDomain,
        storageBucket: storageBucket.isEmpty ? null : storageBucket,
        iosBundleId: iosBundleId.isEmpty ? null : iosBundleId,
        androidClientId: androidClientId.isEmpty ? null : androidClientId,
        iosClientId: iosClientId.isEmpty ? null : iosClientId,
        measurementId: measurementId.isEmpty ? null : measurementId,
      );
    }

    return DefaultFirebaseOptions.currentPlatform;
  }
}
