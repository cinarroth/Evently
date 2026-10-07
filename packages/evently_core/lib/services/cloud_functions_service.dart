import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Central place where emulator vs production callable endpoints are decided.
/// Apps initialise this once in main() based on --dart-define flags.
class CloudFunctionsService {
  CloudFunctionsService._();

  static FirebaseFunctions get instance => FirebaseFunctions.instance;

  /// Points callable traffic at the local emulator.
  static void useEmulator({String host = 'localhost'}) {
    instance.useFunctionsEmulator(host, 5001);
  }

  /// Invokes [function] and returns the JSON payload as a mutable map.
  static Future<Map<String, dynamic>> call(
    String function,
    Map<String, dynamic> data,
  ) async {
    try {
      final res = await instance
          .httpsCallable(function,
              options:
                  HttpsCallableOptions(timeout: const Duration(seconds: 30)))
          .call<dynamic>(data);
      final raw = res.data;
      if (raw is Map) return raw.map((k, v) => MapEntry(k.toString(), v));
      return const <String, dynamic>{};
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Callable $function failed: ${e.code} ${e.message}');
      rethrow;
    }
  }
}
