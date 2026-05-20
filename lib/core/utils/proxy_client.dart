import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'app_settings.dart';

/// Read Windows system proxy from registry.
/// Returns the proxy URL (e.g. "127.0.0.1:7890") or null if not set/disabled.
String? _readWindowsSystemProxy() {
  try {
    // Use reg query to read Internet Settings
    final result = Process.runSync(
      'reg',
      [
        'query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v',
        'ProxyEnable',
      ],
      runInShell: true,
    );
    final output = result.stdout.toString();
    // Check if ProxyEnable is 0x1
    if (!output.contains('0x1')) {
      if (kDebugMode) debugPrint('[Proxy] System proxy is disabled');
      return null;
    }

    final serverResult = Process.runSync(
      'reg',
      [
        'query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v',
        'ProxyServer',
      ],
      runInShell: true,
    );
    final serverOutput = serverResult.stdout.toString();
    // Extract the proxy server value
    final match = RegExp(r'ProxyServer\s+REG_SZ\s+(.+)').firstMatch(serverOutput);
    if (match != null) {
      final proxy = match.group(1)!.trim();
      if (kDebugMode) debugPrint('[Proxy] System proxy: $proxy');
      return proxy;
    }
    return null;
  } catch (e) {
    if (kDebugMode) debugPrint('[Proxy] Failed to read system proxy: $e');
    return null;
  }
}

/// Creates an HTTP client that respects the proxy settings.
/// [proxyMode]: 'none' | 'system' | 'custom'
/// [proxyUrl]: required when proxyMode is 'custom', e.g. '127.0.0.1:7890'
http.Client createProxyClient({String? proxyMode, String? proxyUrl}) {
  final mode = proxyMode ?? 'none';

  if (mode == 'none') {
    if (kDebugMode) debugPrint('[Proxy] No proxy');
    return http.Client();
  }

  final httpClient = HttpClient();

  if (mode == 'system') {
    final systemProxy = _readWindowsSystemProxy();
    if (systemProxy != null) {
      httpClient.findProxy = (uri) {
        if (kDebugMode) debugPrint('[Proxy] Using system proxy: $systemProxy for ${uri.host}');
        return 'PROXY $systemProxy';
      };
    } else {
      // Fall back to environment variables
      httpClient.findProxy = HttpClient.findProxyFromEnvironment;
      if (kDebugMode) debugPrint('[Proxy] System proxy not found, using environment');
    }
  } else if (mode == 'custom' && proxyUrl != null && proxyUrl.isNotEmpty) {
    httpClient.findProxy = (uri) {
      if (kDebugMode) debugPrint('[Proxy] Using custom proxy: $proxyUrl for ${uri.host}');
      return 'PROXY $proxyUrl';
    };
  }

  httpClient.badCertificateCallback = (cert, host, port) => true;

  return IOClient(httpClient);
}

/// Convenience: read proxy settings from SharedPreferences and create a client.
Future<http.Client> createProxyClientFromPrefs() async {
  final prefs = await AppSettings.load();
  final proxyMode = prefs.getString('proxy_mode') ?? 'none';
  final proxyUrl = prefs.getString('proxy_url') ?? '';
  return createProxyClient(proxyMode: proxyMode, proxyUrl: proxyUrl);
}

/// Test if the proxy can reach a URL. Returns true if accessible.
Future<bool> testProxyConnection(String testUrl) async {
  try {
    final client = await createProxyClientFromPrefs();
    final response = await client.get(
      Uri.parse(testUrl),
      headers: {'User-Agent': 'JAV-Manager/1.0'},
    ).timeout(const Duration(seconds: 10));
    client.close();
    return response.statusCode == 200;
  } catch (e) {
    if (kDebugMode) debugPrint('[Proxy] Test failed: $e');
    return false;
  }
}
