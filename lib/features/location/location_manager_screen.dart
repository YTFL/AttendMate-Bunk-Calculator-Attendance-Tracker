import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/database_service.dart';
import '../../utils/snackbar_utils.dart';
import '../../widgets/day_cycle_background.dart';
import 'location_map_picker.dart';
import 'location_model.dart';

enum _LocationFilter { all, geofenced, unmapped }

class LocationManagerScreen extends StatefulWidget {
  const LocationManagerScreen({super.key});

  @override
  State<LocationManagerScreen> createState() => _LocationManagerScreenState();
}

class _LocationManagerScreenState extends State<LocationManagerScreen> {
  List<LocationConfig> _locations = [];
  Map<String, List<String>> _linkedSubjectsByLocation = {};
  bool _isLoading = true;
  _LocationFilter _currentFilter = _LocationFilter.all;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Live Proximity State
  bool _isTestingProximity = false;
  Map<String, double> _proximityDistances = {}; // locationId -> distance in meters
  String? _proximityStatusMessage;
  String? _capturingLocationId;

  @override
  void initState() {
    super.initState();
    _loadLocations(showLoading: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleLocationPermission();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLocations({bool showLoading = false}) async {
    if (showLoading) {
      setState(() => _isLoading = true);
    }
    try {
      final locs = await DatabaseService().loadLocations();
      final subjects = await DatabaseService().loadSubjects();

      // Index subjects associated with each location
      final Map<String, List<String>> linkedMap = {};
      for (final sub in subjects) {
        if (sub.locationId != null && sub.locationId!.isNotEmpty) {
          linkedMap.putIfAbsent(sub.locationId!, () => []).add(sub.name);
        }
        for (final slot in sub.schedule) {
          if (slot.locationId != null && slot.locationId!.isNotEmpty) {
            final list = linkedMap.putIfAbsent(slot.locationId!, () => []);
            if (!list.contains(sub.name)) {
              list.add(sub.name);
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _locations = locs;
          _linkedSubjectsByLocation = linkedMap;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        SnackbarUtils.showErrorSnackBar(context, 'Failed to load locations: $e');
      }
    }
  }

  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        SnackbarUtils.showErrorSnackBar(
          context,
          'Location services are disabled. Please enable GPS in device settings.',
        );
      }
      return false;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          SnackbarUtils.showErrorSnackBar(context, 'Location permission was denied.');
        }
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Location permissions are permanently denied.'),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () => Geolocator.openAppSettings(),
            ),
          ),
        );
      }
      return false;
    }

    // Check accuracy status
    try {
      final accuracy = await Geolocator.getLocationAccuracy();
      if (accuracy == LocationAccuracyStatus.reduced && mounted) {
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        await showDialog(
          context: context,
          barrierColor: Colors.black.withValues(alpha: isDarkMode ? 0.65 : 0.45),
          builder: (ctx) => AlertDialog(
            backgroundColor: isDarkMode ? const Color(0xFF16161A) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Precise Location Required'),
            content: const Text(
              'AttendMate requires "Precise" location accuracy to distinguish between classrooms within 25 metres. Please enable Precise location.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Later'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Geolocator.openAppSettings();
                },
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );
      }
    } catch (_) {}

    // Check background location permission
    if (permission == LocationPermission.whileInUse && mounted) {
      final isDarkMode = Theme.of(context).brightness == Brightness.dark;
      final wantsBackground = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: isDarkMode ? 0.65 : 0.45),
        builder: (ctx) => AlertDialog(
          backgroundColor: isDarkMode ? const Color(0xFF16161A) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          icon: const Icon(Icons.sensors, size: 36),
          title: const Text('Background Geofencing'),
          content: const Text(
            'Auto-attendance checks your proximity 5 minutes after class starts — even when your screen is off.\n\n'
            'For this to function seamlessly, please select "Allow all the time" in device settings.\n\n'
            'We strictly protect privacy and never monitor your location outside your timetable windows.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Skip'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Configure'),
            ),
          ],
        ),
      );

      if (wantsBackground == true) {
        final bgPermission = await Geolocator.requestPermission();
        if (bgPermission != LocationPermission.always && mounted) {
          await Geolocator.openAppSettings();
        }
      }
    }

    return true;
  }

  // ── Live Campus Proximity Scan ──────────────────────────────────────────────
  Future<void> _scanCampusProximity() async {
    final hasPerm = await _handleLocationPermission();
    if (!hasPerm) return;

    HapticFeedback.mediumImpact();
    setState(() {
      _isTestingProximity = true;
      _proximityStatusMessage = 'Acquiring high-precision GPS lock...';
    });

    try {
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            timeLimit: Duration(seconds: 12),
          ),
        );
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }

      if (pos == null) {
        if (mounted) {
          setState(() {
            _isTestingProximity = false;
            _proximityStatusMessage = 'Could not acquire GPS position. Try stepping outdoors or near a window.';
          });
        }
        return;
      }

      final currentPos = pos;
      final Map<String, double> dists = {};
      String? inRangeRoom;
      double? minDistance;
      String? closestRoom;

      for (final loc in _locations) {
        if (loc.latitude != null && loc.longitude != null) {
          final d = Geolocator.distanceBetween(
            currentPos.latitude,
            currentPos.longitude,
            loc.latitude!,
            loc.longitude!,
          );
          dists[loc.id] = d;
          if (d <= 25.0 && inRangeRoom == null) {
            inRangeRoom = loc.name;
          }
          if (minDistance == null || d < minDistance) {
            minDistance = d;
            closestRoom = loc.name;
          }
        }
      }

      if (mounted) {
        setState(() {
          _isTestingProximity = false;
          _proximityDistances = dists;

          if (inRangeRoom != null) {
            final dist = dists.entries
                .firstWhere((e) => _locations.any((l) => l.id == e.key && l.name == inRangeRoom))
                .value;
            _proximityStatusMessage =
                'In Range: "$inRangeRoom" (${dist.toStringAsFixed(1)}m away)';
          } else if (closestRoom != null && minDistance != null) {
            final distStr = minDistance < 1000
                ? '${minDistance.toStringAsFixed(0)}m'
                : '${(minDistance / 1000).toStringAsFixed(1)}km';
            _proximityStatusMessage =
                'Nearest: "$closestRoom" ($distStr away)';
          } else {
            _proximityStatusMessage =
                'GPS location acquired. No classrooms have coordinates configured yet.';
          }
        });
        HapticFeedback.lightImpact();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTestingProximity = false;
          _proximityStatusMessage = 'Proximity scan error: $e';
        });
      }
    }
  }

  // ── One-Tap Fast GPS Capture Directly on Card ─────────────────────────────
  Future<void> _captureGpsForRoom(LocationConfig loc) async {
    final hasPerm = await _handleLocationPermission();
    if (!hasPerm) return;

    HapticFeedback.selectionClick();
    setState(() => _capturingLocationId = loc.id);

    try {
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            timeLimit: Duration(seconds: 12),
          ),
        );
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }

      if (pos == null) {
        if (mounted) {
          setState(() => _capturingLocationId = null);
          SnackbarUtils.showErrorSnackBar(
            context,
            'Unable to obtain GPS fix. Try stepping near a window or select on map.',
          );
        }
        return;
      }

      final updated = loc.copyWith(
        latitude: pos.latitude,
        longitude: pos.longitude,
      );
      await DatabaseService().saveLocation(updated);
      await _loadLocations(showLoading: false);

      if (mounted) {
        setState(() => _capturingLocationId = null);
        HapticFeedback.mediumImpact();
        SnackbarUtils.showSuccessSnackBar(
          context,
          '📍 Captured GPS for "${loc.name}" (±${pos.accuracy.toStringAsFixed(1)}m accuracy)!',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _capturingLocationId = null);
        SnackbarUtils.showErrorSnackBar(context, 'Failed to capture GPS: $e');
      }
    }
  }

  Future<void> _showMapPickerDialog(
    Function(double lat, double lng) onSelect, {
    double? initialLat,
    double? initialLng,
  }) async {
    final result = await showDialog<Map<String, double>>(
      context: context,
      builder: (ctx) => InteractiveMapPickerDialog(
        initialLatitude: initialLat,
        initialLongitude: initialLng,
      ),
    );

    if (result != null && result.containsKey('latitude') && result.containsKey('longitude')) {
      onSelect(result['latitude']!, result['longitude']!);
    }
  }

  void _showAddEditLocationSheet([LocationConfig? location]) {
    final nameController = TextEditingController(text: location?.name);
    final blockController = TextEditingController(text: location?.block);
    double? latitude = location?.latitude;
    double? longitude = location?.longitude;
    bool isFetchingGps = false;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final presets = ['Room', 'Lecture Hall', 'Lab', 'Auditorium', 'Seminar Room', 'Library'];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: isDarkMode ? 0.65 : 0.45),
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final colorScheme = Theme.of(context).colorScheme;
          final viewInsets = MediaQuery.of(ctx).viewInsets.bottom;

          return Padding(
            padding: EdgeInsets.only(bottom: viewInsets),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  decoration: BoxDecoration(
                    color: isDarkMode
                        ? const Color(0xFF121218).withValues(alpha: 0.72)
                        : Colors.white.withValues(alpha: 0.78),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                    border: Border(
                      top: BorderSide(
                        color: isDarkMode
                            ? Colors.white.withValues(alpha: 0.16)
                            : Colors.white.withValues(alpha: 0.60),
                        width: 1.0,
                      ),
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Drag Pill
                        Center(
                          child: Container(
                            width: 44,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 18),
                            decoration: BoxDecoration(
                              color: isDarkMode
                                  ? Colors.white.withValues(alpha: 0.25)
                                  : Colors.black.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),

                        // Title & Subtitle Row
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: colorScheme.primary.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: colorScheme.primary.withValues(alpha: 0.25),
                                ),
                              ),
                              child: Icon(
                                location == null
                                    ? Icons.add_location_alt_rounded
                                    : Icons.edit_location_alt_rounded,
                                color: colorScheme.primary,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    location == null ? 'Add Classroom Location' : 'Edit Location',
                                    style: GoogleFonts.inter(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '25m radius automated proximity detection',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 18),

                        // Quick Presets
                        Text(
                          'QUICK PRESETS',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: presets.map((preset) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ActionChip(
                                  label: Text(preset, style: const TextStyle(fontSize: 12)),
                                  backgroundColor: isDarkMode
                                      ? Colors.white.withValues(alpha: 0.06)
                                      : Colors.black.withValues(alpha: 0.04),
                                  side: BorderSide(
                                    color: isDarkMode
                                        ? Colors.white.withValues(alpha: 0.12)
                                        : Colors.black.withValues(alpha: 0.08),
                                  ),
                                  onPressed: () {
                                    HapticFeedback.selectionClick();
                                    final current = nameController.text.trim();
                                    if (current.isEmpty || presets.contains(current)) {
                                      nameController.text = preset;
                                    } else {
                                      nameController.text = '$preset $current';
                                    }
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Room / Location Name Input
                        TextFormField(
                          controller: nameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: 'Room / Lecture Hall',
                            hintText: 'e.g., Room 402, Lab A, B707',
                            filled: true,
                            fillColor: isDarkMode
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.black.withValues(alpha: 0.03),
                            prefixIcon: const Icon(Icons.meeting_room_outlined, size: 20),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: isDarkMode ? Colors.white12 : Colors.grey.shade300,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: isDarkMode ? Colors.white12 : Colors.grey.shade300,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 14),

                        // Block / Building Input
                        TextFormField(
                          controller: blockController,
                          textCapitalization: TextCapitalization.characters,
                          decoration: InputDecoration(
                            labelText: 'Block / Building Wing (Optional)',
                            hintText: 'e.g., B Block, Science Wing, Central Tower',
                            filled: true,
                            fillColor: isDarkMode
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.black.withValues(alpha: 0.03),
                            prefixIcon: const Icon(Icons.business_outlined, size: 20),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: isDarkMode ? Colors.white12 : Colors.grey.shade300,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: isDarkMode ? Colors.white12 : Colors.grey.shade300,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Coordinate Status Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'GEOFENCE COORDINATES',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            if (latitude != null && longitude != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_circle, color: Colors.green, size: 12),
                                    SizedBox(width: 4),
                                    Text(
                                      'Active 25m Zone',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        // Coordinate Display Card
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: latitude != null && longitude != null
                                ? Colors.green.withValues(alpha: 0.08)
                                : (isDarkMode
                                    ? Colors.white.withValues(alpha: 0.04)
                                    : Colors.black.withValues(alpha: 0.03)),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: latitude != null && longitude != null
                                  ? Colors.green.withValues(alpha: 0.3)
                                  : (isDarkMode ? Colors.white12 : Colors.grey.shade300),
                            ),
                          ),
                          child: latitude != null && longitude != null
                              ? Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withValues(alpha: 0.15),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.gps_fixed,
                                        color: Colors.green,
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${latitude!.toStringAsFixed(6)}°, ${longitude!.toStringAsFixed(6)}°',
                                            style: GoogleFonts.robotoMono(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: colorScheme.onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          const Text(
                                            'Coordinates set for 25m proximity detection',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.green,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close_rounded, size: 20),
                                      tooltip: 'Clear coordinates',
                                      color: colorScheme.error,
                                      onPressed: () {
                                        setSheetState(() {
                                          latitude = null;
                                          longitude = null;
                                        });
                                      },
                                    ),
                                  ],
                                )
                              : Row(
                                  children: [
                                    Icon(
                                      Icons.location_off_outlined,
                                      size: 20,
                                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'No coordinates assigned yet. Use GPS or Map Picker below.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                        ),

                        const SizedBox(height: 14),

                        // Action Buttons: Use GPS & Pick on Map
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: isFetchingGps
                                    ? null
                                    : () async {
                                        final hasPermission = await _handleLocationPermission();
                                        if (!hasPermission) return;

                                        setSheetState(() => isFetchingGps = true);
                                        try {
                                          Position? pos;
                                          try {
                                            pos = await Geolocator.getCurrentPosition(
                                              locationSettings: const LocationSettings(
                                                accuracy: LocationAccuracy.best,
                                                timeLimit: Duration(seconds: 15),
                                              ),
                                            );
                                          } catch (_) {
                                            pos = await Geolocator.getLastKnownPosition();
                                          }

                                          final currentPos = pos;
                                          if (currentPos != null) {
                                            setSheetState(() {
                                              latitude = currentPos.latitude;
                                              longitude = currentPos.longitude;
                                              isFetchingGps = false;
                                            });
                                            if (mounted) {
                                              HapticFeedback.lightImpact();
                                            }
                                          } else {
                                            setSheetState(() => isFetchingGps = false);
                                            if (mounted) {
                                              SnackbarUtils.showErrorSnackBar(
                                                context,
                                                'Could not obtain GPS location. Please try Map Picker.',
                                              );
                                            }
                                          }
                                        } catch (e) {
                                          setSheetState(() => isFetchingGps = false);
                                          if (mounted) {
                                            SnackbarUtils.showErrorSnackBar(
                                              context,
                                              'Error getting coordinates: $e',
                                            );
                                          }
                                        }
                                      },
                                icon: isFetchingGps
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.my_location, size: 16),
                                label: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(isFetchingGps ? 'Locking GPS...' : 'Use Current GPS'),
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  _showMapPickerDialog(
                                    (lat, lng) {
                                      setSheetState(() {
                                        latitude = lat;
                                        longitude = lng;
                                      });
                                    },
                                    initialLat: latitude,
                                    initialLng: longitude,
                                  );
                                },
                                icon: const Icon(Icons.map_outlined, size: 16),
                                label: const FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text('Select on Map'),
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Action Row: Cancel & Save
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () => Navigator.pop(sheetContext),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: FilledButton(
                                onPressed: () async {
                                  final name = nameController.text.trim();
                                  if (name.isEmpty) {
                                    SnackbarUtils.showErrorSnackBar(
                                      context,
                                      'Room / Location Name is required',
                                    );
                                    return;
                                  }

                                  if (latitude != null && (latitude! < -90.0 || latitude! > 90.0)) {
                                    SnackbarUtils.showErrorSnackBar(
                                      context,
                                      'Invalid Latitude: Must be between -90.0° and +90.0°',
                                    );
                                    return;
                                  }

                                  if (longitude != null &&
                                      (longitude! < -180.0 || longitude! > 180.0)) {
                                    SnackbarUtils.showErrorSnackBar(
                                      context,
                                      'Invalid Longitude: Must be between -180.0° and +180.0°',
                                    );
                                    return;
                                  }

                                  final newLoc = LocationConfig(
                                    id: location?.id ?? const Uuid().v4(),
                                    name: name,
                                    block: blockController.text.trim().isEmpty
                                        ? null
                                        : blockController.text.trim(),
                                    latitude: latitude,
                                    longitude: longitude,
                                  );

                                  Navigator.pop(sheetContext);
                                  await DatabaseService().saveLocation(newLoc);
                                  _loadLocations(showLoading: false);
                                  if (mounted) {
                                    SnackbarUtils.showSuccessSnackBar(
                                      context,
                                      location == null
                                          ? 'Location added successfully.'
                                          : 'Location updated.',
                                    );
                                  }
                                },
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: Text(
                                  location == null ? 'Save Location' : 'Update Location',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
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
            ),
          );
        },
      ),
    );
  }

  Future<void> _deleteLocation(LocationConfig loc) async {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: isDarkMode ? 0.65 : 0.45),
      builder: (ctx) => AlertDialog(
        backgroundColor: isDarkMode ? const Color(0xFF16161A) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Location?'),
        content: Text(
          'Are you sure you want to delete "${loc.name}"? Linked subjects will revert to manual attendance mode.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseService().deleteLocation(loc.id);
      _loadLocations(showLoading: false);
      if (mounted) {
        SnackbarUtils.showSuccessSnackBar(context, 'Location deleted.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDarkMode = theme.brightness == Brightness.dark;

    final mappedCount = _locations.where((l) => l.latitude != null && l.longitude != null).length;
    final unmappedCount = _locations.length - mappedCount;

    // Filtered list
    final filteredLocations = _locations.where((loc) {
      final matchesSearch = _searchQuery.isEmpty ||
          loc.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (loc.block != null && loc.block!.toLowerCase().contains(_searchQuery.toLowerCase()));

      if (!matchesSearch) return false;

      switch (_currentFilter) {
        case _LocationFilter.all:
          return true;
        case _LocationFilter.geofenced:
          return loc.latitude != null && loc.longitude != null;
        case _LocationFilter.unmapped:
          return loc.latitude == null || loc.longitude == null;
      }
    }).toList();

    return DayCycleBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(
            'Locations & Geofencing',
            style: GoogleFonts.inter(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.help_outline_rounded),
              tooltip: 'How Geofencing Works',
              onPressed: () => _showGeofencingGuideDialog(context, isDarkMode),
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        // ── Real-World Classroom Presence & Proximity Card ───────────
                        _buildPresenceStatusCard(
                          colorScheme: colorScheme,
                          isDarkMode: isDarkMode,
                          mappedCount: mappedCount,
                          unmappedCount: unmappedCount,
                        ),

                        const SizedBox(height: 18),

                        // ── Quick Filter Tabs & Search Bar ───────────────────────
                        _buildFilterAndSearchSection(
                          colorScheme: colorScheme,
                          isDarkMode: isDarkMode,
                          totalCount: _locations.length,
                          mappedCount: mappedCount,
                          unmappedCount: unmappedCount,
                        ),

                        const SizedBox(height: 14),

                        // ── Section Header ───────────────────────────────────────
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.room_preferences_rounded,
                                  size: 15,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'CLASSROOM LOCATIONS',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.8,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              '${filteredLocations.length} ${_currentFilter == _LocationFilter.all ? 'total' : 'matched'}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),
                      ]),
                    ),
                  ),

                  // ── Locations List or Empty State ────────────────────────
                  if (filteredLocations.isEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverToBoxAdapter(
                        child: _buildEmptyState(
                          colorScheme: colorScheme,
                          isDarkMode: isDarkMode,
                          isFilterEmpty: _locations.isNotEmpty,
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList.builder(
                        itemCount: filteredLocations.length,
                        itemBuilder: (context, index) {
                          return _buildTactileLocationCard(
                            loc: filteredLocations[index],
                            colorScheme: colorScheme,
                            isDarkMode: isDarkMode,
                          );
                        },
                      ),
                    ),

                  const SliverToBoxAdapter(
                    child: SizedBox(height: 80),
                  ),
                ],
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            HapticFeedback.lightImpact();
            _showAddEditLocationSheet();
          },
          icon: const Icon(Icons.add_location_alt_rounded),
          label: Text(
            'Add Location',
            style: GoogleFonts.inter(fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  // ── Practical Classroom Presence Card ──────────────────────────────────────
  Widget _buildPresenceStatusCard({
    required ColorScheme colorScheme,
    required bool isDarkMode,
    required int mappedCount,
    required int unmappedCount,
  }) {
    final totalCount = _locations.length;
    final allMapped = totalCount > 0 && mappedCount == totalCount;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color(0xFF14141C).withValues(alpha: 0.65)
            : Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDarkMode
              ? Colors.white.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.60),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDarkMode ? 0.25 : 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: Icon, Title & Real Mapped Status badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: isDarkMode ? 0.15 : 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.near_me_rounded,
                  size: 20,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Classroom Presence',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Auto-marks attendance within 25m of your classroom',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Clean status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: allMapped
                      ? Colors.green.withValues(alpha: isDarkMode ? 0.18 : 0.12)
                      : (mappedCount > 0
                          ? colorScheme.primary.withValues(alpha: isDarkMode ? 0.18 : 0.10)
                          : (isDarkMode ? Colors.white10 : Colors.black.withValues(alpha: 0.06))),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: allMapped
                        ? Colors.green.withValues(alpha: 0.3)
                        : (mappedCount > 0
                            ? colorScheme.primary.withValues(alpha: 0.25)
                            : Colors.transparent),
                  ),
                ),
                child: Text(
                  totalCount == 0
                      ? 'No Rooms'
                      : (allMapped
                          ? 'All Set'
                          : '$mappedCount/$totalCount Mapped'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: allMapped
                        ? (isDarkMode ? const Color(0xFF4ADE80) : Colors.green.shade800)
                        : (mappedCount > 0
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Detection Result or Guide
          if (_isTestingProximity)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDarkMode ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Acquiring GPS location...',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            )
          else if (_proximityStatusMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _proximityStatusMessage!.startsWith('In Range')
                    ? Colors.green.withValues(alpha: isDarkMode ? 0.15 : 0.08)
                    : Colors.amber.withValues(alpha: isDarkMode ? 0.15 : 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _proximityStatusMessage!.startsWith('In Range')
                      ? Colors.green.withValues(alpha: 0.3)
                      : Colors.amber.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _proximityStatusMessage!.startsWith('In Range')
                        ? Icons.check_circle_rounded
                        : Icons.info_outline_rounded,
                    size: 18,
                    color: _proximityStatusMessage!.startsWith('In Range')
                        ? (isDarkMode ? const Color(0xFF4ADE80) : Colors.green.shade800)
                        : (isDarkMode ? Colors.amber : Colors.amber.shade900),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _proximityStatusMessage!.startsWith('In Range')
                              ? 'Inside Attendance Zone'
                              : 'Outside Attendance Zone',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _proximityStatusMessage!,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      setState(() {
                        _proximityStatusMessage = null;
                        _proximityDistances.clear();
                      });
                    },
                  ),
                ],
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? Colors.white.withValues(alpha: 0.03)
                    : Colors.black.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDarkMode ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.my_location_rounded,
                    size: 16,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Test if your seat is recognized inside any saved classroom.',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 12),

          // Action button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isTestingProximity ? null : _scanCampusProximity,
              icon: const Icon(Icons.my_location_rounded, size: 15),
              label: Text(
                _proximityStatusMessage != null ? 'Re-check Current Location' : 'Check Classroom Proximity',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                side: BorderSide(
                  color: isDarkMode ? Colors.white24 : Colors.black26,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Filter and Search Section ──────────────────────────────────────────────
  Widget _buildFilterAndSearchSection({
    required ColorScheme colorScheme,
    required bool isDarkMode,
    required int totalCount,
    required int mappedCount,
    required int unmappedCount,
  }) {
    return Column(
      children: [
        // Filter pills row
        Row(
          children: [
            _buildFilterChip(
              title: 'All',
              count: totalCount,
              filter: _LocationFilter.all,
              colorScheme: colorScheme,
              isDarkMode: isDarkMode,
            ),
            const SizedBox(width: 8),
            _buildFilterChip(
              title: 'Geofenced',
              count: mappedCount,
              filter: _LocationFilter.geofenced,
              colorScheme: colorScheme,
              isDarkMode: isDarkMode,
              activeColor: const Color(0xFF22C55E),
            ),
            const SizedBox(width: 8),
            _buildFilterChip(
              title: 'Needs GPS',
              count: unmappedCount,
              filter: _LocationFilter.unmapped,
              colorScheme: colorScheme,
              isDarkMode: isDarkMode,
              activeColor: Colors.orange,
            ),
          ],
        ),

        // Search Bar (Shown when user has 3+ locations)
        if (_locations.length >= 3) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Search by room or building...',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: isDarkMode
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.03),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: isDarkMode ? Colors.white12 : Colors.black12,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: isDarkMode ? Colors.white12 : Colors.black12,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFilterChip({
    required String title,
    required int count,
    required _LocationFilter filter,
    required ColorScheme colorScheme,
    required bool isDarkMode,
    Color? activeColor,
  }) {
    final isSelected = _currentFilter == filter;
    final primaryColor = activeColor ?? colorScheme.primary;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _currentFilter = filter);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? primaryColor.withValues(alpha: isDarkMode ? 0.22 : 0.12)
                : (isDarkMode ? const Color(0xFF13131A) : Colors.white.withValues(alpha: 0.6)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? primaryColor.withValues(alpha: 0.45)
                  : (isDarkMode ? Colors.white10 : Colors.black12),
              width: isSelected ? 1.4 : 1.0,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? primaryColor : colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? primaryColor.withValues(alpha: 0.2)
                      : (isDarkMode ? Colors.white10 : Colors.black.withValues(alpha: 0.06)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? primaryColor : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Tactile Location Beacon Card ───────────────────────────────────────────
  Widget _buildTactileLocationCard({
    required LocationConfig loc,
    required ColorScheme colorScheme,
    required bool isDarkMode,
  }) {
    final hasGps = loc.latitude != null && loc.longitude != null;
    final linkedSubjects = _linkedSubjectsByLocation[loc.id] ?? [];
    final isCapturing = _capturingLocationId == loc.id;
    final distance = _proximityDistances[loc.id];
    final isInRange = distance != null && distance <= 25.0;

    // Generate room initials or icon
    final monogram = loc.name.length <= 4
        ? loc.name.toUpperCase()
        : loc.name.split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(3).join().toUpperCase();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDarkMode
              ? (isInRange
                  ? const Color(0xFF14241B).withValues(alpha: 0.70)
                  : const Color(0xFF14141C).withValues(alpha: 0.65))
              : (isInRange
                  ? const Color(0xFFF0FDF4).withValues(alpha: 0.85)
                  : Colors.white.withValues(alpha: 0.75)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isInRange
                ? Colors.green.withValues(alpha: 0.6)
                : (hasGps
                    ? (isDarkMode
                        ? Colors.white.withValues(alpha: 0.14)
                        : Colors.white.withValues(alpha: 0.60))
                    : Colors.orange.withValues(alpha: 0.45)),
            width: isInRange ? 1.6 : 1.0,
          ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDarkMode ? 0.25 : 0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Monogram avatar + Room Name + Status Beacon
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Monogram Beacon Badge
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: hasGps
                              ? [
                                  const Color(0xFF22C55E).withValues(alpha: 0.25),
                                  const Color(0xFF16A34A).withValues(alpha: 0.10),
                                ]
                              : [
                                  Colors.orange.withValues(alpha: 0.25),
                                  Colors.orange.withValues(alpha: 0.08),
                                ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: hasGps
                              ? const Color(0xFF22C55E).withValues(alpha: 0.4)
                              : Colors.orange.withValues(alpha: 0.4),
                          width: 1.2,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          monogram.isNotEmpty ? monogram : 'LOC',
                          style: GoogleFonts.inter(
                            fontSize: monogram.length > 3 ? 11 : 13,
                            fontWeight: FontWeight.bold,
                            color: hasGps ? const Color(0xFF22C55E) : Colors.orange,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Title & Building Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  loc.name,
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              if (isInRange) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'IN RANGE',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                Icons.business_rounded,
                                size: 13,
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  loc.block != null && loc.block!.isNotEmpty
                                      ? loc.block!
                                      : 'No building assigned',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Actions Menu (Map, Edit, Delete)
                    PopupMenuButton<String>(
                      icon: Icon(
                        Icons.more_vert_rounded,
                        size: 20,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      color: isDarkMode ? const Color(0xFF16161A) : Colors.white,
                      elevation: 8,
                      onSelected: (val) {
                        if (val == 'edit') {
                          _showAddEditLocationSheet(loc);
                        } else if (val == 'map') {
                          _showMapPickerDialog(
                            (lat, lng) async {
                              final updated = loc.copyWith(latitude: lat, longitude: lng);
                              await DatabaseService().saveLocation(updated);
                              _loadLocations(showLoading: false);
                            },
                            initialLat: loc.latitude,
                            initialLng: loc.longitude,
                          );
                        } else if (val == 'delete') {
                          _deleteLocation(loc);
                        }
                      },
                      itemBuilder: (ctx) => [
                        if (hasGps)
                          const PopupMenuItem(
                            value: 'map',
                            child: Row(
                              children: [
                                Icon(Icons.map_outlined, size: 18),
                                SizedBox(width: 10),
                                Text('Adjust on Map'),
                              ],
                            ),
                          ),
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit_outlined, size: 18),
                              SizedBox(width: 10),
                              Text('Edit Details'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                              const SizedBox(width: 10),
                              Text('Delete', style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Middle Row: Linked Subjects (if any)
                if (linkedSubjects.isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: linkedSubjects.map((subName) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: colorScheme.primary.withValues(alpha: 0.16),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_stories_rounded, size: 11, color: colorScheme.primary),
                            const SizedBox(width: 4),
                            Text(
                              subName,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                ],

                // Bottom State Bar: Coordinates or Call to Action
                if (hasGps) ...[
                  // GPS Active Bar
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? Colors.white.withValues(alpha: 0.04)
                          : Colors.black.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDarkMode ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.gps_fixed, size: 14, color: Color(0xFF22C55E)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${loc.latitude!.toStringAsFixed(6)}°,  ${loc.longitude!.toStringAsFixed(6)}°',
                            style: GoogleFonts.robotoMono(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface.withValues(alpha: 0.85),
                            ),
                          ),
                        ),
                        if (distance != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isInRange
                                  ? Colors.green.withValues(alpha: 0.2)
                                  : (isDarkMode ? Colors.white10 : Colors.black12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              distance < 1000
                                  ? '${distance.toStringAsFixed(1)}m away'
                                  : '${(distance / 1000).toStringAsFixed(1)}km away',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isInRange ? Colors.green : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        else
                          Text(
                            '25m Safe Zone',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                            ),
                          ),
                      ],
                    ),
                  ),
                ] else ...[
                  // Unmapped Alert & Direct One-Tap Capture
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: isDarkMode ? 0.12 : 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange),
                            SizedBox(width: 6),
                            Text(
                              'No GPS Coordinates Set',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Auto-attendance will skip geofencing until coordinates are mapped.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: isDarkMode ? Colors.orange.shade200 : Colors.orange.shade900,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            // Direct "Capture GPS Here" Button
                            Expanded(
                              flex: 3,
                              child: FilledButton.icon(
                                onPressed: isCapturing ? null : () => _captureGpsForRoom(loc),
                                icon: isCapturing
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.my_location, size: 15),
                                label: Text(
                                  isCapturing ? 'Locking...' : 'Capture GPS Here',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.orange.shade800,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // "Select on Map" Button
                            Expanded(
                              flex: 2,
                              child: OutlinedButton(
                                onPressed: () {
                                  _showMapPickerDialog(
                                    (lat, lng) async {
                                      final updated = loc.copyWith(latitude: lat, longitude: lng);
                                      await DatabaseService().saveLocation(updated);
                                      _loadLocations(showLoading: false);
                                    },
                                    initialLat: loc.latitude,
                                    initialLng: loc.longitude,
                                  );
                                },
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  side: BorderSide(
                                    color: isDarkMode ? Colors.white24 : Colors.black26,
                                  ),
                                ),
                                child: const Text(
                                  'Pin on Map',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }

  // ── Empty State ────────────────────────────────────────────────────────────
  Widget _buildEmptyState({
    required ColorScheme colorScheme,
    required bool isDarkMode,
    required bool isFilterEmpty,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
          decoration: BoxDecoration(
            color: isDarkMode
                ? const Color(0xFF14141E).withValues(alpha: 0.50)
                : Colors.white.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDarkMode
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.black.withValues(alpha: 0.08),
            ),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isFilterEmpty ? Icons.filter_alt_off_rounded : Icons.pin_drop_outlined,
                  size: 38,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isFilterEmpty ? 'No Rooms Match This Filter' : 'No Classroom Locations Configured',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isFilterEmpty
                    ? 'Switch back to "All" or clear search to view all campus locations.'
                    : 'Add lecture halls, laboratories, or seminar rooms to enable automated 25m presence verification.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              if (!isFilterEmpty)
                FilledButton.icon(
                  onPressed: () => _showAddEditLocationSheet(),
                  icon: const Icon(Icons.add_location_alt_rounded),
                  label: const Text('Add First Location'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                )
              else
                TextButton(
                  onPressed: () {
                    setState(() {
                      _currentFilter = _LocationFilter.all;
                      _searchQuery = '';
                      _searchController.clear();
                    });
                  },
                  child: const Text('Show All Locations'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Info Guide Dialog ──────────────────────────────────────────────────────
  void _showGeofencingGuideDialog(BuildContext context, bool isDarkMode) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: isDarkMode ? 0.65 : 0.45),
      builder: (ctx) => AlertDialog(
        backgroundColor: isDarkMode ? const Color(0xFF16161A) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.radar_rounded, color: Colors.green, size: 22),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'How Geofencing Works',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildGuideBullet(
              icon: Icons.timer_outlined,
              title: '5-Minute Window Check',
              description:
                  '5 minutes after a scheduled lecture starts, AttendMate wakes up briefly in the background.',
            ),
            const SizedBox(height: 12),
            _buildGuideBullet(
              icon: Icons.adjust_rounded,
              title: '25-Metre Precision Radius',
              description:
                  'If your device is within 25m of the classroom coordinates, attendance is automatically marked Present.',
            ),
            const SizedBox(height: 12),
            _buildGuideBullet(
              icon: Icons.shield_outlined,
              title: 'Battery & Privacy Friendly',
              description:
                  'GPS runs only for a few seconds during scheduled class windows and never tracks outside campus hours.',
            ),
          ],
        ),
        actions: [
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Understood'),
          ),
        ],
      ),
    );
  }

  Widget _buildGuideBullet({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.green),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: const TextStyle(fontSize: 12, height: 1.35),
              ),
            ],
          ),
        ),
      ],
    );
  }
}


