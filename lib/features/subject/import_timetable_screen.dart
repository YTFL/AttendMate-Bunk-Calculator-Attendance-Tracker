import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../utils/snackbar_utils.dart';
import '../../utils/timetable_import_utils.dart';
import '../subject/subject_model.dart';
import '../subject/subject_provider.dart';

class ImportTimetableScreen extends StatefulWidget {
  const ImportTimetableScreen({super.key});

  @override
  State<ImportTimetableScreen> createState() => _ImportTimetableScreenState();
}

class _ImportTimetableScreenState extends State<ImportTimetableScreen> {
  final _jsonTextController = TextEditingController();
  String? _errorMessage;
  List<Subject>? _importedSubjects;

  @override
  void dispose() {
    _jsonTextController.dispose();
    super.dispose();
  }

  void _parseAndValidateJson() {
    final jsonString = _jsonTextController.text.trim();
    
    if (jsonString.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter or paste JSON data';
        _importedSubjects = null;
      });
      return;
    }

    try {
      final subjectProvider = Provider.of<SubjectProvider>(context, listen: false);
      final usedColors = subjectProvider.subjects.map((s) => s.color).toSet();
      
      final subjects = TimetableImportUtils.parseJsonToSubjects(jsonString, usedColors);
      
      setState(() {
        _importedSubjects = subjects;
        _errorMessage = null;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _importedSubjects = null;
      });
    }
  }

  void _importSubjects() {
    if (_importedSubjects == null || _importedSubjects!.isEmpty) {
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        const SnackBar(
          content: Text('No valid subjects to import'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final subjectProvider = Provider.of<SubjectProvider>(context, listen: false);
    
    subjectProvider.bulkImportSubjects(_importedSubjects!);
    
    ScaffoldMessenger.of(context).showReplacingSnackBar(
      SnackBar(
        content: Text('Successfully imported ${_importedSubjects!.length} subject(s)'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
    
    Navigator.pop(context);
  }

  void _copyTemplate() {
    final formatRef = _getFormatReference();
    Clipboard.setData(ClipboardData(text: formatRef));
    
    ScaffoldMessenger.of(context).showReplacingSnackBar(
      const SnackBar(
        content: Text('JSON format reference copied to clipboard'),
        backgroundColor: Colors.blue,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _clearInput() {
    setState(() {
      _jsonTextController.clear();
      _errorMessage = null;
      _importedSubjects = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Import Timetable'),
        ),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Instructions
                Card(
                  color: Colors.blue.withAlpha(25),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.blue),
                            SizedBox(width: 8),
                            Text(
                              'Import Instructions',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Paste valid JSON data or use the copy format button to get started. '
                          'You can import single or multiple subjects with all their timeslots. '
                          'Colors are automatically assigned from available unused colors.',
                          style: TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _copyTemplate,
                            icon: const Icon(Icons.content_copy, size: 18),
                            label: const Text('Copy Format Reference'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // JSON Input
                TextFormField(
                  controller: _jsonTextController,
                  minLines: 12,
                  maxLines: 20,
                  decoration: InputDecoration(
                    labelText: 'JSON Data',
                    hintText: 'Paste your JSON data here...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.grey.withValues(alpha: 0.1),
                  ),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                const SizedBox(height: 12),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _parseAndValidateJson,
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text('Parse & Preview'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _clearInput,
                      icon: const Icon(Icons.clear, size: 18),
                      label: const Text('Clear'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Error Message
                if (_errorMessage != null)
                  Card(
                    color: Colors.red.withAlpha(25),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Error',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _errorMessage!,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Preview
                if (_importedSubjects != null && _importedSubjects!.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      const Text(
                        'Preview',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ..._importedSubjects!.map((subject) {
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 16,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        color: subject.color,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        subject.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: subject.schedule.map((slot) {
                                    return Chip(
                                      label: Text(
                                        '${slot.day.name.substring(0, 3).toUpperCase()}: ${slot.startTime.format(context)} - ${slot.endTime.format(context)}',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      backgroundColor: subject.color.withAlpha(50),
                                      padding: const EdgeInsets.symmetric(horizontal: 4),
                                      visualDensity: VisualDensity.compact,
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _importSubjects,
                          icon: const Icon(Icons.download, size: 18),
                          label: Text(
                            'Import ${_importedSubjects!.length} Subject(s)',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),

                // Format Help
                const SizedBox(height: 24),
                ExpansionTile(
                  title: const Text('JSON Format Reference'),
                  children: [
                    Container(
                        color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.grey.withValues(alpha: 0.1),
                      padding: const EdgeInsets.all(12),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Text(
                          _getFormatReference(),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getFormatReference() {
    return '''{
  "subjects": [
    {
      "name": "Mathematics",
      "acronym": "MTH",
      "schedule": [
        {
          "day": "monday",
          "startTime": "09:00",
          "endTime": "10:30"
        },
        {
          "day": "wednesday",
          "startTime": "14:00",
          "endTime": "15:30"
        }
      ]
    },
    {
      "name": "Physics",
      "acronym": "PHY",
      "schedule": [
        {
          "day": "tuesday",
          "startTime": "09:00",
          "endTime": "10:30"
        }
      ]
    }
  ]
}

Days: monday, tuesday, wednesday, thursday, friday, saturday, sunday
Time format: HH:MM (24-hour)
Acronym: optional (e.g., "MTH", "PHY")
Color assignment: automatic from unused colors''';
  }
}
