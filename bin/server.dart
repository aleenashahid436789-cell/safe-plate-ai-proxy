// server/bin/server.dart
//
// Backend proxy for Safe Plate AI. Holds the Gemini API key server-side,
// enforces per-device and global daily request caps, and requires a
// shared-secret header so the endpoints aren't wide open to the internet.
//
// Run locally:
//   dart pub get
//   GEMINI_API_KEY=your-key APP_SHARED_SECRET=your-secret dart run bin/server.dart
//
// Deploy: see server/README.md.

import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'package:safe_plate_ai_server/gemini_client.dart' as gemini;
import 'package:safe_plate_ai_server/models/challenge_profile.dart';
import 'package:safe_plate_ai_server/rate_limiter.dart';

final _rateLimiter = RateLimiter(
  perDeviceDailyLimit: int.tryParse(Platform.environment['PER_DEVICE_DAILY_LIMIT'] ?? '') ?? 40,
  globalDailyBudget: int.tryParse(Platform.environment['GLOBAL_DAILY_BUDGET'] ?? '') ?? 2000,
);

String? get _appSharedSecret => Platform.environment['APP_SHARED_SECRET'];

Response _json(Object body, {int status = 200}) => Response(
      status,
      body: jsonEncode(body),
      headers: {'Content-Type': 'application/json'},
    );

Middleware _authAndRateLimit() {
  return (Handler innerHandler) {
    return (Request request) async {
      final secret = _appSharedSecret;
      if (secret != null && secret.isNotEmpty) {
        if (request.headers['x-app-secret'] != secret) {
          return _json({'error': 'Unauthorized'}, status: 401);
        }
      }

      final deviceId = request.headers['x-device-id'];
      if (deviceId == null || deviceId.isEmpty) {
        return _json({'error': 'Missing X-Device-Id header'}, status: 400);
      }

      final rejection = _rateLimiter.check(deviceId);
      if (rejection != null) {
        return _json({'error': rejection}, status: 429);
      }

      return innerHandler(request);
    };
  };
}

Future<Response> _analyzeFood(Request request) async {
  try {
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final base64Image = body['imageBase64'] as String?;
    final mimeType = body['mimeType'] as String? ?? 'image/jpeg';
    final medications = body['medications'] as String? ?? '';

    if (base64Image == null || base64Image.isEmpty) {
      return _json({'error': 'imageBase64 is required'}, status: 400);
    }

    final result = await gemini.analyzeFood(
      base64Image: base64Image,
      mimeType: mimeType,
      medications: medications,
    );
    return _json(result);
  } on gemini.GeminiException catch (e) {
    return _json({'error': e.message}, status: e.statusCode);
  } catch (e) {
    return _json({'error': 'Bad request: $e'}, status: 400);
  }
}

Future<Response> _coachFree(Request request) async {
  try {
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final profile = ChallengeProfile.fromWireJson(body['profile'] as Map<String, dynamic>);
    final result = await gemini.generateFirstHalf(profile);
    return _json(result);
  } on gemini.GeminiException catch (e) {
    return _json({'error': e.message}, status: e.statusCode);
  } catch (e) {
    return _json({'error': 'Bad request: $e'}, status: 400);
  }
}

Future<Response> _coachPremium(Request request) async {
  try {
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final profile = ChallengeProfile.fromWireJson(body['profile'] as Map<String, dynamic>);
    // TODO(purchase-verification): before generating, verify body['purchaseToken']
    // against the Google Play Developer API so premium content can't be
    // requested without a real purchase. See server/README.md phase 2.
    final result = await gemini.generatePremiumPlan(profile);
    return _json(result);
  } on gemini.GeminiException catch (e) {
    return _json({'error': e.message}, status: e.statusCode);
  } catch (e) {
    return _json({'error': 'Bad request: $e'}, status: 400);
  }
}

void main(List<String> args) async {
  // Fail fast and loud if the key is missing, rather than 500ing on first request.
  if ((Platform.environment['GEMINI_API_KEY'] ?? '').isEmpty) {
    stderr.writeln('FATAL: GEMINI_API_KEY environment variable is not set.');
    exit(1);
  }
  if ((_appSharedSecret ?? '').isEmpty) {
    stderr.writeln(
      'WARNING: APP_SHARED_SECRET is not set — endpoints are reachable by anyone '
      'who finds the URL. Set it before deploying publicly.',
    );
  }

  final protectedRouter = Router()
    ..post('/analyze-food', _analyzeFood)
    ..post('/coach/free', _coachFree)
    ..post('/coach/premium', _coachPremium);

  final protectedHandler =
      const Pipeline().addMiddleware(_authAndRateLimit()).addHandler(protectedRouter.call);

  final router = Router()
    ..get('/health', (Request request) => Response.ok('ok'))
    ..mount('/v1', protectedHandler);

  final handler = const Pipeline().addMiddleware(logRequests()).addHandler(router.call);

  Stream.periodic(const Duration(hours: 1)).listen((_) => _rateLimiter.sweep());

  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  print('Safe Plate AI proxy listening on port ${server.port}');
}
