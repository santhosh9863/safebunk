import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../providers/auth_provider.dart';
import '../providers/safebunk_auth_provider.dart';

class AuthCaptureWebViewScreen extends ConsumerStatefulWidget {
  final Uri startUri;

  const AuthCaptureWebViewScreen({
    super.key,
    required this.startUri,
  });

  @override
  ConsumerState<AuthCaptureWebViewScreen> createState() =>
      _AuthCaptureWebViewScreenState();
}

enum _CaptureState {
  loading,
  injectingJs,
  extractingToken,
  adoptingSession,
  complete,
  notAuthenticated,
  failed,
}

class _DebugEntry {
  final int hop;
  final String url;
  final bool tokenExists;
  final int tokenLength;
  final int cookieLength;
  final String title;
  final String bodySnippet;
  final bool hasDashboardMarkers;
  final bool isLoginPage;
  final String cookies;

  const _DebugEntry({
    required this.hop,
    required this.url,
    required this.tokenExists,
    required this.tokenLength,
    required this.cookieLength,
    required this.title,
    required this.bodySnippet,
    required this.hasDashboardMarkers,
    required this.isLoginPage,
    required this.cookies,
  });
}

class _AuthCaptureWebViewScreenState
    extends ConsumerState<AuthCaptureWebViewScreen> {
  _CaptureState _state = _CaptureState.loading;
  String? _errorMessage;
  WebViewController? _controller;
  Timer? _timeoutTimer;
  bool _resolved = false;
  int _navigationCount = 0;
  final List<_DebugEntry> _debugLog = [];
  bool _showDebug = false;

  static const _captureTimeout = Duration(seconds: 60);

  @override
  void initState() {
    super.initState();
    _timeoutTimer = Timer(_captureTimeout, _onTimeout);
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  void _onTimeout() {
    if (!_resolved && mounted) {
      _resolved = true;
      setState(() {
        _state = _CaptureState.notAuthenticated;
        _errorMessage = 'Session capture timed out. No authenticated session found.';
      });
    }
  }

  String _debugExtractJs() {
    return '''
(function() {
  try {
    var t = localStorage.getItem('token') || localStorage.getItem('accessToken') || '';
    var c = document.cookie || '';
    var body = document.body ? document.body.innerText || '' : '';
    var snippet = body.substring(0, 300);
    var lower = body.toLowerCase();
    var hasDashboard = lower.indexOf('dashboard') !== -1
      || lower.indexOf('attendance') !== -1
      || lower.indexOf('logout') !== -1
      || lower.indexOf('profile') !== -1
      || lower.indexOf('timetable') !== -1
      || lower.indexOf('marks') !== -1;
    var isLogin = lower.indexOf('sign in') !== -1
      || lower.indexOf('login') !== -1
      || lower.indexOf('email') !== -1
      || lower.indexOf('password') !== -1
      || lower.indexOf('sign in with google') !== -1;
    var hasPhpsessid = c.indexOf('PHPSESSID') !== -1;
    var hasAuthSession = c.indexOf('AUTH_SESSION') !== -1;
    var localStorageKeys = Object.keys(localStorage).join(',');

    return JSON.stringify({
      url: location.href,
      title: document.title || '',
      token: t,
      tokenExists: !!t,
      tokenLength: t.length,
      cookieLength: c.length,
      cookies: c,
      hasPHPSESSID: hasPhpsessid,
      hasAUTHSESSION: hasAuthSession,
      localStorageKeys: localStorageKeys,
      bodySnippet: snippet,
      hasDashboardMarkers: hasDashboard,
      isLoginPage: isLogin
    });
  } catch(e) {
    return JSON.stringify({
      url: location.href,
      title: '',
      token: '',
      tokenExists: false,
      tokenLength: 0,
      cookieLength: 0,
      cookies: '',
      hasPHPSESSID: false,
      hasAUTHSESSION: false,
      localStorageKeys: '',
      bodySnippet: 'JS_ERROR: ' + e.toString(),
      hasDashboardMarkers: false,
      isLoginPage: false
    });
  }
})();
''';
  }

  Future<void> _injectAndDebug() async {
    if (_resolved) return;
    final controller = _controller;
    if (controller == null) return;

    setState(() => _state = _CaptureState.injectingJs);

    try {
      final raw = await controller.runJavaScriptReturningResult(_debugExtractJs());
      final result = jsonDecode(raw as String) as Map<String, dynamic>;

      final url = result['url'] as String? ?? '';
      final title = result['title'] as String? ?? '';
      final token = result['token'] as String? ?? '';
      final tokenExists = result['tokenExists'] == true;
      final tokenLength = result['tokenLength'] as int? ?? 0;
      final cookieLength = result['cookieLength'] as int? ?? 0;
      final bodySnippet = result['bodySnippet'] as String? ?? '';
      final hasDashboard = result['hasDashboardMarkers'] == true;
      final isLogin = result['isLoginPage'] == true;
      final cookies = result['cookies'] as String? ?? '';
      final hasPHPSESSID = result['hasPHPSESSID'] == true;
      final hasAuthSession = result['hasAUTHSESSION'] == true;
      final localStorageKeys = result['localStorageKeys'] as String? ?? '';

      final entry = _DebugEntry(
        hop: _navigationCount,
        url: url,
        tokenExists: tokenExists,
        tokenLength: tokenLength,
        cookieLength: cookieLength,
        title: title,
        bodySnippet: bodySnippet,
        hasDashboardMarkers: hasDashboard,
        isLoginPage: isLogin,
        cookies: cookies,
      );
      _debugLog.add(entry);

      debugPrint('');
      debugPrint('╔══════════════════════════════════════════════════════');
      debugPrint('║ [AuthCapture] === HOP $_navigationCount ===');
      debugPrint('║ URL: $url');
      debugPrint('║ Title: $title');
      debugPrint('║ Token exists: $tokenExists  |  Token length: $tokenLength');
      debugPrint('║ Cookie length: $cookieLength');
      debugPrint('║ Has PHPSESSID: $hasPHPSESSID  |  Has AUTH_SESSION: $hasAuthSession');
      debugPrint('║ Dashboard markers: $hasDashboard');
      debugPrint('║ Is login page: $isLogin');
      debugPrint('║ localStorage keys: $localStorageKeys');
      debugPrint('║ Cookies: ${cookies.length > 200 ? "${cookies.substring(0, 200)}..." : cookies}');
      debugPrint('╚══════════════════════════════════════════════════════');
      debugPrint('');

      if (isLogin && _navigationCount > 1) {
        debugPrint('[AuthCapture] ⚠️  WARNING: Page after hop 1 is still a login page — cookie jar likely NOT shared!');
        debugPrint('[AuthCapture] ⚠️  WARNING: WebView did NOT inherit Chrome Custom Tab session.');
      }

      if (_debugLog.length >= 2 && !_showDebug) {
        setState(() => _showDebug = true);
      }

      if (tokenExists && token.isNotEmpty) {
        _resolved = true;
        _timeoutTimer?.cancel();
        setState(() => _state = _CaptureState.extractingToken);

        Map<String, String>? parsedCookies;
        if (cookies.isNotEmpty) {
          parsedCookies = {};
          for (final part in cookies.split(';')) {
            final kv = part.trim().split('=');
            if (kv.length >= 2) {
              parsedCookies[kv[0].trim()] = kv.sublist(1).join('=').trim();
            }
          }
        }

        final phpsessid = parsedCookies?['PHPSESSID'];
        final authSession = parsedCookies?['AUTH_SESSION'];

        debugPrint('[AuthCapture] ✅ Token FOUND! Adopting session...');
        debugPrint('[AuthCapture] PHPSESSID=${phpsessid ?? "(not found)"}');
        debugPrint('[AuthCapture] AUTH_SESSION=${authSession ?? "(not found)"}');
        debugPrint('[AuthCapture] Token (first 50 chars): ${token.length > 50 ? "${token.substring(0, 50)}..." : token}');

        await _adoptSession(
          accessToken: token,
          phpsessid: phpsessid,
          authSession: authSession,
          cookies: parsedCookies,
        );
      } else if (tokenExists && token.isEmpty) {
        debugPrint('[AuthCapture] ⚠️  tokenExists=true but token string is empty — JS returned wrong field?');
      } else {
        debugPrint('[AuthCapture] No token yet on hop $_navigationCount — waiting for next navigation');
        if (isLogin) {
          debugPrint('[AuthCapture] ⚠️  Current page appears to be a login page — auth session NOT inherited.');
        }
      }
    } catch (e) {
      debugPrint('[AuthCapture] JS injection error: $e');
      if (!_resolved && mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _adoptSession({
    required String accessToken,
    String? phpsessid,
    String? authSession,
    Map<String, String>? cookies,
  }) async {
    if (!mounted) return;
    setState(() => _state = _CaptureState.adoptingSession);

    final notifier = ref.read(safebunkAuthProvider.notifier);
    final result = await notifier.adoptSession(
      accessToken: accessToken,
      phpsessid: phpsessid,
      authSession: authSession,
      cookies: cookies,
    );

    if (!mounted) return;

    if (result != null) {
      setState(() => _state = _CaptureState.complete);
      ref.read(authProvider.notifier).setAuthenticated();
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      setState(() {
        _state = _CaptureState.failed;
        _errorMessage = 'Backend rejected the session.';
      });
    }
  }

  void _retry() {
    _resolved = false;
    _debugLog.clear();
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(_captureTimeout, _onTimeout);
    setState(() => _state = _CaptureState.loading);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_showDebug ? 'Auth Capture Debug' : 'Completing Sign-In'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_debugLog.isNotEmpty)
            IconButton(
              icon: Icon(_showDebug ? Icons.visibility_off : Icons.bug_report),
              onPressed: () => setState(() => _showDebug = !_showDebug),
            ),
        ],
      ),
      body: _showDebug ? _buildDebugPanel(theme) : _buildMainView(theme),
    );
  }

  Widget _buildMainView(ThemeData theme) {
    if (_state == _CaptureState.loading ||
        _state == _CaptureState.injectingJs ||
        _state == _CaptureState.extractingToken ||
        _state == _CaptureState.adoptingSession) {
      return _buildWebView(theme);
    }
    return _buildStatusScreen(theme);
  }

  Widget _buildWebView(ThemeData theme) {
    return Column(
      children: [
        if (_state == _CaptureState.injectingJs ||
            _state == _CaptureState.extractingToken ||
            _state == _CaptureState.adoptingSession)
          LinearProgressIndicator(),
        if (_state == _CaptureState.loading)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Text('Loading Linways...',
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        Expanded(
          child: WebViewWidget(
            controller: _controller ?? _createController(),
          ),
        ),
      ],
    );
  }

  WebViewController _createController() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            final urlLower = url.toLowerCase();
            final isGoogleAccounts = urlLower.contains('accounts.google.com');
            final isLoginUrl = urlLower.contains('login') || urlLower.contains('signin');
            debugPrint('');
            debugPrint('╔══════════════════════════════════════════════════════');
            debugPrint('║ [AuthCapture] >>> NAVIGATION STARTED <<<');
            debugPrint('║ URL: $url');
            if (isGoogleAccounts) {
              debugPrint('║ ⚠️  WARNING: Navigating to Google Accounts — auth prompt');
            }
            if (isLoginUrl) {
              debugPrint('║ ⚠️  WARNING: URL contains login/signin — session may not be shared');
            }
            debugPrint('╚══════════════════════════════════════════════════════');
            debugPrint('');
            if (!_resolved && _navigationCount > 0) {
              setState(() => _state = _CaptureState.injectingJs);
            }
          },
          onPageFinished: (url) {
            debugPrint('[AuthCapture] Page finished: $url (hop ${_navigationCount + 1})');
            _navigationCount++;
            _injectAndDebug();
          },
          onNavigationRequest: (navReq) {
            debugPrint('[AuthCapture] Nav request: ${navReq.url}');
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(widget.startUri);

    _controller = controller;
    return controller;
  }

  Widget _buildDebugPanel(ThemeData theme) {
    return Column(
      children: [
        if (_debugLog.length > 0)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            color: Colors.amber.shade50,
            child: Text(
              'Hops: ${_debugLog.length} | Resolved: $_resolved',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: _debugLog.length,
            itemBuilder: (ctx, i) {
              final e = _debugLog[i];
              final authed = e.tokenExists;
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                color: authed ? Colors.green.shade50 : null,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Hop #${e.hop}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: authed ? Colors.green.shade700 : null,
                          )),
                      const SizedBox(height: 4),
                      _debugRow('URL', e.url, max: 80),
                      _debugRow('Title', e.title),
                      _debugRow('Token exists', '${e.tokenExists} (len=${e.tokenLength})'),
                      _debugRow('Cookie length', '${e.cookieLength}'),
                      _debugRow('Dashboard markers', '${e.hasDashboardMarkers}'),
                      _debugRow('Is login page', '${e.isLoginPage}'),
                      _debugRow('Cookies', e.cookies, max: 100),
                      const SizedBox(height: 4),
                      Text(e.bodySnippet,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            color: Colors.grey.shade700,
                          ),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _debugRow(String label, String value, {int? max}) {
    final display = max != null && value.length > max
        ? '${value.substring(0, max)}...'
        : value;
    return Padding(
      padding: const EdgeInsets.only(top: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text('$label:',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                )),
          ),
          Expanded(
            child: Text(display.isEmpty ? '(empty)' : display,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusScreen(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _statusIcon(),
            const SizedBox(height: 24),
            Text(
              _statusMessage(),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: _state == _CaptureState.failed ||
                        _state == _CaptureState.notAuthenticated
                    ? Colors.red.shade700
                    : null,
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
            ],
            if (_state == _CaptureState.failed ||
                _state == _CaptureState.notAuthenticated) ...[
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _retry,
                child: const Text('Try Again'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go Back'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusIcon() {
    switch (_state) {
      case _CaptureState.complete:
        return const Icon(Icons.check_circle, color: Colors.green, size: 56);
      case _CaptureState.failed:
      case _CaptureState.notAuthenticated:
        return const Icon(Icons.error_outline, color: Colors.red, size: 56);
      default:
        return const SizedBox(
          width: 48, height: 48,
          child: CircularProgressIndicator(strokeWidth: 3),
        );
    }
  }

  String _statusMessage() {
    switch (_state) {
      case _CaptureState.complete:
        return 'Signed in successfully!';
      case _CaptureState.failed:
        return 'Session adoption failed.';
      case _CaptureState.notAuthenticated:
        return 'No authenticated session found.\nMake sure you completed the Google sign-in.';
      default:
        return '';
    }
  }
}
