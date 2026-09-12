import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/github_discussion_model.dart';
import '../../services/github_discussions_service.dart';
import '../../utils/url_launcher_utils.dart';
import 'discussion_detail_screen.dart';

class GitHubDiscussionsScreen extends StatefulWidget {
  const GitHubDiscussionsScreen({super.key});

  @override
  State<GitHubDiscussionsScreen> createState() => _GitHubDiscussionsScreenState();
}

class _GitHubDiscussionsScreenState extends State<GitHubDiscussionsScreen> {
  final GitHubDiscussionsService _service = GitHubDiscussionsService();
  List<GitHubDiscussion> _discussions = [];
  bool _isAutoRefreshing = false;
  String _selectedCategory = 'All';

  @override
  void initState() {
    super.initState();
    _initAndFetch();
  }

  Future<void> _initAndFetch() async {
    // 1. Immediately load any cached discussions from local storage so the page has content right away
    final cached = await _service.getCachedDiscussions();
    if (mounted) {
      setState(() {
        _discussions = cached;
        _isAutoRefreshing = true;
      });
    }

    // 2. Automatically refresh in the background from GitHub
    final fresh = await _service.fetchDiscussions(forceRefresh: true);
    if (mounted) {
      setState(() {
        _discussions = fresh;
        _isAutoRefreshing = false;
      });
    }
  }

  Future<void> _manualRefresh() async {
    setState(() => _isAutoRefreshing = true);
    final fresh = await _service.fetchDiscussions(forceRefresh: true);
    if (mounted) {
      setState(() {
        _discussions = fresh;
        _isAutoRefreshing = false;
      });
    }
  }

  List<String> get _availableCategories {
    final categories = <String>{'All'};
    for (final d in _discussions) {
      if (d.category.isNotEmpty) {
        categories.add(d.category);
      }
    }
    return categories.toList();
  }

  List<GitHubDiscussion> get _filteredDiscussions {
    if (_selectedCategory == 'All') return _discussions;
    return _discussions
        .where((d) => d.category.toLowerCase() == _selectedCategory.toLowerCase())
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final categories = _availableCategories;
    final filtered = _filteredDiscussions;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Community Discussions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new_rounded),
            tooltip: 'Open GitHub Discussions',
            onPressed: () => UrlLauncherUtils.launchExternalUrl(
              GitHubDiscussionsService.discussionsUrl,
              context: context,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _manualRefresh,
        child: Column(
          children: [
            if (_isAutoRefreshing)
              const LinearProgressIndicator(minHeight: 2.5),
            // Category Filter Chips
            if (categories.length > 2)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: categories.map((cat) {
                      final isSelected = _selectedCategory.toLowerCase() == cat.toLowerCase();
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: FilterChip(
                          label: Text(cat),
                          selected: isSelected,
                          onSelected: (sel) {
                            setState(() => _selectedCategory = cat);
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            const Divider(height: 1),

            // Discussions List
            Expanded(
              child: filtered.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                        Center(
                          child: _isAutoRefreshing
                              ? const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircularProgressIndicator(),
                                    SizedBox(height: 16),
                                    Text(
                                      'Fetching community discussions...',
                                      style: TextStyle(fontSize: 14, color: Colors.grey),
                                    ),
                                  ],
                                )
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.forum_outlined,
                                      size: 56,
                                      color: isDark ? Colors.white24 : Colors.grey.shade400,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No discussions found in this category.',
                                      style: TextStyle(
                                        color: isDark ? Colors.white60 : Colors.black54,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    TextButton.icon(
                                      icon: const Icon(Icons.refresh),
                                      label: const Text('Refresh'),
                                      onPressed: _manualRefresh,
                                    ),
                                  ],
                                ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(12),
                            itemCount: filtered.length,
                            separatorBuilder: (ctx, i) => const SizedBox(height: 8),
                            itemBuilder: (ctx, i) {
                              final item = filtered[i];
                              final dateStr = DateFormat.yMMMd().format(item.publishedAt.toLocal());
                              final isAnnouncement = item.category.toLowerCase() == 'announcements';

                              return Card(
                                elevation: 0.5,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: isDark ? Colors.white12 : Colors.grey.shade300,
                                  ),
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => DiscussionDetailScreen(discussion: item),
                                      ),
                                    );
                                    // Refresh unread state locally
                                    final updated = await _service.getCachedDiscussions();
                                    if (mounted) {
                                      setState(() => _discussions = updated);
                                    }
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(14.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Header Row: Category Badge + Date
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: isDark ? Colors.white12 : Colors.black12,
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    isAnnouncement
                                                        ? Icons.campaign_rounded
                                                        : Icons.forum_outlined,
                                                    size: 12,
                                                    color: isDark ? Colors.white70 : Colors.black87,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    item.category,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                      color: isDark ? Colors.white : Colors.black,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const Spacer(),
                                            Text(
                                              dateStr,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isDark ? Colors.white54 : Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),

                                        // Title
                                        Text(
                                          item.title,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 6),

                                        // Author info & preview
                                        Row(
                                          children: [
                                            if (item.authorAvatarUrl != null)
                                              CircleAvatar(
                                                radius: 9,
                                                backgroundImage: NetworkImage(item.authorAvatarUrl!),
                                              )
                                            else
                                              const CircleAvatar(
                                                radius: 9,
                                                child: Icon(Icons.person, size: 10),
                                              ),
                                            const SizedBox(width: 6),
                                            Text(
                                              item.author,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                color: isDark ? Colors.white70 : Colors.black87,
                                              ),
                                            ),
                                            if (item.number > 0) ...[
                                              const SizedBox(width: 6),
                                              Text(
                                                '#${item.number}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: isDark ? Colors.white38 : Colors.grey.shade500,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
