import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:path/path.dart' as path;
import '../models/models.dart';
import '../repositories/actor_repository.dart';
import '../utils/proxy_client.dart';
import '../utils/app_paths.dart';

class AvatarService {
  static const String _filetreeUrl =
      'https://raw.githubusercontent.com/xinxin8816/gfriends/master/Filetree.json';
  static const String _contentBaseUrl =
      'https://raw.githubusercontent.com/xinxin8816/gfriends/master/Content/';

  final ActorRepository _actorRepository;

  AvatarService({ActorRepository? actorRepository})
      : _actorRepository = actorRepository ?? ActorRepository();

  Future<String> get _avatarsDir async => AppPaths.avatarsDir;

  Future<Map<String, dynamic>?> fetchFiletree() async {
    if (kDebugMode) debugPrint('[Avatar] Fetching filetree...');

    try {
      final localFile = File(path.join(Directory.current.path, 'test', 'Filetree.json'));
      if (await localFile.exists()) {
        if (kDebugMode) debugPrint('[Avatar] Loading local filetree from test folder');
        final bytes = await localFile.readAsBytes();
        final content = utf8.decode(bytes, allowMalformed: true);
        final filetree = json.decode(content) as Map<String, dynamic>;
        if (kDebugMode) {
          debugPrint('[Avatar] Local filetree loaded, Content keys count: ${(filetree['Content'] as Map?)?.length ?? 0}');
        }
        return filetree;
      }
    } catch (localError) {
      if (kDebugMode) debugPrint('[Avatar] Local filetree error: $localError');
    }

    try {
      final client = await createProxyClientFromPrefs();
      try {
        final response = await client.get(
          Uri.parse(_filetreeUrl),
          headers: {'Accept-Encoding': 'gzip'},
        ).timeout(const Duration(seconds: 30));

        if (kDebugMode) {
          debugPrint('[Avatar] Filetree status: ${response.statusCode}, size: ${response.bodyBytes.length}');
        }
        if (response.statusCode != 200) return null;

        final content = utf8.decode(response.bodyBytes, allowMalformed: true);
        return json.decode(content) as Map<String, dynamic>;
      } finally {
        client.close();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Avatar] Filetree fetch error: $e');
      return null;
    }
  }

  int _countMatchingChars(String a, String b) {
    int match = 0;
    final minLen = a.length < b.length ? a.length : b.length;
    for (int i = 0; i < minLen; i++) {
      if (a[i] == b[i]) match++;
    }
    return match;
  }

  bool _isFuzzyMatch(String baseName, String searchName) {
    if (baseName == searchName) return true;
    if (baseName.length != searchName.length) return false;

    final matchingChars = _countMatchingChars(baseName, searchName);

    if (searchName.length <= 3) {
      return matchingChars >= searchName.length - 1;
    }
    if (searchName.length == 4) {
      return matchingChars >= 3;
    }
    return matchingChars >= searchName.length - 1;
  }

  String? _findActorInFiletree(Map<String, dynamic> filetree, String actorName) {
    final content = filetree['Content'] as Map<String, dynamic>?;
    if (content == null) {
      if (kDebugMode) debugPrint('[Avatar] Filetree Content is null');
      return null;
    }

    final searchName = actorName.trim();

    if (kDebugMode) {
      debugPrint('[Avatar] Searching for: "$searchName" (len=${searchName.length})');
    }

    String? exactMatch;
    String? fuzzyMatch;
    int fuzzyScore = 0;

    for (final companyEntry in content.entries) {
      final companyFolder = companyEntry.key;
      final files = companyEntry.value;
      if (files is! Map<String, dynamic>) continue;

      for (final fileEntry in files.entries) {
        final keyName = fileEntry.key.toString();
        final valuePath = fileEntry.value.toString();

        final nameWithoutExt = keyName.replaceAll(RegExp(r'\.jpg$'), '');
        final baseName = nameWithoutExt.replaceFirst(RegExp(r'-\d+$'), '');

        if (baseName == searchName) {
          exactMatch = _buildUrl(companyFolder, valuePath);
          if (kDebugMode) debugPrint('[Avatar] Exact match: "$searchName" in "$companyFolder"');
          break;
        }

        if (exactMatch == null && _isFuzzyMatch(baseName, searchName)) {
          final score = _countMatchingChars(baseName, searchName);
          if (score > fuzzyScore) {
            fuzzyScore = score;
            fuzzyMatch = _buildUrl(companyFolder, valuePath);
            if (kDebugMode) {
              debugPrint('[Avatar] Fuzzy candidate: "$baseName" (match=$score/${searchName.length}) in "$companyFolder"');
            }
          }
        }
      }
      if (exactMatch != null) break;
    }

    if (exactMatch != null) return exactMatch;
    if (fuzzyMatch != null) {
      if (kDebugMode) debugPrint('[Avatar] Using fuzzy match for: "$searchName"');
      return fuzzyMatch;
    }

    if (kDebugMode) debugPrint('[Avatar] No match for: "$searchName"');
    return null;
  }

  List<String> findAllAvatarUrls(Map<String, dynamic> filetree, String actorName) {
    final content = filetree['Content'] as Map<String, dynamic>?;
    if (content == null) {
      if (kDebugMode) debugPrint('[Avatar] Filetree Content is null');
      return [];
    }

    final searchName = actorName.trim();
    final List<String> exactUrls = [];
    final List<String> fuzzyUrls = [];

    for (final companyEntry in content.entries) {
      final companyFolder = companyEntry.key;
      final files = companyEntry.value;
      if (files is! Map<String, dynamic>) continue;

      for (final fileEntry in files.entries) {
        final keyName = fileEntry.key.toString();
        final valuePath = fileEntry.value.toString();

        final nameWithoutExt = keyName.replaceAll(RegExp(r'\.jpg$'), '');
        final baseName = nameWithoutExt.replaceFirst(RegExp(r'-\d+$'), '');

        final url = _buildUrl(companyFolder, valuePath);

        if (baseName == searchName) {
          if (!exactUrls.contains(url)) {
            exactUrls.add(url);
            if (kDebugMode) {
              debugPrint('[Avatar] Exact match avatar: "$baseName" in "$companyFolder"');
            }
          }
        } else if (_isFuzzyMatch(baseName, searchName)) {
          if (!fuzzyUrls.contains(url)) {
            fuzzyUrls.add(url);
            if (kDebugMode) {
              debugPrint('[Avatar] Fuzzy avatar: "$baseName" in "$companyFolder"');
            }
          }
        }
      }
    }

    if (exactUrls.isNotEmpty) {
      if (kDebugMode) {
        debugPrint('[Avatar] Found ${exactUrls.length} exact avatar(s) for: "$searchName"');
      }
      return exactUrls;
    }

    if (kDebugMode) {
      debugPrint('[Avatar] Found ${fuzzyUrls.length} fuzzy avatar(s) for: "$searchName"');
    }
    return fuzzyUrls;
  }

  String _buildUrl(String companyFolder, String valuePath) {
    return '$_contentBaseUrl${Uri.encodeComponent(companyFolder)}/$valuePath';
  }

  Future<int> fetchAvatarsForActors(
    List<Actor> actors, {
    void Function(int current, int total, String actorName)? onProgress,
  }) async {
    final filetree = await fetchFiletree();
    if (filetree == null) {
      if (kDebugMode) debugPrint('[Avatar] Filetree is null, aborting');
      return 0;
    }

    final avatarsDir = await _avatarsDir;
    int successCount = 0;
    final client = await createProxyClientFromPrefs();

    final actorsToFetch = actors.where((actor) {
      if (actor.avatarUrl == null || actor.avatarUrl!.isEmpty) return true;
      return !File(actor.avatarUrl!).existsSync();
    }).toList();

    try {
      const batchSize = 5;

      for (var i = 0; i < actorsToFetch.length; i += batchSize) {
        final end = (i + batchSize > actorsToFetch.length) ? actorsToFetch.length : i + batchSize;
        final batch = actorsToFetch.sublist(i, end);

        final results = await Future.wait(batch.map((actor) async {
          try {
            final imageUrl = _findActorInFiletree(filetree, actor.name);
            if (imageUrl == null) return false;

            if (kDebugMode) debugPrint('[Avatar] Downloading: ${actor.name} -> $imageUrl');

            final response = await client.get(Uri.parse(imageUrl)).timeout(const Duration(seconds: 15));

            if (response.statusCode == 200 && response.bodyBytes.length > 100) {
              final safeName = actor.name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
              final filePath = path.join(avatarsDir, '$safeName.jpg');
              await File(filePath).writeAsBytes(response.bodyBytes);
              await _actorRepository.updateActorAvatar(actor.id!, filePath);

              if (kDebugMode) debugPrint('[Avatar] Saved: $filePath (${response.bodyBytes.length} bytes)');

              return true;
            }
            return false;
          } catch (e) {
            if (kDebugMode) debugPrint('[Avatar] Error for ${actor.name}: $e');
            return false;
          }
        }));

        successCount += results.where((r) => r).length;
        onProgress?.call(end.clamp(0, actorsToFetch.length), actorsToFetch.length,
            batch.last.name);

        if (i + batchSize < actorsToFetch.length) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
    } finally {
      client.close();
    }
    if (kDebugMode) debugPrint('[Avatar] Done. $successCount/${actorsToFetch.length} avatars fetched');
    return successCount;
  }
}
