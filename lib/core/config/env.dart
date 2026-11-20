import 'dart:convert';
import 'dart:typed_data';

/// Build-time configuration. The app talks ONLY to the livescore-postdata
/// SBX1 gateway. Run:
///   flutter run --dart-define-from-file=env/local.json
///
/// `API_BASE_URL` is the gateway base (`<origin>/api/x`). The shared secret is
/// either `API_SECRET` (base64, 32 bytes) or split into fragments
/// `API_SECRET_A/B/C` (+ optional `_D`), each XOR-masked with `API_MASK`
/// (base64) and reassembled at runtime so the secret never appears as one
/// string in the binary. See [SecretFragments].
class Env {
  Env._();

  static const String apiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const String _secret = String.fromEnvironment('API_SECRET');
  static const String _a = String.fromEnvironment('API_SECRET_A');
  static const String _b = String.fromEnvironment('API_SECRET_B');
  static const String _c = String.fromEnvironment('API_SECRET_C');
  static const String _d = String.fromEnvironment('API_SECRET_D');
  static const String _mask = String.fromEnvironment('API_MASK');

  /// The 32-byte secret, or null when not configured / malformed.
  static Uint8List? get secretBytes => SecretFragments.resolve(
    secret: _secret,
    fragments: [_a, _b, _c, _d],
    mask: _mask,
  );

  static bool get isConfigured => apiBaseUrl.isNotEmpty && secretBytes != null;
}

class SecretFragments {
  SecretFragments._();

  static Uint8List _xor(List<int> data, List<int> mask) => Uint8List.fromList([
    for (var i = 0; i < data.length; i++) data[i] ^ mask[i % mask.length],
  ]);

  /// Plain secret wins; otherwise unmask + concatenate non-empty fragments.
  /// Returns null unless the result is exactly 32 bytes.
  static Uint8List? resolve({
    String secret = '',
    List<String> fragments = const [],
    String mask = '',
  }) {
    try {
      Uint8List? out;
      if (secret.isNotEmpty) {
        out = base64.decode(base64.normalize(secret));
      } else {
        final parts = fragments.where((f) => f.isNotEmpty).toList();
        if (parts.isEmpty || mask.isEmpty) return null;
        final m = base64.decode(base64.normalize(mask));
        if (m.isEmpty) return null;
        final bytes = <int>[];
        for (final p in parts) {
          bytes.addAll(_xor(base64.decode(base64.normalize(p)), m));
        }
        out = Uint8List.fromList(bytes);
      }
      return out.length == 32 ? out : null;
    } catch (_) {
      return null;
    }
  }

  /// Build tooling: split a base64 secret into [n] masked fragments.
  static List<String> split(Uint8List secret, Uint8List mask, int n) {
    final size = (secret.length / n).ceil();
    return [
      for (var i = 0; i < secret.length; i += size)
        base64.encode(
          _xor(secret.sublist(i, (i + size).clamp(0, secret.length)), mask),
        ),
    ];
  }
}
