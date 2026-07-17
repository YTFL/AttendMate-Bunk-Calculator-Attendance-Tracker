import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../attendance/attendance_model.dart';
import '../../utils/responsive_scale.dart';
import 'swipe_action_provider.dart';
import 'swipeable_card.dart';

class SwipeActionsSettingsScreen extends StatefulWidget {
  const SwipeActionsSettingsScreen({super.key});

  @override
  State<SwipeActionsSettingsScreen> createState() => _SwipeActionsSettingsScreenState();
}

class _SwipeActionsSettingsScreenState extends State<SwipeActionsSettingsScreen> {
  // Local state for the interactive preview mock card
  AttendanceStatus? _mockStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final provider = Provider.of<SwipeActionProvider>(context);
    final rs = context.rs;

    // Helper to build the swipe background for the mock card
    Widget buildMockSwipeBackground({
      required SwipeAction action,
      required Alignment alignment,
      required bool isUnmarking,
    }) {
      final Color color;
      final IconData icon;

      if (isUnmarking) {
        color = Colors.grey.shade600;
        icon = Icons.undo;
      } else {
        switch (action) {
          case SwipeAction.present:
            color = Colors.green.shade700;
            icon = Icons.check;
            break;
          case SwipeAction.absent:
            color = Colors.red.shade700;
            icon = Icons.close;
            break;
        }
      }

      return Container(
        margin: rs.insetsSymmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(rs.scale(12)),
        ),
        padding: EdgeInsets.symmetric(horizontal: rs.width(20)),
        alignment: alignment,
        child: Icon(icon, color: Colors.white, size: rs.scale(24)),
      );
    }

    // Interactive Preview Card build
    Widget buildPreviewCard() {
      String statusText;
      Color statusColor;
      IconData statusIcon;
      Widget? trailingWidget;

      switch (_mockStatus) {
        case AttendanceStatus.attended:
          statusText = 'Attended';
          statusColor = Colors.green.shade700;
          statusIcon = Icons.check_circle_outline;
          break;
        case AttendanceStatus.absent:
          statusText = 'Absent';
          statusColor = Colors.red.shade700;
          statusIcon = Icons.cancel_outlined;
          break;
        case AttendanceStatus.cancelled:
          statusText = 'Holiday';
          statusColor = Colors.grey.shade600;
          statusIcon = Icons.celebration_outlined;
          break;
        default:
          statusText = 'Awaiting Status';
          statusColor = theme.colorScheme.onSurface.withValues(alpha: 0.7);
          statusIcon = Icons.hourglass_empty;
      }

      // Trailing holiday/unmark toggle button
      if (_mockStatus == AttendanceStatus.cancelled) {
        trailingWidget = IconButton(
          icon: const Icon(Icons.cancel_outlined),
          tooltip: 'Unmark Holiday',
          color: Colors.grey,
          onPressed: () {
            setState(() {
              _mockStatus = null;
            });
            ScaffoldMessenger.of(context).removeCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Preview: Attendance unmarked')),
            );
          },
        );
      } else {
        trailingWidget = IconButton(
          icon: const Icon(Icons.celebration_outlined),
          tooltip: 'Mark Holiday',
          color: Colors.purple,
          onPressed: () {
            setState(() {
              _mockStatus = AttendanceStatus.cancelled;
            });
            ScaffoldMessenger.of(context).removeCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Preview: Marked as Holiday')),
            );
          },
        );
      }

      final rightSwipeAction = provider.rightAction;
      final leftSwipeAction = provider.leftAction;

      final isUnmarkingRight = (_mockStatus == AttendanceStatus.attended && rightSwipeAction == SwipeAction.present) ||
          (_mockStatus == AttendanceStatus.absent && rightSwipeAction == SwipeAction.absent);

      final isUnmarkingLeft = (_mockStatus == AttendanceStatus.attended && leftSwipeAction == SwipeAction.present) ||
          (_mockStatus == AttendanceStatus.absent && leftSwipeAction == SwipeAction.absent);

      return SwipeableCard(
        key: const ValueKey('mock_card'),
        swipeRightBackground: buildMockSwipeBackground(
          action: rightSwipeAction,
          alignment: Alignment.centerLeft,
          isUnmarking: isUnmarkingRight,
        ),
        swipeLeftBackground: buildMockSwipeBackground(
          action: leftSwipeAction,
          alignment: Alignment.centerRight,
          isUnmarking: isUnmarkingLeft,
        ),
        onSwipeRight: () {
          setState(() {
            if (isUnmarkingRight) {
              _mockStatus = null;
            } else {
              _mockStatus = rightSwipeAction == SwipeAction.present
                  ? AttendanceStatus.attended
                  : AttendanceStatus.absent;
            }
          });

          final actionName = isUnmarkingRight
              ? 'Unmarked'
              : (rightSwipeAction == SwipeAction.present ? 'Marked Present' : 'Marked Absent');

          ScaffoldMessenger.of(context).removeCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Preview: $actionName'),
              duration: const Duration(seconds: 1),
            ),
          );
        },
        onSwipeLeft: () {
          setState(() {
            if (isUnmarkingLeft) {
              _mockStatus = null;
            } else {
              _mockStatus = leftSwipeAction == SwipeAction.present
                  ? AttendanceStatus.attended
                  : AttendanceStatus.absent;
            }
          });

          final actionName = isUnmarkingLeft
              ? 'Unmarked'
              : (leftSwipeAction == SwipeAction.present ? 'Marked Present' : 'Marked Absent');

          ScaffoldMessenger.of(context).removeCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Preview: $actionName'),
              duration: const Duration(seconds: 1),
            ),
          );
        },
        rs: rs,
        child: Card(
          elevation: 2.0,
          margin: rs.insetsSymmetric(horizontal: 8, vertical: 6),
          shadowColor: isDarkMode ? null : Colors.black.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rs.scale(12)),
            side: BorderSide(
              color: isDarkMode
                  ? Colors.white.withValues(alpha: 0.4)
                  : theme.colorScheme.onSurface.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: Padding(
            padding: rs.insetsAll(8),
            child: ListTile(
              contentPadding: rs.insetsSymmetric(horizontal: 8, vertical: 2),
              leading: CircleAvatar(
                radius: rs.scale(20.6),
                backgroundColor: theme.colorScheme.primary,
                child: Center(
                  child: Text(
                    'PREV',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: theme.colorScheme.onPrimary,
                      fontSize: rs.font(11),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              title: Text(
                'Demo Class Name',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: rs.font(15)),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('09:00 AM - 10:00 AM'),
                  SizedBox(height: rs.height(4)),
                  Row(
                    children: [
                      Icon(statusIcon, size: rs.scale(16), color: statusColor),
                      SizedBox(width: rs.width(4)),
                      Flexible(
                        child: Text(
                          statusText,
                          style: TextStyle(
                            color: statusColor,
                            fontStyle: FontStyle.italic,
                            fontSize: rs.font(13),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              trailing: trailingWidget,
            ),
          ),
        ),
      );
    }

    // Layout configuration card option build
    Widget buildConfigurationOption({
      required String title,
      required SwipeAction rightAction,
      required SwipeAction leftAction,
      required bool isSelected,
      required VoidCallback onTap,
    }) {
      final borderSide = isSelected
          ? BorderSide(color: theme.colorScheme.primary, width: 2.0)
          : BorderSide(color: theme.colorScheme.onSurface.withValues(alpha: 0.12), width: 1.0);

      final optionColor = isSelected
          ? theme.colorScheme.primary.withValues(alpha: 0.05)
          : null;

      return Card(
        elevation: isSelected ? 2.0 : 0.5,
        color: optionColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rs.scale(12)),
          side: borderSide,
        ),
        margin: rs.insetsSymmetric(vertical: 8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(rs.scale(12)),
          child: Padding(
            padding: rs.insetsAll(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: rs.font(16),
                        color: isSelected ? theme.colorScheme.primary : null,
                      ),
                    ),
                    if (isSelected)
                      Icon(
                        Icons.check_circle,
                        color: theme.colorScheme.primary,
                        size: rs.scale(22),
                      )
                    else
                      Icon(
                        Icons.radio_button_off,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.38),
                        size: rs.scale(22),
                      ),
                  ],
                ),
                SizedBox(height: rs.height(16)),
                // Right Swipe Details
                Row(
                  children: [
                    Icon(
                      Icons.arrow_forward_outlined,
                      color: Colors.green.shade700,
                      size: rs.scale(20),
                    ),
                    SizedBox(width: rs.width(12)),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Swipe Right',
                          style: TextStyle(
                            fontSize: rs.font(12),
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        Text(
                          rightAction.displayName,
                          style: TextStyle(
                            fontSize: rs.font(14),
                            fontWeight: FontWeight.w600,
                            color: rightAction == SwipeAction.present
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                SizedBox(height: rs.height(12)),
                // Left Swipe Details
                Row(
                  children: [
                    Icon(
                      Icons.arrow_back_outlined,
                      color: Colors.red.shade700,
                      size: rs.scale(20),
                    ),
                    SizedBox(width: rs.width(12)),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Swipe Left',
                          style: TextStyle(
                            fontSize: rs.font(12),
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        Text(
                          leftAction.displayName,
                          style: TextStyle(
                            fontSize: rs.font(14),
                            fontWeight: FontWeight.w600,
                            color: leftAction == SwipeAction.present
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Swipe Actions'),
      ),
      body: ListView(
        padding: rs.insetsAll(16),
        children: [
          Text(
            'Customize swipe gestures for your daily classes. Swiping in the direction of an already active status will unmark the attendance.',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              fontSize: rs.font(14),
              height: 1.4,
            ),
          ),
          SizedBox(height: rs.height(24)),
          
          // Preview section
          Text(
            'Interactive Preview',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: rs.font(18),
            ),
          ),
          SizedBox(height: rs.height(4)),
          Text(
            'Swipe the card left or right, or toggle holiday status to test.',
            style: TextStyle(
              fontSize: rs.font(12),
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          SizedBox(height: rs.height(12)),
          buildPreviewCard(),
          SizedBox(height: rs.height(28)),

          // Customization section
          Text(
            'Choose Configuration',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: rs.font(18),
            ),
          ),
          SizedBox(height: rs.height(8)),
          buildConfigurationOption(
            title: 'Option A',
            rightAction: SwipeAction.present,
            leftAction: SwipeAction.absent,
            isSelected: provider.rightAction == SwipeAction.present,
            onTap: () => provider.setRightAction(SwipeAction.present),
          ),
          buildConfigurationOption(
            title: 'Option B',
            rightAction: SwipeAction.absent,
            leftAction: SwipeAction.present,
            isSelected: provider.rightAction == SwipeAction.absent,
            onTap: () => provider.setRightAction(SwipeAction.absent),
          ),
          SizedBox(height: rs.height(20)),
        ],
      ),
    );
  }
}
