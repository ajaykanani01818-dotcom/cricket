import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../config/env.dart';
import 'json.dart';
import 'sbx1.dart';

/// Ported from RN `src/services/api.ts`.
class PageInfo {
  final int total, perPage, page, totalPages;
  const PageInfo({
    this.total = 0,
    this.perPage = 0,
    this.page = 1,
    this.totalPages = 0,
  });

  factory PageInfo.fromJson(dynamic v) {
    final m = J.map(v);
    final perPage = J.integer(m['perPage']) ?? 0;
    final total = J.integer(m['total']) ?? 0;
    return PageInfo(
      total: total,
      perPage: perPage,
      page: J.integer(m['page']) ?? 1,
      totalPages:
          J.integer(m['totalPages']) ??
          (perPage > 0 ? (total / perPage).ceil() : 0),
    );
  }
}

class ApiResponse {
  final String message;
  final dynamic data;
  final PageInfo? pageInfo;

  /// The whole decoded body (some endpoints carry extra top-level keys such as
  /// `page`, `perPage`, `totalCount`, `pagination`).
  final JsonMap raw;

  const ApiResponse({
    required this.message,
    required this.data,
    this.pageInfo,
    this.raw = const {},
  });

  factory ApiResponse.fromJson(JsonMap json) => ApiResponse(
    message: J.str(json['message']),
    data: json['data'],
    pageInfo: json['pageInfo'] != null
        ? PageInfo.fromJson(json['pageInfo'])
        : json['pagination'] != null
        ? PageInfo.fromJson(json['pagination'])
        : null,
    raw: json,
  );

  List<JsonMap> get dataList => J.maps(data);
  JsonMap get dataMap => J.map(data);
}

class ApiException implements Exception {
  final int statusCode; // 0 = network/timeout
  final String message;
  const ApiException(this.statusCode, this.message);

  bool get isNotFound =>
      statusCode == 404 ||
      (statusCode == 400 &&
          RegExp(
            r"doesn't exist|does not exist|not found",
            caseSensitive: false,
          ).hasMatch(message));

  bool get isNetwork => statusCode == 0;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Human message for any error thrown by a service call.
String friendlyError(Object e) {
  if (e is ApiException) {
    if (e.isNetwork) {
      return 'Unable to reach the server. Check your connection and try again.';
    }
    return e.message;
  }
  return 'Something went wrong. Please try again.';
}

/// SBX1 client: every call is `POST {baseUrl}/{token}` with an encrypted,
/// authenticated envelope (docs/SECURITY_PROTOCOL.md).
class ApiClient {
  ApiClient({
    http.Client? client,
    String? baseUrl,
    List<int>? secret,
    this.timeout = const Duration(seconds: 15),
    List<Duration>? retryDelays,
    DateTime Function()? clock,
    Random? random,
  }) : _client = client ?? http.Client(),
       baseUrl = (baseUrl ?? Env.apiBaseUrl).replaceAll(RegExp(r'/+$'), ''),
       _secret = secret ?? Env.secretBytes,
       retryDelays =
           retryDelays ?? const [Duration(seconds: 1), Duration(seconds: 3)],
       _clock = clock ?? DateTime.now,
       // ignore: prefer_initializing_formals
       _random = random;

  final http.Client _client;
  final String baseUrl;
  final List<int>? _secret;
  final Duration timeout;
  final List<Duration> retryDelays;
  final DateTime Function() _clock;
  final Random? _random;

  /// server time minus device time, learned from the HTTP `Date` header when
  /// the device clock is off by more than [_skewTolerance].
  Duration clockOffset = Duration.zero;
  static const _skewTolerance = Duration(seconds: 60);

  static ApiClient instance = ApiClient();

  static String _serverErrorMessage(int status) {
    if (status == 502 || status == 503) {
      return 'Service temporarily unavailable. Please try again later.';
    }
    if (status == 504) return 'Request timed out. Please try again.';
    return 'HTTP error! status: $status';
  }

  /// Returns true when the offset changed.
  bool _learnClock(http.BaseResponse res) {
    final h = res.headers['date'];
    if (h == null) return false;
    try {
      final diff = HttpDate.parse(h).difference(_clock().toUtc());
      final next = diff.abs() > _skewTolerance ? diff : Duration.zero;
      final changed = (next - clockOffset).abs() > _skewTolerance;
      clockOffset = next;
      return changed;
    } catch (_) {
      return false;
    }
  }

  /// Calls the route [token] with [params] (path + query params merged; null
  /// values dropped). Timeout and retries: network errors and 5xx only.
  /// Identical requests that are already in flight share one round trip
  /// (Home, Live and the search warm-up often ask for the same list at the
  /// same moment on a cold start). Every route is a read, so sharing is safe.
  final Map<String, Future<ApiResponse>> _inFlight = {};

  Future<ApiResponse> call(String token, [Map<String, Object?>? params]) {
    final key = '$token|${_canonicalParams(params)}';
    final existing = _inFlight[key];
    if (existing != null) return existing;
    final f = _call(token, params);
    _inFlight[key] = f;
    // Clear on completion (success or failure); never let this chain throw.
    // (Statement bodies on purpose: returning the removed Future would re-throw
    // its error into this chain's own, unobserved, Future.)
    f.then<void>((_) {
      _inFlight.remove(key);
    }, onError: (Object _) {
      _inFlight.remove(key);
    });
    return f;
  }

  static String _canonicalParams(Map<String, Object?>? params) {
    if (params == null || params.isEmpty) return '';
    final keys = params.keys.where((k) => params[k] != null && k != '_').toList()..sort();
    return keys.map((k) => '$k=${params[k]}').join('&');
  }

  Future<ApiResponse> _call(String token, [Map<String, Object?>? params]) async {
    final secret = _secret;
    if (baseUrl.isEmpty || secret == null) {
      throw const ApiException(
        0,
        'API is not configured. Run with --dart-define-from-file=env/local.json',
      );
    }
    final p = <String, Object?>{};
    params?.forEach((k, v) {
      if (v != null && k != '_') p[k] = v;
    });
    final uri = Uri.parse('$baseUrl/$token');
    ApiException? lastError;
    var skewRetried = false;

    for (var attempt = 0; attempt <= retryDelays.length; attempt++) {
      if (attempt > 0) await Future<void>.delayed(retryDelays[attempt - 1]);
      try {
        final nonce = Sbx1.randomBytes(16, _random);
        final ts = _clock().add(clockOffset).millisecondsSinceEpoch;
        final env = await Sbx1.buildRequest(
          secret: secret,
          token: token,
          params: p,
          ts: ts,
          nonce: nonce,
          iv: Sbx1.randomBytes(12, _random),
        );
        final res = await _client
            .post(
              uri,
              headers: const {
                'Accept': 'application/json',
                'Content-Type': 'application/json',
                'x-kid': '1',
              },
              body: jsonEncode(env.toJson()),
            )
            .timeout(timeout);
        final clockChanged = _learnClock(res);

        if (res.statusCode == 404 && clockChanged && !skewRetried) {
          // Probably rejected for a stale timestamp: retry once with the corrected clock.
          skewRetried = true;
          attempt--;
          continue;
        }
        if (res.statusCode != 200) {
          final err = ApiException(
            res.statusCode,
            res.statusCode == 404
                ? 'Not Found'
                : _serverErrorMessage(res.statusCode),
          );
          if (res.statusCode < 500) throw err;
          lastError = err;
          continue;
        }

        final Map<String, dynamic> payload;
        try {
          payload = await Sbx1.parseResponse(
            secret: secret,
            nonceB64: env.n,
            body: jsonDecode(utf8.decode(res.bodyBytes)),
          );
        } on Sbx1Exception {
          throw const ApiException(-1, 'Invalid response from server.');
        } on FormatException {
          throw const ApiException(-1, 'Invalid response from server.');
        }
        final status = payload['s'] is int ? payload['s'] as int : 0;
        final inner = payload['b'];
        if (status >= 200 && status < 300) {
          if (inner is! Map) {
            throw const ApiException(-1, 'Invalid response from server.');
          }
          return ApiResponse.fromJson(J.map(inner));
        }
        var msg = _serverErrorMessage(status);
        if (inner is Map) {
          msg = J.text(inner['message']) ?? J.text(inner['error']) ?? msg;
        }
        final err = ApiException(status, msg);
        if (status < 500) throw err;
        lastError = err;
      } on ApiException {
        rethrow;
      } on TimeoutException {
        lastError = const ApiException(
          0,
          'Request timed out. Please try again.',
        );
      } on SocketException catch (e) {
        lastError = ApiException(0, 'Network error: ${e.message}');
      } on http.ClientException catch (e) {
        lastError = ApiException(0, 'Network error: ${e.message}');
      } on FormatException {
        throw const ApiException(-1, 'Invalid response from server.');
      }
    }
    throw lastError ?? const ApiException(0, 'Request failed.');
  }
}
