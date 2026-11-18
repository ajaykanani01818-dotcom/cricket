import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/env.dart';
import 'json.dart';

/// Ported from RN `src/services/api.ts`.
class PageInfo {
  final int total, perPage, page, totalPages;
  const PageInfo({this.total = 0, this.perPage = 0, this.page = 1, this.totalPages = 0});

  factory PageInfo.fromJson(dynamic v) {
    final m = J.map(v);
    final perPage = J.integer(m['perPage']) ?? 0;
    final total = J.integer(m['total']) ?? 0;
    return PageInfo(
      total: total,
      perPage: perPage,
      page: J.integer(m['page']) ?? 1,
      totalPages: J.integer(m['totalPages']) ?? (perPage > 0 ? (total / perPage).ceil() : 0),
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

  const ApiResponse({required this.message, required this.data, this.pageInfo, this.raw = const {}});

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
      (statusCode == 400 && RegExp(r"doesn't exist|does not exist|not found", caseSensitive: false).hasMatch(message));

  bool get isNetwork => statusCode == 0;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Human message for any error thrown by a service call.
String friendlyError(Object e) {
  if (e is ApiException) {
    if (e.isNetwork) return 'Unable to reach the server. Check your connection and try again.';
    return e.message;
  }
  return 'Something went wrong. Please try again.';
}

class ApiClient {
  ApiClient({http.Client? client, String? baseUrl, String? apiKey, this.timeout = const Duration(seconds: 15), List<Duration>? retryDelays})
      : _client = client ?? http.Client(),
        baseUrl = baseUrl ?? Env.apiBaseUrl,
        apiKey = apiKey ?? Env.apiKey,
        retryDelays = retryDelays ?? const [Duration(seconds: 1), Duration(seconds: 3)];

  final http.Client _client;
  final String baseUrl;
  final String apiKey;
  final Duration timeout;
  final List<Duration> retryDelays;

  static ApiClient instance = ApiClient();

  Map<String, String> get _headers => {
        'Accept': 'application/json, text/plain, */*',
        'Content-Type': 'application/json',
        'sb-live-score-api-key': apiKey,
      };

  Uri buildUri(String endpoint, [Map<String, Object?>? params]) {
    final q = <String, String>{};
    params?.forEach((k, v) {
      if (v != null && k != '_') q[k] = v.toString();
    });
    final uri = Uri.parse('$baseUrl$endpoint');
    return q.isEmpty ? uri : uri.replace(queryParameters: {...uri.queryParameters, ...q});
  }

  static String _serverErrorMessage(int status) {
    if (status == 502 || status == 503) return 'Service temporarily unavailable. Please try again later.';
    if (status == 504) return 'Request timed out. Please try again.';
    return 'HTTP error! status: $status';
  }

  /// GET with timeout and retries (network errors and 5xx only; 4xx throw at once).
  Future<ApiResponse> get(String endpoint, [Map<String, Object?>? params]) async {
    if (baseUrl.isEmpty) {
      throw const ApiException(0, 'API is not configured. Run with --dart-define-from-file=env/local.json');
    }
    final uri = buildUri(endpoint, params);
    ApiException? lastError;

    for (var attempt = 0; attempt <= retryDelays.length; attempt++) {
      if (attempt > 0) await Future<void>.delayed(retryDelays[attempt - 1]);
      try {
        final res = await _client.get(uri, headers: _headers).timeout(timeout);
        if (res.statusCode >= 200 && res.statusCode < 300) {
          final body = jsonDecode(utf8.decode(res.bodyBytes));
          return ApiResponse.fromJson(J.map(body));
        }
        String msg = _serverErrorMessage(res.statusCode);
        try {
          final body = J.map(jsonDecode(utf8.decode(res.bodyBytes)));
          msg = J.text(body['message']) ?? J.text(body['error']) ?? msg;
        } catch (_) {}
        final err = ApiException(res.statusCode, msg);
        if (res.statusCode < 500) throw err;
        lastError = err;
      } on ApiException {
        rethrow;
      } on TimeoutException {
        lastError = const ApiException(0, 'Request timed out. Please try again.');
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
