class GitHubDiscussion {
  final String id;
  final int number;
  final String title;
  final String author;
  final String? authorAvatarUrl;
  final DateTime publishedAt;
  final DateTime updatedAt;
  final String htmlContent;
  final String markdownContent;
  final String category;
  final String url;
  final bool isRead;

  const GitHubDiscussion({
    required this.id,
    required this.number,
    required this.title,
    required this.author,
    this.authorAvatarUrl,
    required this.publishedAt,
    required this.updatedAt,
    required this.htmlContent,
    required this.markdownContent,
    required this.category,
    required this.url,
    this.isRead = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'number': number,
      'title': title,
      'author': author,
      'authorAvatarUrl': authorAvatarUrl,
      'publishedAt': publishedAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'htmlContent': htmlContent,
      'markdownContent': markdownContent,
      'category': category,
      'url': url,
      'isRead': isRead,
    };
  }

  factory GitHubDiscussion.fromJson(Map<String, dynamic> json) {
    return GitHubDiscussion(
      id: json['id'] as String,
      number: json['number'] as int? ?? 0,
      title: json['title'] as String,
      author: json['author'] as String,
      authorAvatarUrl: json['authorAvatarUrl'] as String?,
      publishedAt: DateTime.tryParse(json['publishedAt'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
      htmlContent: json['htmlContent'] as String? ?? '',
      markdownContent: json['markdownContent'] as String? ?? '',
      category: json['category'] as String? ?? 'General',
      url: json['url'] as String? ?? '',
      isRead: json['isRead'] as bool? ?? false,
    );
  }

  GitHubDiscussion copyWith({
    String? id,
    int? number,
    String? title,
    String? author,
    String? authorAvatarUrl,
    DateTime? publishedAt,
    DateTime? updatedAt,
    String? htmlContent,
    String? markdownContent,
    String? category,
    String? url,
    bool? isRead,
  }) {
    return GitHubDiscussion(
      id: id ?? this.id,
      number: number ?? this.number,
      title: title ?? this.title,
      author: author ?? this.author,
      authorAvatarUrl: authorAvatarUrl ?? this.authorAvatarUrl,
      publishedAt: publishedAt ?? this.publishedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      htmlContent: htmlContent ?? this.htmlContent,
      markdownContent: markdownContent ?? this.markdownContent,
      category: category ?? this.category,
      url: url ?? this.url,
      isRead: isRead ?? this.isRead,
    );
  }
}
