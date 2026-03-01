import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../../main.dart';
import '../../utils/snackbar_utils.dart';
import '../calendar/calendar_screen.dart';
import '../home/home_screen.dart';
import '../subject/add_subject_screen.dart';
import '../subject/import_timetable_screen.dart';

class SetupGuideScreen extends StatefulWidget {
  const SetupGuideScreen({super.key});

  @override
  State<SetupGuideScreen> createState() => _SetupGuideScreenState();
}

class _SetupGuideScreenState extends State<SetupGuideScreen> {
  late final PageController _pageController;
  int _currentPage = 0;

  static const String _aiPrompt = '''I have attached an image/screenshot of my college timetable. Convert it into the following JSON format exactly:

{
  "subjects": [
    {
      "name": "Subject Name",
      "acronym": "ACR",
      "schedule": [
        {
          "day": "monday",
          "startTime": "09:00",
          "endTime": "10:00"
        }
      ]
    }
  ]
}

Rules to follow:
- "name" is the full subject name as shown in the timetable.
- "acronym" is a short 2–4 letter code for the subject (create one if not shown).
- "day" must be fully lowercase: monday, tuesday, wednesday, thursday, friday, saturday, or sunday.
- "startTime" and "endTime" must be in 24-hour HH:MM format (e.g. 09:00, 14:30).
- Include every subject and every time slot shown in the timetable.
- Return only the raw JSON with no extra explanation.''';

  final List<_GuideSection> _sections = [
    _GuideSection(
      title: '1. Setting Up Your Semester',
      openInAppLabel: 'Open Semester Page',
      openTarget: _GuideOpenTarget.semesterTab,
      markdown: '''
## Overview
Before you can add subjects or track attendance, you must set up a semester.

---

## Steps
1. Open AttendMate and tap the **Semester** tab.
2. Tap **Set Up Semester**.
3. Fill **Start Date**, **End Date**, and **Target Attendance %**.
4. Tap **Save**.

> Attendance tracking and subject features stay locked until a valid semester is configured.
''',
    ),
    _GuideSection(
      title: '2. Adding Subjects Manually',
      openInAppLabel: 'Open Add Subject',
      openTarget: _GuideOpenTarget.addSubject,
      markdown: '''
## Overview
Add subjects one by one with name, acronym, color, and time slots.

---

## Steps
1. Open the **Subjects** tab.
2. Tap the **+** button.
3. Fill subject name, optional acronym, and color.
4. Tap **Add Time Slot** and add each day/time.
5. Tap **Save Subject**.

---

## Manage Existing Subjects
To edit or delete, open any subject card and update details.
''',
    ),
    _GuideSection(
      title: '3. Importing Subjects via JSON',
      openInAppLabel: 'Open Import Timetable',
      openTarget: _GuideOpenTarget.importTimetable,
      markdown: '''
## Overview
If you have your timetable ready, you can import all subjects at once.

---

## How to Import
1. On **Subjects**, tap the **Import** icon in the top app bar (upper-right corner).
2. Paste JSON and tap **Parse**.
3. Review preview cards.
4. Tap the **Import** button at the bottom of the screen (below the preview cards).

---

> **Tip:** Want to skip manual JSON writing? Use the ready-to-use AI prompt below with your timetable image.

## Ready-to-use AI Prompt
Use the prompt below with your timetable image in Gemini/ChatGPT/Claude.

```text
I have attached an image/screenshot of my college timetable. Convert it into the following JSON format exactly:

{
  "subjects": [
    {
      "name": "Subject Name",
      "acronym": "ACR",
      "schedule": [
        {
          "day": "monday",
          "startTime": "09:00",
          "endTime": "10:00"
        }
      ]
    }
  ]
}

Rules to follow:
- "name" is the full subject name as shown in the timetable.
- "acronym" is a short 2–4 letter code for the subject (create one if not shown).
- "day" must be fully lowercase: monday, tuesday, wednesday, thursday, friday, saturday, or sunday.
- "startTime" and "endTime" must be in 24-hour HH:MM format (e.g. 09:00, 14:30).
- Include every subject and every time slot shown in the timetable.
- Return only the raw JSON with no extra explanation.
```
''',
      aiPromptCopyText: _aiPrompt,
    ),
    _GuideSection(
      title: '4. Marking Attendance',
      openInAppLabel: 'Open Today Page',
      openTarget: _GuideOpenTarget.todayTab,
      markdown: '''
## Overview
The **Today** tab shows all classes for the current day.

---

## Class Actions
Use class actions:
- **Mark Present**
- **Mark Absent**
- **Unmark**

---

## Bulk Day Actions
Bulk actions are available for a full day:
- **Mark Holiday**
- **Skip Day**
- **Mark Today as Present**

> Any class left unmarked at 10 PM is auto-marked as Present (holiday days are skipped).
''',
    ),
  _GuideSection(
      title: '5. Calendar View',
      openInAppLabel: 'Open Calendar',
      openTarget: _GuideOpenTarget.calendar,
      markdown: '''
## Overview
Open **Calendar** from the app bar to review attendance across dates.

---

## Date Actions
Tap any past date to:
- View class-wise status
- Edit attendance
- Use bulk actions for that date

> Upcoming dates are read-only.
''',
    ),
  _GuideSection(
      title: '6. Bunk Meter',
      openInAppLabel: 'Open Bunk Meter',
      openTarget: _GuideOpenTarget.bunkMeterTab,
      markdown: '''
## Overview
The **Bunk Meter** predicts where each subject stands against your target.

---

## Subject Metrics
For each subject, it shows:
- Current %
- Held / Attended / Bunked counts
- Remaining classes

---

## Prediction Summary
It also tells whether you can bunk safely, need to attend more, or if the target is unreachable.
''',
    ),
  _GuideSection(
      title: '7. Notifications',
      openInAppLabel: 'Open Today Page',
      openTarget: _GuideOpenTarget.todayTab,
      markdown: '''
## Overview
AttendMate sends notifications when classes end.

---

## Quick Actions
From each notification, you can:
- **Mark Present**
- **Mark Absent**

Tap notification body to open **Today**.

> Ensure notification permissions are enabled in Android settings.
''',
    ),
  _GuideSection(
      title: '8. More',
      openInAppLabel: 'Open More Page',
      openTarget: _GuideOpenTarget.moreTab,
      markdown: '''
## Overview
The **More** page contains app info, update tools, guide access, and support links.

---

## Available Items
- **Use 24-hour format** toggle
- **App version**
- **Build number**
- **App updates**
- **What's New**
- **Current version release date**
- **Setup Guide**
- **Support me**
- **Request feature / Report bug**

---

## Notes
- **App updates** opens the install/update flow directly when an update is available.
- **What's New** opens the in-app release notes page.
''',
    ),
  _GuideSection(
      title: '9. Tips & Tricks',
      openInAppLabel: 'Open Today Page',
      openTarget: _GuideOpenTarget.todayTab,
      markdown: '''
## Tips
- Color-code subjects for faster recognition.
- Use JSON import to save setup time.
- Keep notifications enabled for quick marking.
- Use Calendar to fix past mistakes.
- Use **Holiday** when classes are officially cancelled.

> All attendance data is stored locally on your device.
''',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _goToPage(int page) async {
    await _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  Future<void> _copyAiPrompt() async {
    await Clipboard.setData(const ClipboardData(text: _aiPrompt));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showReplacingSnackBar(
      const SnackBar(content: Text('AI prompt copied to clipboard.')),
    );
  }

  void _openSectionInApp(_GuideOpenTarget target) {
    switch (target) {
      case _GuideOpenTarget.todayTab:
        return _openHomeTab(0);
      case _GuideOpenTarget.subjectsTab:
        return _openHomeTab(1);
      case _GuideOpenTarget.semesterTab:
        return _openHomeTab(2);
      case _GuideOpenTarget.bunkMeterTab:
        return _openHomeTab(3);
      case _GuideOpenTarget.moreTab:
        return _openHomeTab(4);
      case _GuideOpenTarget.addSubject:
        return _openHomeTab(1, subLevelBuilder: (context) => const AddSubjectScreen());
      case _GuideOpenTarget.importTimetable:
        return _openHomeTab(1, subLevelBuilder: (context) => const ImportTimetableScreen());
      case _GuideOpenTarget.calendar:
        return _openHomeTab(0, subLevelBuilder: (context) => const CalendarScreen());
    }
  }

  void _openHomeTab(
    int tabIndex, {
    WidgetBuilder? subLevelBuilder,
  }) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => HomeScreen(initialPageIndex: tabIndex),
      ),
      (route) => false,
    );

    if (subLevelBuilder != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final nav = navigatorKey.currentState;
        if (nav == null || !nav.mounted) {
          return;
        }
        nav.push(MaterialPageRoute(builder: subLevelBuilder));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final blockquoteBackground = colorScheme.surfaceContainerHighest;
    final codeBackground = colorScheme.surfaceContainerHigh;

    final markdownStyle = MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      blockquoteDecoration: BoxDecoration(
        color: blockquoteBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      blockquotePadding: const EdgeInsets.all(12),
      codeblockDecoration: BoxDecoration(
        color: codeBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      code: TextStyle(
        backgroundColor: codeBackground,
      ),
    );

    final totalPages = _sections.length + 1;
    final sectionIndex = _currentPage - 1;
    final appBarTitle = _currentPage == 0
        ? 'Setup Guide'
        : _sections[sectionIndex].title;

    return PopScope(
      canPop: _currentPage == 0,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_currentPage > 0) {
          await _goToPage(0);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(appBarTitle),
        ),
        body: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (page) {
                  setState(() {
                    _currentPage = page;
                  });
                },
                itemCount: totalPages,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _TableOfContentsPage(
                      sections: _sections,
                      onSelectSection: (section) => _goToPage(section + 1),
                    );
                  }

                  final section = _sections[index - 1];
                  return _GuideSectionPage(
                    markdown: section.markdown,
                    markdownStyle: markdownStyle,
                    aiPromptCopyText: section.aiPromptCopyText,
                    onCopyPrompt: _copyAiPrompt,
                    openInAppLabel: section.openInAppLabel,
                    onOpenInApp: section.openTarget == null
                        ? null
                        : () => _openSectionInApp(section.openTarget!),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _currentPage == 0
                        ? null
                        : () => _goToPage(_currentPage - 1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Center(
                      child: Text('Page ${_currentPage + 1} of $totalPages'),
                    ),
                  ),
                  IconButton(
                    onPressed: _currentPage == totalPages - 1
                        ? null
                        : () => _goToPage(_currentPage + 1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideSection {
  final String title;
  final String markdown;
  final String? aiPromptCopyText;
  final String? openInAppLabel;
  final _GuideOpenTarget? openTarget;

  _GuideSection({
    required this.title,
    required this.markdown,
    this.aiPromptCopyText,
    this.openInAppLabel,
    this.openTarget,
  });
}

enum _GuideOpenTarget {
  todayTab,
  subjectsTab,
  semesterTab,
  bunkMeterTab,
  moreTab,
  addSubject,
  importTimetable,
  calendar,
}

class _TableOfContentsPage extends StatelessWidget {
  final List<_GuideSection> sections;
  final ValueChanged<int> onSelectSection;

  const _TableOfContentsPage({
    required this.sections,
    required this.onSelectSection,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'AttendMate — Setup & User Guide',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Swipe like a book, or jump directly using the table of contents.',
        ),
        const SizedBox(height: 16),
        ...List.generate(sections.length, (index) {
          return ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: Text(sections[index].title),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onSelectSection(index),
          );
        }),
      ],
    );
  }
}

class _GuideSectionPage extends StatelessWidget {
  final String markdown;
  final MarkdownStyleSheet markdownStyle;
  final String? aiPromptCopyText;
  final VoidCallback onCopyPrompt;
  final String? openInAppLabel;
  final VoidCallback? onOpenInApp;

  const _GuideSectionPage({
    required this.markdown,
    required this.markdownStyle,
    this.aiPromptCopyText,
    required this.onCopyPrompt,
    this.openInAppLabel,
    this.onOpenInApp,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (onOpenInApp != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: onOpenInApp,
                  icon: const Icon(Icons.open_in_new_outlined),
                  label: Text(openInAppLabel ?? 'Open in App'),
                ),
              ],
            ),
          ),
        Expanded(
          child: Markdown(
            data: markdown,
            styleSheet: markdownStyle,
            builders: {
              'pre': _CodeBlockBuilder(
                aiPromptText: aiPromptCopyText,
                onCopyPrompt: onCopyPrompt,
              ),
            },
            padding: const EdgeInsets.all(16),
          ),
        ),
      ],
    );
  }
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  final String? aiPromptText;
  final VoidCallback onCopyPrompt;

  _CodeBlockBuilder({
    required this.aiPromptText,
    required this.onCopyPrompt,
  });

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final codeText = element.textContent;
    final shouldShowCopy = aiPromptText != null;

    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final isDarkMode = theme.brightness == Brightness.dark;
        final codeBlockBackground = shouldShowCopy
            ? (isDarkMode
                ? colorScheme.surfaceContainerHighest
                : colorScheme.surfaceContainerLow)
            : colorScheme.surfaceContainerHigh;
        final borderColor = shouldShowCopy
            ? colorScheme.outline
            : colorScheme.outlineVariant;

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: codeBlockBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor.withValues(alpha: 0.7)),
            boxShadow: shouldShowCopy
                ? [
                    BoxShadow(
                      color: colorScheme.shadow.withValues(alpha: isDarkMode ? 0.35 : 0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (shouldShowCopy)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainer,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'AI Prompt',
                        style: theme.textTheme.labelLarge,
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: onCopyPrompt,
                        icon: const Icon(Icons.copy_outlined),
                        label: const Text('Copy'),
                      ),
                    ],
                  ),
                ),
              if (shouldShowCopy)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    codeText,
                    style: (preferredStyle ?? const TextStyle()).copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                )
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    codeText,
                    style: (preferredStyle ?? const TextStyle()).copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}