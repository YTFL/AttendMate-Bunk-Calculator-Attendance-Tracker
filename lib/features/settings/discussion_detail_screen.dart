import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:intl/intl.dart';

import '../../models/github_discussion_model.dart';
import '../../services/github_discussions_service.dart';
import '../../utils/markdown_link_helper.dart';
import '../../utils/url_launcher_utils.dart';

class DiscussionDetailScreen extends StatefulWidget {
  final GitHubDiscussion discussion;

  const DiscussionDetailScreen({super.key, required this.discussion});

  @override
  State<DiscussionDetailScreen> createState() => _DiscussionDetailScreenState();
}

class _DiscussionDetailScreenState extends State<DiscussionDetailScreen> {
  @override
  void initState() {
    super.initState();
    // Mark discussion as read when viewed
    GitHubDiscussionsService().markAsRead(widget.discussion.id);
  }

  @override
  Widget build(BuildContext context) {
    final discussion = widget.discussion;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final formattedDate = DateFormat.yMMMd().add_jm().format(discussion.publishedAt.toLocal());

    return Scaffold(
      appBar: AppBar(
        title: Text(discussion.number > 0 ? '#${discussion.number} Discussion' : 'Discussion'),
        actions: [
          if (discussion.url.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.open_in_new_rounded),
              tooltip: 'Open on GitHub',
              onPressed: () => UrlLauncherUtils.launchExternalUrl(discussion.url, context: context),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category Badge (Monochrome)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    discussion.category.toLowerCase() == 'announcements'
                        ? Icons.campaign_rounded
                        : Icons.forum_outlined,
                    size: 14,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    discussion.category,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Title
            Text(
              discussion.title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 12),

            // Author & Date Info
            Row(
              children: [
                if (discussion.authorAvatarUrl != null)
                  CircleAvatar(
                    radius: 14,
                    backgroundImage: NetworkImage(discussion.authorAvatarUrl!),
                  )
                else
                  const CircleAvatar(
                    radius: 14,
                    child: Icon(Icons.person, size: 16),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        discussion.author,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        formattedDate,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            // Markdown Content
            MarkdownBody(
              data: discussion.markdownContent.isNotEmpty
                  ? discussion.markdownContent
                  : '_No description provided._',
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                p: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: isDark ? Colors.white.withValues(alpha: 0.9) : Colors.black87,
                ),
                h1: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                h2: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                h3: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                blockquote: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black87,
                  fontStyle: FontStyle.italic,
                ),
                blockquoteDecoration: BoxDecoration(
                  color: isDark ? Colors.white10 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                  border: Border(
                    left: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 4,
                    ),
                  ),
                ),
              ),
              onTapLink: (text, href, title) {
                MarkdownLinkHelper.openLink(context, href);
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
