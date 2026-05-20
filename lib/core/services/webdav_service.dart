import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

class WebDavFile {
  final String name;
  final int sizeBytes;
  final DateTime? modifiedDate;

  const WebDavFile({
    required this.name,
    required this.sizeBytes,
    this.modifiedDate,
  });

  String get sizeFormatted {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    if (sizeBytes < 1024 * 1024 * 1024) return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class WebdavService {
  static const String _backupFolder = 'jav_manager_backups';

  Uri _buildUri(String serverUrl, String path) {
    final base = serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl;
    return Uri.parse('$base/$path');
  }

  Map<String, String> _authHeaders(String username, String password) {
    final basicAuth = 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
    return {'Authorization': basicAuth};
  }

  /// List backup files in the remote backup folder.
  Future<List<WebDavFile>> listBackups({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    try {
      final uri = _buildUri(serverUrl, _backupFolder);
      final headers = {
        ..._authHeaders(username, password),
        'Depth': '1',
      };

      final request = http.Request('PROPFIND', uri);
      request.headers.addAll(headers);
      final response = await request.send();

      final statusCode = response.statusCode;
      if (statusCode == 207) {
        final body = await response.stream.bytesToString();
        debugPrint('[WebDAV] PROPFIND body length: ${body.length}');
        debugPrint('[WebDAV] PROPFIND body start: ${body.substring(0, body.length > 300 ? 300 : body.length)}');
        return _parsePropfindResponse(body);
      } else if (statusCode == 404) {
        // Folder doesn't exist yet - create it
        await _createFolder(serverUrl, username, password);
        return [];
      } else {
        debugPrint('[WebDAV] PROPFIND failed: $statusCode');
        return [];
      }
    } catch (e) {
      debugPrint('[WebDAV] listBackups error: $e');
      return [];
    }
  }

  /// Upload the local database file to WebDAV.
  Future<bool> uploadBackup({
    required String serverUrl,
    required String username,
    required String password,
    required String localDbPath,
  }) async {
    try {
      final file = File(localDbPath);
      if (!file.existsSync()) {
        debugPrint('[WebDAV] Local DB file not found: $localDbPath');
        return false;
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'jav_manager_$timestamp.db';
      final uri = _buildUri(serverUrl, '$_backupFolder/$fileName');
      final bytes = await file.readAsBytes();

      // Ensure backup folder exists
      await _createFolder(serverUrl, username, password);

      final response = await http.put(
        uri,
        headers: {
          ..._authHeaders(username, password),
          'Content-Type': 'application/octet-stream',
        },
        body: bytes,
      );

      if (response.statusCode == 201 || response.statusCode == 200 || response.statusCode == 204) {
        debugPrint('[WebDAV] Backup uploaded: $fileName');
        return true;
      } else {
        debugPrint('[WebDAV] Upload failed: ${response.statusCode} ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('[WebDAV] uploadBackup error: $e');
      return false;
    }
  }

  /// Download a backup file to local path.
  Future<bool> downloadBackup({
    required String serverUrl,
    required String username,
    required String password,
    required String remoteFileName,
    required String localPath,
  }) async {
    try {
      final uri = _buildUri(serverUrl, '$_backupFolder/$remoteFileName');
      final response = await http.get(
        uri,
        headers: _authHeaders(username, password),
      );

      if (response.statusCode == 200) {
        final file = File(localPath);
        await file.writeAsBytes(response.bodyBytes);
        debugPrint('[WebDAV] Downloaded: $remoteFileName -> $localPath');
        return true;
      } else {
        debugPrint('[WebDAV] Download failed: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('[WebDAV] downloadBackup error: $e');
      return false;
    }
  }

  /// Delete a remote backup file.
  Future<bool> deleteBackup({
    required String serverUrl,
    required String username,
    required String password,
    required String remoteFileName,
  }) async {
    try {
      final uri = _buildUri(serverUrl, '$_backupFolder/$remoteFileName');
      final response = await http.delete(
        uri,
        headers: _authHeaders(username, password),
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        debugPrint('[WebDAV] Deleted: $remoteFileName');
        return true;
      } else {
        debugPrint('[WebDAV] Delete failed: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('[WebDAV] deleteBackup error: $e');
      return false;
    }
  }

  /// Import: download a backup to a temp file.
  /// Returns the temp path on success. Caller is responsible for closing DB
  /// and replacing the live database file.
  Future<String?> importBackup({
    required String serverUrl,
    required String username,
    required String password,
    required String remoteFileName,
    required String localDbPath,
  }) async {
    try {
      final tempPath = '$localDbPath.restored';
      final success = await downloadBackup(
        serverUrl: serverUrl,
        username: username,
        password: password,
        remoteFileName: remoteFileName,
        localPath: tempPath,
      );

      if (success) {
        final tempFile = File(tempPath);
        if (tempFile.existsSync()) {
          debugPrint('[WebDAV] Downloaded backup to: $tempPath');
          return tempPath;
        }
      }
      return null;
    } catch (e) {
      debugPrint('[WebDAV] importBackup error: $e');
      return null;
    }
  }

  /// Create the backup folder on WebDAV server (MKCOL).
  Future<void> _createFolder(String serverUrl, String username, String password) async {
    try {
      final uri = _buildUri(serverUrl, _backupFolder);
      final request = http.Request('MKCOL', uri);
      request.headers.addAll(_authHeaders(username, password));
      final response = await request.send();

      // 201 = created, 405 = already exists
      debugPrint(
        '[WebDAV] MKCOL status: ${response.statusCode}',
      );
    } catch (e) {
      debugPrint('[WebDAV] _createFolder error: $e');
    }
  }

  /// Parse WebDAV PROPFIND XML response.
  /// Handles various namespace prefixes (D:, d:, lp1:, etc.) across different servers.
  List<WebDavFile> _parsePropfindResponse(String xmlBody) {
    final files = <WebDavFile>[];
    try {
      final document = XmlDocument.parse(xmlBody);

      // Collect all response elements regardless of namespace prefix
      final responses = _findResponseElements(document);
      debugPrint('[WebDAV] Found ${responses.length} response elements');

      for (final response in responses) {
        final href = _findChildText(response, ['D:href', 'd:href', 'lp1:href']);
        if (href == null || href.endsWith('/')) continue; // Skip folder entries

        final name = href.split('/').last;
        if (name.isEmpty) continue;

        final propstat = _findChild(response, ['D:propstat', 'd:propstat', 'lp1:propstat']);
        if (propstat == null) continue;

        final status = _findChildText(propstat, ['D:status', 'd:status', 'lp1:status']) ?? '';
        if (!status.contains('200')) continue;

        final prop = _findChild(propstat, ['D:prop', 'd:prop', 'lp1:prop']);
        if (prop == null) continue;

        final sizeStr = _findChildText(prop, ['D:getcontentlength', 'd:getcontentlength', 'lp1:getcontentlength']);
        final dateStr = _findChildText(prop, ['D:getlastmodified', 'd:getlastmodified', 'lp1:getlastmodified']);

        final size = int.tryParse(sizeStr ?? '0') ?? 0;
        DateTime? date;
        if (dateStr != null) {
          date = DateTime.tryParse(dateStr);
        }

        files.add(WebDavFile(
          name: name,
          sizeBytes: size,
          modifiedDate: date ?? DateTime.now(),
        ));
      }
    } catch (e) {
      debugPrint('[WebDAV] XML parse error: $e');
    }

    // Sort by date descending (newest first)
    files.sort((a, b) {
      final da = a.modifiedDate ?? DateTime(2000);
      final db = b.modifiedDate ?? DateTime(2000);
      return db.compareTo(da);
    });

    debugPrint('[WebDAV] Parsed ${files.length} backup files');
    return files;
  }

  /// Find all response elements in the document tree, matching any namespace prefix.
  List<XmlElement> _findResponseElements(XmlNode root) {
    final result = <XmlElement>[];
    for (final node in root.descendants) {
      if (node is XmlElement) {
        final localName = node.name.toString().split(':').last;
        if (localName == 'response') {
          result.add(node);
        }
      }
    }
    return result;
  }

  /// Find a child element of [parent] matching one of the [candidates] tag names.
  XmlElement? _findChild(XmlElement parent, List<String> candidates) {
    for (final child in parent.children) {
      if (child is XmlElement && candidates.contains(child.name.toString())) {
        return child;
      }
    }
    return null;
  }

  /// Find text content of a child element of [parent] matching one of [candidates].
  String? _findChildText(XmlElement parent, List<String> candidates) {
    for (final child in parent.children) {
      if (child is XmlElement && candidates.contains(child.name.toString())) {
        return child.innerText;
      }
    }
    return null;
  }
}