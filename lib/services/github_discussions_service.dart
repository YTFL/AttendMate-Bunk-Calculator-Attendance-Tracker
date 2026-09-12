import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/github_discussion_model.dart';

class GitHubDiscussionsService {
  static final GitHubDiscussionsService _instance = GitHubDiscussionsService._internal();
  factory GitHubDiscussionsService() => _instance;
  GitHubDiscussionsService._internal();

  static const String repoOwner = 'YTFL';
  static const String repoName = 'AttendMate-Bunk-Calculator-Attendance-Tracker';
  static const String discussionsUrl = 'https://github.com/$repoOwner/$repoName/discussions';
  static const String discussionsAtomUrl = 'https://github.com/$repoOwner/$repoName/discussions.atom';
  static const String announcementsAtomUrl = 'https://github.com/$repoOwner/$repoName/discussions/categories/announcements.atom';

  static const String _prefCachedDiscussionsKey = 'cached_github_discussions_json';
  static const String _prefLastSeenAnnouncementIdKey = 'last_seen_announcement_id';
  static const String _prefReadDiscussionIdsKey = 'read_discussion_ids';

  /// Get cached discussions from local storage
  Future<List<GitHubDiscussion>> getCachedDiscussions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_prefCachedDiscussionsKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List list = jsonDecode(jsonStr);
        final readIds = (prefs.getStringList(_prefReadDiscussionIdsKey) ?? []).toSet();
        return list
            .map((item) => GitHubDiscussion.fromJson(item as Map<String, dynamic>))
            .map((d) => d.copyWith(isRead: readIds.contains(d.id)))
            .toList();
      }
    } catch (e) {
      debugPrint('GitHubDiscussionsService: Error loading cached discussions: $e');
    }
    return [];
  }

  /// Save discussions to offline cache
  Future<void> _cacheDiscussions(List<GitHubDiscussion> discussions) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(discussions.map((d) => d.toJson()).toList());
      await prefs.setString(_prefCachedDiscussionsKey, jsonStr);
    } catch (e) {
      debugPrint('GitHubDiscussionsService: Error saving cache: $e');
    }
  }

  /// Mark a discussion as read
  Future<void> markAsRead(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final readIds = (prefs.getStringList(_prefReadDiscussionIdsKey) ?? []).toSet();
      readIds.add(id);
      await prefs.setStringList(_prefReadDiscussionIdsKey, readIds.toList());
    } catch (_) {}
  }

  /// Check for a new unseen discussion tagged 'Announcements'
  Future<GitHubDiscussion?> checkForNewAnnouncement() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSeenId = prefs.getString(_prefLastSeenAnnouncementIdKey);

      // Fetch announcement category feed directly
      final response = await http.get(
        Uri.parse(announcementsAtomUrl),
        headers: {'Accept': 'application/atom+xml'},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final announcements = _parseAtomFeed(response.body, defaultCategory: 'Announcements');
        if (announcements.isNotEmpty) {
          // Sort by published date descending
          announcements.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
          final latest = announcements.first;

          // Update cache with these announcements
          final currentCache = await getCachedDiscussions();
          final merged = _mergeDiscussions(currentCache, announcements);
          await _cacheDiscussions(merged);

          if (latest.id != lastSeenId) {
            return latest;
          }
        }
      }
    } catch (e) {
      debugPrint('GitHubDiscussionsService: Error checking for new announcements: $e');
    }
    return null;
  }

  /// Acknowledge the announcement so it won't pop up again
  Future<void> markAnnouncementAsSeen(String announcementId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefLastSeenAnnouncementIdKey, announcementId);
      await markAsRead(announcementId);
    } catch (_) {}
  }

  /// Fetch all discussions, combining general feed and announcements
  Future<List<GitHubDiscussion>> fetchDiscussions({bool forceRefresh = false}) async {
    List<GitHubDiscussion> cached = await getCachedDiscussions();

    try {
      // Parallel fetch of main feed and announcements feed to properly tag announcements
      final results = await Future.wait([
        http.get(Uri.parse(discussionsAtomUrl), headers: {'Accept': 'application/atom+xml'})
            .timeout(const Duration(seconds: 10)),
        http.get(Uri.parse(announcementsAtomUrl), headers: {'Accept': 'application/atom+xml'})
            .timeout(const Duration(seconds: 10)),
      ]);

      final allRes = results[0];
      final annRes = results[1];

      final Set<String> announcementIds = {};
      final List<GitHubDiscussion> announcementsList = [];
      if (annRes.statusCode == 200 && annRes.body.isNotEmpty) {
        final ann = _parseAtomFeed(annRes.body, defaultCategory: 'Announcements');
        for (final item in ann) {
          announcementIds.add(item.id);
          announcementsList.add(item);
        }
      }

      final List<GitHubDiscussion> allDiscussions = [];
      if (allRes.statusCode == 200 && allRes.body.isNotEmpty) {
        final main = _parseAtomFeed(allRes.body, defaultCategory: 'General');
        for (final item in main) {
          if (announcementIds.contains(item.id)) {
            allDiscussions.add(item.copyWith(category: 'Announcements'));
          } else {
            allDiscussions.add(item);
          }
        }
      }

      final merged = _mergeDiscussions(cached, _mergeDiscussions(allDiscussions, announcementsList));
      merged.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

      await _cacheDiscussions(merged);
      return merged;
    } catch (e) {
      debugPrint('GitHubDiscussionsService: Fetch failed, returning offline cache: $e');
      return cached;
    }
  }

  List<GitHubDiscussion> _mergeDiscussions(
    List<GitHubDiscussion> listA,
    List<GitHubDiscussion> listB,
  ) {
    final Map<String, GitHubDiscussion> map = {};
    for (final item in listA) {
      map[item.id] = item;
    }
    for (final item in listB) {
      final existing = map[item.id];
      if (existing != null) {
        map[item.id] = item.copyWith(isRead: existing.isRead);
      } else {
        map[item.id] = item;
      }
    }
    return map.values.toList();
  }

  /// Parse Atom XML feed entries into GitHubDiscussion items
  List<GitHubDiscussion> _parseAtomFeed(String xml, {required String defaultCategory}) {
    final List<GitHubDiscussion> discussions = [];
    final entryRegex = RegExp(r'<entry>([\s\S]*?)<\/entry>', multiLine: true);
    final matches = entryRegex.allMatches(xml);

    for (final match in matches) {
      final entryXml = match.group(1) ?? '';

      final idMatch = RegExp(r'<id>(.*?)<\/id>').firstMatch(entryXml);
      final id = idMatch?.group(1)?.trim() ?? '';

      final linkMatch = RegExp(r'<link[^>]*href="([^"]*)"').firstMatch(entryXml);
      final url = linkMatch?.group(1)?.trim() ?? '';

      final titleMatch = RegExp(r'<title>([\s\S]*?)<\/title>').firstMatch(entryXml);
      final title = _unescapeXml(titleMatch?.group(1)?.trim() ?? 'Untitled');

      final publishedMatch = RegExp(r'<published>(.*?)<\/published>').firstMatch(entryXml);
      final publishedAt = DateTime.tryParse(publishedMatch?.group(1)?.trim() ?? '') ?? DateTime.now();

      final updatedMatch = RegExp(r'<updated>(.*?)<\/updated>').firstMatch(entryXml);
      final updatedAt = DateTime.tryParse(updatedMatch?.group(1)?.trim() ?? '') ?? publishedAt;

      final authorMatch = RegExp(r'<author>\s*<name>(.*?)<\/name>', multiLine: true).firstMatch(entryXml);
      final author = authorMatch?.group(1)?.trim() ?? 'Anonymous';

      final avatarMatch = RegExp(r'<media:thumbnail[^>]*url="([^"]*)"').firstMatch(entryXml);
      final authorAvatarUrl = avatarMatch != null ? _unescapeXml(avatarMatch.group(1) ?? '') : null;

      final contentMatch = RegExp(r'<content[^>]*type="html">([\s\S]*?)<\/content>').firstMatch(entryXml);
      final rawHtml = _unescapeXml(contentMatch?.group(1)?.trim() ?? '');
      final markdown = _htmlToMarkdown(rawHtml);

      // Extract discussion number from URL (e.g. https://github.com/.../discussions/2)
      int number = 0;
      final numberMatch = RegExp(r'/discussions/(\d+)').firstMatch(url);
      if (numberMatch != null) {
        number = int.tryParse(numberMatch.group(1) ?? '0') ?? 0;
      }

      discussions.add(GitHubDiscussion(
        id: id.isNotEmpty ? id : url,
        number: number,
        title: title,
        author: author,
        authorAvatarUrl: authorAvatarUrl,
        publishedAt: publishedAt,
        updatedAt: updatedAt,
        htmlContent: rawHtml,
        markdownContent: markdown,
        category: defaultCategory,
        url: url,
      ));
    }

    return discussions;
  }

  static String _unescapeXml(String text) {
    return text
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&');
  }

  /// Clean HTML to Markdown conversion for in-app reading
  static String _htmlToMarkdown(String html) {
    if (html.isEmpty) return '';

    String md = html;

    // Headings
    md = md.replaceAllMapped(RegExp(r'<h1[^>]*>([\s\S]*?)<\/h1>', caseSensitive: false), (m) => '\n# ${m[1]?.trim()}\n\n');
    md = md.replaceAllMapped(RegExp(r'<h2[^>]*>([\s\S]*?)<\/h2>', caseSensitive: false), (m) => '\n## ${m[1]?.trim()}\n\n');
    md = md.replaceAllMapped(RegExp(r'<h3[^>]*>([\s\S]*?)<\/h3>', caseSensitive: false), (m) => '\n### ${m[1]?.trim()}\n\n');
    md = md.replaceAllMapped(RegExp(r'<h4[^>]*>([\s\S]*?)<\/h4>', caseSensitive: false), (m) => '\n#### ${m[1]?.trim()}\n\n');
    md = md.replaceAllMapped(RegExp(r'<h5[^>]*>([\s\S]*?)<\/h5>', caseSensitive: false), (m) => '\n##### ${m[1]?.trim()}\n\n');
    md = md.replaceAllMapped(RegExp(r'<h6[^>]*>([\s\S]*?)<\/h6>', caseSensitive: false), (m) => '\n###### ${m[1]?.trim()}\n\n');

    // Bold & Italics
    md = md.replaceAllMapped(RegExp(r'<strong[^>]*>([\s\S]*?)<\/strong>', caseSensitive: false), (m) => '**${m[1]?.trim()}**');
    md = md.replaceAllMapped(RegExp(r'<b[^>]*>([\s\S]*?)<\/b>', caseSensitive: false), (m) => '**${m[1]?.trim()}**');
    md = md.replaceAllMapped(RegExp(r'<em[^>]*>([\s\S]*?)<\/em>', caseSensitive: false), (m) => '*${m[1]?.trim()}*');
    md = md.replaceAllMapped(RegExp(r'<i[^>]*>([\s\S]*?)<\/i>', caseSensitive: false), (m) => '*${m[1]?.trim()}*');

    // Links: <a ... href="..." ...>Text</a>
    md = md.replaceAllMapped(RegExp(r'<a[^>]*href="([^"]*)"[^>]*>([\s\S]*?)<\/a>', caseSensitive: false), (m) {
      final href = m[1]?.trim() ?? '';
      final label = m[2]?.trim() ?? href;
      return '[$label]($href)';
    });

    // Lists
    md = md.replaceAllMapped(RegExp(r'<li[^>]*>([\s\S]*?)<\/li>', caseSensitive: false), (m) => '- ${m[1]?.trim()}\n');
    md = md.replaceAll(RegExp(r'<\/?(ul|ol)[^>]*>', caseSensitive: false), '\n');

    // Paragraphs & Line breaks
    md = md.replaceAllMapped(RegExp(r'<p[^>]*>([\s\S]*?)<\/p>', caseSensitive: false), (m) => '${m[1]?.trim()}\n\n');
    md = md.replaceAll(RegExp(r'<br\s*\/?>', caseSensitive: false), '\n');

    // Blockquotes
    md = md.replaceAllMapped(RegExp(r'<blockquote[^>]*>([\s\S]*?)<\/blockquote>', caseSensitive: false), (m) {
      final lines = (m[1] ?? '').trim().split('\n');
      return '\n${lines.map((l) => '> $l').join('\n')}\n\n';
    });

    // Strip remaining tags like <g-emoji>, <div>, <span>
    md = md.replaceAll(RegExp(r'<[^>]+>'), '');

    // Collapse multiple consecutive newlines
    md = md.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return md.trim();
  }
}
