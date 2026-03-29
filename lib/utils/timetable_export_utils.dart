import 'dart:io';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../features/subject/subject_model.dart';

class TimetableExportUtils {
  static const daysOfWeek = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  static List<Subject> _extractWeeklySubjects(List<Subject> subjects) {
    final weeklySubjects = <Subject>[];
    for (final subject in subjects) {
      final weeklySchedule = subject.schedule.where((slot) => !slot.isSpecialClass).toList();
      if (weeklySchedule.isEmpty) {
        continue;
      }
      weeklySubjects.add(subject.copyWith(schedule: weeklySchedule));
    }
    return weeklySubjects;
  }

  static Future<Directory> _resolveDownloadsDirectory() async {
    if (Platform.isAndroid) {
      final androidDownloads = Directory('/storage/emulated/0/Download');
      if (await androidDownloads.exists()) {
        return androidDownloads;
      }
      throw const FileSystemException('Could not access Android Downloads folder.');
    }

    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null && userProfile.isNotEmpty) {
        final windowsDownloads = Directory('$userProfile\\Downloads');
        if (await windowsDownloads.exists()) {
          return windowsDownloads;
        }
      }
    }

    final downloads = await getDownloadsDirectory();
    if (downloads != null) {
      if (!await downloads.exists()) {
        await downloads.create(recursive: true);
      }
      return downloads;
    }

    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      final unixDownloads = Directory('$home/Downloads');
      if (await unixDownloads.exists()) {
        return unixDownloads;
      }
    }

    throw const FileSystemException('Could not resolve Downloads folder on this device.');
  }

  static Future<File> _createExportFile(String extension) async {
    final directory = await _resolveDownloadsDirectory();
    final timestamp = DateFormat('yyyy-MM-dd_HHmmss').format(DateTime.now());
    return File('${directory.path}${Platform.pathSeparator}timetable_$timestamp.$extension');
  }

  /// Build a grid-based timetable structure
  static Map<String, dynamic> _buildTimetableGrid(List<Subject> subjects) {
    // Extract unique time slots by normalized key to avoid duplicates
    // across different Subject instances that share the same time range.
    final slotKeyToOrder = <String, int>{};
    final slotKeys = <String>[];
    for (final subject in subjects) {
      for (final slot in subject.schedule) {
        final key = _timeSlotKey(slot);
        final order = slot.startTime.hour * 60 + slot.startTime.minute;
        if (!slotKeyToOrder.containsKey(key)) {
          slotKeyToOrder[key] = order;
          slotKeys.add(key);
        }
      }
    }

    slotKeys.sort((a, b) => (slotKeyToOrder[a] ?? 0).compareTo(slotKeyToOrder[b] ?? 0));

    // Create grid: day -> timeSlot -> subject
    final grid = <String, Map<String, String>>{};
    
    for (final day in daysOfWeek) {
      grid[day] = {};
      for (final slotKey in slotKeys) {
        grid[day]![slotKey] = '-';
      }
    }

    // Fill in the subjects
    for (final subject in subjects) {
      for (final slot in subject.schedule) {
        final dayName = _dayOfWeekToString(slot.day);
        final slotKey = _timeSlotKey(slot);
        grid[dayName]![slotKey] = subject.acronym ?? subject.name;
      }
    }

    return {
      'timeSlots': slotKeys,
      'grid': grid,
    };
  }

  static String _timeSlotKey(TimeSlot slot) {
    final start = '${slot.startTime.hour.toString().padLeft(2, '0')}:${slot.startTime.minute.toString().padLeft(2, '0')}';
    final end = '${slot.endTime.hour.toString().padLeft(2, '0')}:${slot.endTime.minute.toString().padLeft(2, '0')}';
    return '$start-$end';
  }

  static String _dayOfWeekToString(DayOfWeek day) {
    const names = {
      DayOfWeek.monday: 'Monday',
      DayOfWeek.tuesday: 'Tuesday',
      DayOfWeek.wednesday: 'Wednesday',
      DayOfWeek.thursday: 'Thursday',
      DayOfWeek.friday: 'Friday',
      DayOfWeek.saturday: 'Saturday',
      DayOfWeek.sunday: 'Sunday',
    };
    return names[day] ?? day.name;
  }

  /// Export as JSON file
  static Future<File> exportAsJsonFile(List<Subject> subjects) async {
    final weeklySubjects = _extractWeeklySubjects(subjects);
    final jsonData = _buildImportCompatibleJson(weeklySubjects);

    final jsonString = _prettyJsonEncode(jsonData);
    
    final file = await _createExportFile('json');
    
    await file.writeAsString(jsonString);
    return file;
  }

  static Map<String, dynamic> _buildImportCompatibleJson(List<Subject> subjects) {
    final subjectList = <Map<String, dynamic>>[];

    for (final subject in subjects) {
      final schedule = subject.schedule.map((slot) {
        return {
          'day': slot.day.name.toLowerCase(),
          'startTime': _formatTime(slot.startTime.hour, slot.startTime.minute),
          'endTime': _formatTime(slot.endTime.hour, slot.endTime.minute),
        };
      }).toList();

      final item = <String, dynamic>{
        'name': subject.name,
        if (subject.acronym != null && subject.acronym!.trim().isNotEmpty)
          'acronym': subject.acronym!.trim(),
        'schedule': schedule,
      };

      subjectList.add(item);
    }

    return {
      'subjects': subjectList,
    };
  }

  static String _formatTime(int hour, int minute) {
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  /// Export as CSV file
  static Future<File> exportAsCsvFile(List<Subject> subjects) async {
    final weeklySubjects = _extractWeeklySubjects(subjects);
    final timetableGrid = _buildTimetableGrid(weeklySubjects);
    final timeSlots = timetableGrid['timeSlots'] as List;
    final grid = timetableGrid['grid'] as Map<String, dynamic>;

    final csv = StringBuffer();
    
    // Header row
    csv.write('Day');
    for (final slot in timeSlots) {
      csv.write(',"${_normalizeForExport(slot.toString())}"');
    }
    csv.write('\r\n');

    // Data rows
    for (final day in daysOfWeek) {
      csv.write(_normalizeForExport(day));
      for (final slot in timeSlots) {
        final subject = grid[day]?[slot] ?? '-';
        csv.write(',"${_normalizeForExport(subject.toString())}"');
      }
      csv.write('\r\n');
    }

    final file = await _createExportFile('csv');

    // Write UTF-8 BOM so Excel-like apps decode characters correctly.
    await file.writeAsString('\uFEFF${csv.toString()}');
    return file;
  }

  /// Export subjects as PDF in landscape mode with tables
  static Future<File> exportAsPDF(List<Subject> subjects) async {
    final markdownTable = exportAsMarkdownTable(subjects);
    final rows = _parseMarkdownTable(markdownTable);

    if (rows.length < 2) {
      throw const FormatException('Unable to generate valid timetable table data for PDF export.');
    }

    final headers = rows.first;
    final dataRows = rows.skip(1).toList();
    final columnCount = headers.length;
    final columnWidths = <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(1.35),
      for (int i = 1; i < columnCount; i++) i: const pw.FlexColumnWidth(1),
    };

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(14, 14, 14, 14),
        build: (context) {
          return [
            pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Weekly Timetable',
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 5),
              pw.Text(
                'Exported on ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.SizedBox(height: 10),
              pw.TableHelper.fromTextArray(
                headers: headers,
                data: dataRows,
                border: pw.TableBorder.all(color: PdfColors.black, width: 0.7),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
                headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                cellStyle: const pw.TextStyle(fontSize: 8),
                headerAlignment: pw.Alignment.center,
                cellAlignment: pw.Alignment.center,
                columnWidths: columnWidths,
                cellHeight: 24,
              ),
            ],
          ),
          ];
        },
      ),
    );

    final file = await _createExportFile('pdf');
    
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  static String exportAsMarkdownTable(List<Subject> subjects) {
    final weeklySubjects = _extractWeeklySubjects(subjects);
    final timetableGrid = _buildTimetableGrid(weeklySubjects);
    final timeSlots = (timetableGrid['timeSlots'] as List<dynamic>).cast<String>();
    final grid = timetableGrid['grid'] as Map<String, dynamic>;

    final headerRow = ['Day', ...timeSlots];
    final separatorRow = List<String>.filled(headerRow.length, '-----------');

    final lines = <String>[
      '| ${headerRow.join(' | ')} |',
      '| ${separatorRow.join(' | ')} |',
    ];

    for (final day in daysOfWeek) {
      final row = <String>[day];
      for (final slot in timeSlots) {
        row.add(_normalizeForExport((grid[day] as Map<String, dynamic>)[slot]?.toString() ?? '-'));
      }
      lines.add('| ${row.join(' | ')} |');
    }

    return lines.join('\n');
  }

  static List<List<String>> _parseMarkdownTable(String markdownTable) {
    final lines = markdownTable
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.startsWith('|') && line.endsWith('|'))
        .toList();

    final rows = <List<String>>[];
    for (final line in lines) {
      final cells = line
          .split('|')
          .map((cell) => cell.trim())
          .where((cell) => cell.isNotEmpty)
          .toList();

      final isSeparator = cells.isNotEmpty &&
          cells.every((cell) => RegExp(r'^:?-{3,}:?$').hasMatch(cell));

      if (!isSeparator && cells.isNotEmpty) {
        rows.add(cells);
      }
    }

    return rows;
  }

  static String _normalizeForExport(String value) {
    final normalized = value
        .replaceAll('\u2012', '-')
        .replaceAll('\u2013', '-')
        .replaceAll('\u2014', '-')
        .replaceAll('\u2015', '-')
        .replaceAll('\u2212', '-')
        .replaceAll('—', '-')
        .replaceAll('–', '-')
        .replaceAll('−', '-')
        .replaceAll('\u00A0', ' ')
        .trim();

    return normalized.isEmpty ? '-' : normalized;
  }

  /// Pretty print JSON string
  static String _prettyJsonEncode(Map<String, dynamic> json) {
    final jsonString = jsonEncode(json);
    return _formatJson(jsonString);
  }

  /// Format JSON string with proper indentation
  static String _formatJson(String jsonString) {
    const indent = '  ';
    String result = '';
    int indentLevel = 0;
    bool inString = false;
    bool escapeNext = false;

    for (int i = 0; i < jsonString.length; i++) {
      final char = jsonString[i];
      final nextChar = i + 1 < jsonString.length ? jsonString[i + 1] : '';

      if (escapeNext) {
        result += char;
        escapeNext = false;
        continue;
      }

      if (char == '\\') {
        result += char;
        escapeNext = true;
        continue;
      }

      if (char == '"' && !escapeNext) {
        inString = !inString;
        result += char;
        continue;
      }

      if (inString) {
        result += char;
        continue;
      }

      if (char == '{' || char == '[') {
        result += char;
        indentLevel++;
        if (nextChar != '}' && nextChar != ']') {
          result += '\n${indent * indentLevel}';
        }
      } else if (char == '}' || char == ']') {
        indentLevel--;
        if (result.endsWith('\n${indent * (indentLevel + 1)}')) {
          result = result.substring(0, result.length - (indent * (indentLevel + 1)).length);
        }
        result += '\n${indent * indentLevel}$char';
      } else if (char == ',') {
        result += char;
        result += '\n${indent * indentLevel}';
      } else if (char == ':') {
        result += '$char ';
      } else if (char != ' ') {
        result += char;
      }
    }

    return result;
  }
}

