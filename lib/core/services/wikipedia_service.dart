import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import '../utils/proxy_client.dart';

class WikipediaService {
  static const String _baseUrl = 'https://ja.wikipedia.org/wiki/';

  Future<Map<String, dynamic>?> fetchActorInfo(String actorName) async {
    final url = '$_baseUrl${Uri.encodeComponent(actorName)}';
    if (kDebugMode) {
      debugPrint('[Wikipedia] Fetching info for: $actorName');
      debugPrint('[Wikipedia] URL: $url');
    }

    try {
      final client = await createProxyClientFromPrefs();
      final response = await client.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'JAV-Manager/1.0 (https://github.com/gfriends/gfriends; contact@example.com)',
        },
      ).timeout(const Duration(seconds: 15));
      client.close();

      if (kDebugMode) {
        debugPrint('[Wikipedia] Response status: ${response.statusCode}');
        debugPrint('[Wikipedia] Content length: ${response.body.length}');
      }

      if (response.statusCode != 200) {
        if (kDebugMode) debugPrint('[Wikipedia] Non-200 status, returning null');
        return null;
      }

      final result = _parseWikipediaHtml(response.body);
      if (kDebugMode) {
        debugPrint('[Wikipedia] Parsed result: $result');
      }
      return result;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('[Wikipedia] Error: $e');
        debugPrint('[Wikipedia] StackTrace: $stackTrace');
      }
      return null;
    }
  }

  Map<String, dynamic>? _parseWikipediaHtml(String htmlContent) {
    try {
      final document = html_parser.parse(htmlContent);

      String? birthDate;
      String? height;
      String? weight;
      String? bust;
      String? waist;
      String? hip;
      String? cupSize;

      // Try multiple selectors for the infobox table
      final infoboxTables = [
        ...document.querySelectorAll('table.infobox'),
        ...document.querySelectorAll('.infobox'),
      ];

      if (kDebugMode) {
        debugPrint('[Wikipedia] Found ${infoboxTables.length} infobox tables');
      }

      // Method 1: Parse infobox table rows
      for (final table in infoboxTables) {
        final tableRows = table.querySelectorAll('tr');
        for (final row in tableRows) {
          final th = row.querySelector('th');
          final td = row.querySelector('td');

          if (th == null || td == null) continue;

          final thText = th.text.trim();
          final tdText = td.text.trim();

          if (birthDate == null && (thText.contains('誕生日') || thText == '生年月日')) {
            final dateMatch = RegExp(r'(\d{4})年(\d{1,2})月(\d{1,2})日').firstMatch(tdText);
            if (dateMatch != null) {
              birthDate = '${dateMatch.group(1)}-${dateMatch.group(2)}-${dateMatch.group(3)}';
            }
          }

          // 身長 and 体重 may be in the same row: "身長 / 体重" -> "152 cm / 90.1 kg"
          if (height == null && thText.contains('身長')) {
            final heightMatch = RegExp(r'(\d+(?:\.\d+)?)\s*cm').firstMatch(tdText);
            if (heightMatch != null) {
              height = heightMatch.group(1);
            }
          }

          if (weight == null && (thText.contains('体重') || (thText.contains('身長') && tdText.contains('kg')))) {
            final weightMatch = RegExp(r'(\d+(?:\.\d+)?)\s*kg').firstMatch(tdText);
            if (weightMatch != null) {
              weight = weightMatch.group(1);
            }
          }

          if (bust == null && (thText.contains('スリーサイズ') || thText == 'サイズ')) {
            final sizesMatch = RegExp(r'(\d+)\s*[-,/]\s*(\d+)\s*[-,/]\s*(\d+)').firstMatch(tdText);
            if (sizesMatch != null) {
              bust = sizesMatch.group(1);
              waist = sizesMatch.group(2);
              hip = sizesMatch.group(3);
            }
          }

          if (cupSize == null && (thText.contains('ブラサイズ') || thText == 'カップ')) {
            final cupMatch = RegExp(r'([A-Z])\s*(?:カップ|cup)', caseSensitive: false).firstMatch(tdText);
            if (cupMatch != null) {
              cupSize = cupMatch.group(1)?.toUpperCase();
            } else {
              final cupOnlyMatch = RegExp(r'\b([A-Z])\b').firstMatch(tdText);
              if (cupOnlyMatch != null) {
                cupSize = cupOnlyMatch.group(1);
              }
            }
          }
        }

        if (birthDate != null || height != null || weight != null ||
            bust != null || cupSize != null) {
          break;
        }
      }

      // Method 2: Fallback - search for specific link-based selectors
      if (birthDate == null) {
        final el = document.querySelector('a[title="誕生日"]');
        if (el != null) {
          final row = _findParentRow(el);
          final td = row?.querySelector('td');
          if (td != null) {
            final m = RegExp(r'(\d{4})年(\d{1,2})月(\d{1,2})日').firstMatch(td.text);
            if (m != null) birthDate = '${m.group(1)}-${m.group(2)}-${m.group(3)}';
          }
        }
      }
      if (height == null) {
        final el = document.querySelector('a[title="身長"]');
        if (el != null) {
          final row = _findParentRow(el);
          final td = row?.querySelector('td');
          if (td != null) {
            final m = RegExp(r'(\d+(?:\.\d+)?)\s*cm').firstMatch(td.text);
            if (m != null) height = m.group(1);
          }
        }
      }
      if (weight == null) {
        // 身長/体重 may be combined in one row, so check from 身長 link too
        final weightEl = document.querySelector('a[title="体重"]');
        final heightEl = document.querySelector('a[title="身長"]');
        final el = weightEl ?? heightEl;
        if (el != null) {
          final row = _findParentRow(el);
          final td = row?.querySelector('td');
          if (td != null) {
            final m = RegExp(r'(\d+(?:\.\d+)?)\s*kg').firstMatch(td.text);
            if (m != null) weight = m.group(1);
          }
        }
      }
      if (bust == null) {
        final el = document.querySelector('a[title="スリーサイズ"]');
        if (el != null) {
          final row = _findParentRow(el);
          final td = row?.querySelector('td');
          if (td != null) {
            final text = td.text.replaceAll('cm', '').trim();
            final m = RegExp(r'(\d+)\s*[-,/]\s*(\d+)\s*[-,/]\s*(\d+)').firstMatch(text);
            if (m != null) {
              bust = m.group(1);
              waist = m.group(2);
              hip = m.group(3);
            }
          }
        }
      }
      if (cupSize == null) {
        final el = document.querySelector('a[title="ブラサイズ"]');
        if (el != null) {
          final row = _findParentRow(el);
          final td = row?.querySelector('td');
          if (td != null) {
            final m = RegExp(r'([A-Z])\s*(?:カップ|cup)', caseSensitive: false).firstMatch(td.text);
            if (m != null) {
              cupSize = m.group(1)?.toUpperCase();
            } else {
              final m2 = RegExp(r'\b([A-Z])\b').firstMatch(td.text);
              if (m2 != null) cupSize = m2.group(1);
            }
          }
        }
      }

      final info = <String, dynamic>{};
      if (birthDate != null) info['birthDate'] = birthDate;
      if (height != null) info['height'] = height;
      if (weight != null) info['weight'] = weight;
      if (bust != null) info['bust'] = bust;
      if (waist != null) info['waist'] = waist;
      if (hip != null) info['hip'] = hip;
      if (cupSize != null) info['cupSize'] = cupSize;

      return info.isNotEmpty ? info : null;
    } catch (e) {
      if (kDebugMode) debugPrint('[Wikipedia] Parse error: $e');
      return null;
    }
  }

  Element? _findParentRow(Element element) {
    var current = element.parent;
    while (current != null) {
      if (current.localName == 'tr') return current;
      current = current.parent;
    }
    return null;
  }

  Future<String?> getActorImageUrl(String actorName) async {
    try {
      final url = '$_baseUrl${Uri.encodeComponent(actorName)}';
      final client = await createProxyClientFromPrefs();
      final response = await client.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'JAV-Manager/1.0 (https://github.com/gfriends/gfriends; contact@example.com)',
        },
      ).timeout(const Duration(seconds: 15));
      client.close();

      if (response.statusCode != 200) return null;
      return _extractMainImage(response.body);
    } catch (e) {
      return null;
    }
  }

  String? _extractMainImage(String htmlContent) {
    try {
      final document = html_parser.parse(htmlContent);
      final infoboxImage = document.querySelector('.infobox img');
      if (infoboxImage != null) {
        final src = infoboxImage.attributes['src'];
        if (src != null && src.startsWith('//')) return 'https:$src';
        return src;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
