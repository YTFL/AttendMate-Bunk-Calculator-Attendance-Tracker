import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/settings/time_format_provider.dart';

/// Centralized app-wide helper to show a time picker dialog based on the user's
/// global [ClockStyle] preference (Material Dialog vs Scroll Wheel).
Future<TimeOfDay?> showAppTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  String helpText = 'Select Time',
}) async {
  final provider = Provider.of<TimeFormatProvider>(context, listen: false);

  if (provider.clockStyle == ClockStyle.material) {
    return await showTimePicker(
      context: context,
      initialTime: initialTime,
      helpText: helpText,
      builder: (ctx, child) {
        return MediaQuery(
          data: MediaQuery.of(ctx).copyWith(
            alwaysUse24HourFormat: provider.is24Hour,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  } else {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return await showDialog<TimeOfDay>(
      context: context,
      barrierColor: isDarkMode ? Colors.white.withValues(alpha: 0.12) : null,
      builder: (BuildContext dialogCtx) {
        return CustomScrollTimePickerDialog(
          initialTime: initialTime,
          helpText: helpText,
          is24Hour: provider.is24Hour,
        );
      },
    );
  }
}

/// Custom scroll-wheel time picker using CupertinoPicker
class CustomScrollTimePickerDialog extends StatefulWidget {
  final TimeOfDay initialTime;
  final String helpText;
  final bool is24Hour;

  const CustomScrollTimePickerDialog({
    super.key,
    required this.initialTime,
    required this.helpText,
    required this.is24Hour,
  });

  @override
  State<CustomScrollTimePickerDialog> createState() => _CustomScrollTimePickerDialogState();
}

class _CustomScrollTimePickerDialogState extends State<CustomScrollTimePickerDialog> {
  late FixedExtentScrollController _hourController;
  late FixedExtentScrollController _minuteController;
  FixedExtentScrollController? _periodController;

  @override
  void initState() {
    super.initState();
    final hour = widget.initialTime.hour;
    final minute = widget.initialTime.minute;

    if (widget.is24Hour) {
      _hourController = FixedExtentScrollController(initialItem: hour);
      _minuteController = FixedExtentScrollController(initialItem: minute);
    } else {
      final isPm = hour >= 12;
      final hour12 = hour % 12;
      final initialHourIndex = (hour12 == 0 ? 12 : hour12) - 1;

      _hourController = FixedExtentScrollController(initialItem: initialHourIndex);
      _minuteController = FixedExtentScrollController(initialItem: minute);
      _periodController = FixedExtentScrollController(initialItem: isPm ? 1 : 0);
    }
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    _periodController?.dispose();
    super.dispose();
  }

  int _wrapIndex(int value, int length) {
    return value % length < 0 ? (value % length) + length : value % length;
  }

  TimeOfDay _getCurrentTime() {
    if (widget.is24Hour) {
      return TimeOfDay(
        hour: _wrapIndex(_hourController.selectedItem, 24),
        minute: _wrapIndex(_minuteController.selectedItem, 60),
      );
    } else {
      final hour12 = _wrapIndex(_hourController.selectedItem, 12) + 1;
      final isPm = (_periodController?.selectedItem ?? 0) == 1;
      int hour24;
      if (isPm) {
        hour24 = hour12 == 12 ? 12 : hour12 + 12;
      } else {
        hour24 = hour12 == 12 ? 0 : hour12;
      }
      return TimeOfDay(
        hour: hour24,
        minute: _wrapIndex(_minuteController.selectedItem, 60),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = TextStyle(
      color: theme.colorScheme.onSurface,
      fontSize: 34,
      fontWeight: FontWeight.bold,
    );

    return AlertDialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      contentPadding: EdgeInsets.zero,
      titlePadding: const EdgeInsets.only(top: 20, left: 24, right: 24),
      title: Text(
        widget.helpText,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurface,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Hours Wheel
              SizedBox(
                width: 80,
                height: 220,
                child: CupertinoPicker(
                  scrollController: _hourController,
                  itemExtent: 48,
                  looping: true,
                  onSelectedItemChanged: (_) {},
                  children: List.generate(widget.is24Hour ? 24 : 12, (index) {
                    final val = widget.is24Hour ? index : index + 1;
                    return Center(
                      child: Text(
                        val.toString().padLeft(2, '0'),
                        style: textStyle,
                      ),
                    );
                  }),
                ),
              ),
              
              // Separator colon
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  ':',
                  style: textStyle.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
              
              // Minutes Wheel
              SizedBox(
                width: 80,
                height: 220,
                child: CupertinoPicker(
                  scrollController: _minuteController,
                  itemExtent: 48,
                  looping: true,
                  onSelectedItemChanged: (_) {},
                  children: List.generate(60, (index) {
                    return Center(
                      child: Text(
                        index.toString().padLeft(2, '0'),
                        style: textStyle,
                      ),
                    );
                  }),
                ),
              ),

              if (!widget.is24Hour) ...[
                const SizedBox(width: 24),
                SizedBox(
                  width: 80,
                  height: 220,
                  child: CupertinoPicker(
                    scrollController: _periodController,
                    itemExtent: 48,
                    onSelectedItemChanged: (_) {},
                    children: [
                      Center(
                        child: Text(
                          'AM',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      Center(
                        child: Text(
                          'PM',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),
          Divider(
            height: 1,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context, _getCurrentTime());
          },
          child: Text(
            'Done',
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
