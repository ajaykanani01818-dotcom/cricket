import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';

/// In-app update gate — ported from RN `src/config/versionGate.ts`.
///
/// Nothing currently sets a minimum version (no remote config source), so
/// [versionGateConfig] is null and [VersionUpdateGate] renders only its child.
/// Kept as working infrastructure in case a version check is wired back in.
class VersionGateConfig {
  const VersionGateConfig({
    required this.minimumAppVersion,
    this.forceUpdate = false,
    this.playStoreUrl = 'https://play.google.com/store/apps/details?id=com.crickbex.dark',
    this.appStoreUrl = 'https://apps.apple.com/search?term=CrickBex&entity=software',
  });

  final String minimumAppVersion;
  final bool forceUpdate;
  final String playStoreUrl;
  final String appStoreUrl;
}

/// Inert (same as RN): no minimum version configured.
const VersionGateConfig? versionGateConfig = null;

const _updateBrief = 'Just 2 minutes to update and access new features. Feel faster.';

/// Semver-style compare on numeric major.minor.patch segments (leading `v`
/// and non-numeric suffixes ignored). -1 if a < b, 0 if equal, 1 if a > b.
int compareSemver(String a, String b) {
  List<int> norm(String s) => s.trim().replaceFirst(RegExp(r'^v', caseSensitive: false), '').split('.').map((part) {
        final m = RegExp(r'^\d+').firstMatch(part);
        return m == null ? 0 : int.tryParse(m.group(0)!) ?? 0;
      }).toList();
  final pa = norm(a), pb = norm(b);
  final n = [pa.length, pb.length, 3].reduce((x, y) => x > y ? x : y);
  for (var i = 0; i < n; i++) {
    final da = i < pa.length ? pa[i] : 0;
    final db = i < pb.length ? pb[i] : 0;
    if (da < db) return -1;
    if (da > db) return 1;
  }
  return 0;
}

/// True when [installed] is strictly lower than the configured minimum.
bool isUpdateRequired(String installed, VersionGateConfig? config) {
  final min = config?.minimumAppVersion.trim() ?? '';
  if (min.isEmpty) return false;
  return compareSemver(installed.trim().isEmpty ? '0.0.0' : installed, min) < 0;
}

Future<String> _installedVersion() async {
  try {
    final v = (await PackageInfo.fromPlatform()).version.trim();
    return v.isEmpty ? '0.0.0' : v;
  } catch (_) {
    return '0.0.0';
  }
}

/// Shows a blocking (force) or dismissible "New version ready" card above
/// [child] when the installed version is below the configured minimum.
/// With the default inert config it never reads the version or shows anything.
class VersionUpdateGate extends StatefulWidget {
  const VersionUpdateGate({
    super.key,
    required this.child,
    this.config = versionGateConfig,
    this.installedVersion,
    this.openStore,
  });

  final Widget child;
  final VersionGateConfig? config;

  /// Injected in tests; defaults to package_info_plus.
  final Future<String> Function()? installedVersion;

  /// Injected in tests; defaults to url_launcher.
  final Future<void> Function(String url)? openStore;

  @override
  State<VersionUpdateGate> createState() => _VersionUpdateGateState();
}

class _VersionUpdateGateState extends State<VersionUpdateGate> with WidgetsBindingObserver {
  bool _needsUpdate = false;
  bool _softDismissed = false;

  bool get _visible => widget.config != null && _needsUpdate && (widget.config!.forceUpdate || !_softDismissed);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  Future<void> _check() async {
    final cfg = widget.config;
    if (cfg == null || cfg.minimumAppVersion.trim().isEmpty) return;
    final v = await (widget.installedVersion ?? _installedVersion)();
    if (!mounted) return;
    setState(() => _needsUpdate = isUpdateRequired(v, cfg));
  }

  @override
  Future<bool> didPopRoute() async {
    if (!_visible) return false;
    // Force update: back does nothing. Soft: back = "Maybe later".
    if (!widget.config!.forceUpdate) _maybeLater();
    return true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _openStore() async {
    final cfg = widget.config;
    if (cfg == null) return;
    final url = defaultTargetPlatform == TargetPlatform.iOS ? cfg.appStoreUrl : cfg.playStoreUrl;
    try {
      if (widget.openStore != null) {
        await widget.openStore!(url);
      } else {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  void _maybeLater() {
    if (widget.config?.forceUpdate ?? true) return;
    setState(() => _softDismissed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return widget.child;
    final force = widget.config!.forceUpdate;
    return Stack(fit: StackFit.expand, children: [
      widget.child,
      Positioned.fill(
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            color: const Color(0x66000000),
            padding: EdgeInsets.fromLTRB(24, MediaQuery.paddingOf(context).top, 24, MediaQuery.paddingOf(context).bottom),
            alignment: Alignment.center,
            child: Semantics(
              liveRegion: true,
              child: Container(
                key: const ValueKey('version_gate_card'),
                constraints: const BoxConstraints(maxWidth: 420),
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.borderNeutral),
                  boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 24, offset: Offset(0, 12))],
                ),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Center(
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.borderNeutral),
                        gradient: const LinearGradient(
                            begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.pitchLight, AppColors.pitch]),
                      ),
                      child: const Icon(Icons.rocket_launch, size: 44, color: AppColors.goldLight),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text('New version ready',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.pitchDark, letterSpacing: -0.35)),
                  const SizedBox(height: 10),
                  const Text(_updateBrief,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, height: 22 / 15, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 24),
                  Semantics(
                    button: true,
                    label: 'Update app in store',
                    child: InkWell(
                      key: const ValueKey('version_gate_update'),
                      onTap: _openStore,
                      borderRadius: BorderRadius.circular(10),
                      child: Ink(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          gradient: const LinearGradient(colors: [AppColors.goldLight, AppColors.gold]),
                        ),
                        child: const SizedBox(
                          height: 48,
                          child: Center(
                            child: Text('Update now',
                                style: TextStyle(color: AppColors.pitchDark, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (!force) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      key: const ValueKey('version_gate_later'),
                      onPressed: _maybeLater,
                      child: const Text('Maybe later',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.pitch, letterSpacing: 0.15)),
                    ),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}
