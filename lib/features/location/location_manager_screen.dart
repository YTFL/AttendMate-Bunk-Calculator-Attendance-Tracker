import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/database_service.dart';
import 'coordinate_parser.dart';
import 'location_model.dart';

class LocationManagerScreen extends StatefulWidget {
  const LocationManagerScreen({super.key});

  @override
  State<LocationManagerScreen> createState() => _LocationManagerScreenState();
}

class _LocationManagerScreenState extends State<LocationManagerScreen> {
  List<LocationConfig> _locations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLocations(showLoading: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleLocationPermission();
    });
  }

  Future<void> _loadLocations({bool showLoading = false}) async {
    if (showLoading) {
      setState(() => _isLoading = true);
    }
    try {
      final locs = await DatabaseService().loadLocations();
      if (mounted) {
        setState(() {
          _locations = locs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load locations: $e')),
        );
      }
    }
  }

  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location services are disabled. Please enable them.')),
        );
      }
      return false;
    }

    // ── Step 1: Foreground permission ─────────────────────────────────────
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permissions are denied.')),
          );
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
              label: 'Open Settings',
              onPressed: () => Geolocator.openAppSettings(),
            ),
          ),
        );
      }
      return false;
    }

    // ── Step 2: Precise location (Android 12+) ────────────────────────────
    try {
      final accuracy = await Geolocator.getLocationAccuracy();
      if (accuracy == LocationAccuracyStatus.reduced && mounted) {
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        await showDialog(
          context: context,
          barrierColor: isDarkMode ? Colors.white.withValues(alpha: 0.12) : null,
          builder: (ctx) => AlertDialog(
            title: const Text('Precise Location Required'),
            content: const Text(
              'AttendMate needs "Precise" location to distinguish between classrooms within 25 metres. Please enable Precise location in your device settings.',
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

    // ── Step 3: Background location (needed for auto-attendance) ──────────
    if (permission == LocationPermission.whileInUse && mounted) {
      final isDarkMode = Theme.of(context).brightness == Brightness.dark;
      final wantsBackground = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        barrierColor: isDarkMode ? Colors.white.withValues(alpha: 0.12) : null,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.sensors, size: 36),
          title: const Text('Background Location'),
          content: const Text(
            'Auto-attendance checks your location 5 minutes after a class starts — even when the app is closed.\n\n'
            'For this to work, please change the location permission to "Allow all the time" on the next screen.\n\n'
            'We never track you outside of class windows.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Skip'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Go to Settings'),
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

  Future<void> _showCoordinateInputDialog(
    Function(double lat, double lng) onSelect, {
    double? initialLat,
    double? initialLng,
  }) async {
    final textController = TextEditingController(
      text: (initialLat != null && initialLng != null) ? '$initialLat, $initialLng' : '',
    );
    ParsedCoordinates? parsedCoords = (initialLat != null && initialLng != null)
        ? ParsedCoordinates(latitude: initialLat, longitude: initialLng)
        : null;

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    await showDialog(
      context: context,
      barrierColor: isDarkMode ? Colors.white.withValues(alpha: 0.12) : null,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          void updateParsed(String val) {
            setDialogState(() {
              parsedCoords = CoordinateParser.parse(val);
            });
          }

          return AlertDialog(
            icon: const Icon(Icons.location_searching, size: 36, color: Colors.blue),
            title: const Text('Set Location Coordinates'),
            content: SizedBox(
              width: 320,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '1. Open your default Maps app to find your classroom or building.\n'
                      '2. Drop a pin or tap on the location.\n'
                      '3. Copy the coordinates or share the link, then paste it below.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: isDarkMode ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final geoUri = Uri.parse('geo:0,0?q=');
                        final webFallback = Uri.parse('https://www.google.com/maps');
                        try {
                          if (await canLaunchUrl(geoUri)) {
                            await launchUrl(geoUri, mode: LaunchMode.externalApplication);
                          } else {
                            await launchUrl(webFallback, mode: LaunchMode.externalApplication);
                          }
                        } catch (_) {
                          await launchUrl(webFallback, mode: LaunchMode.externalApplication);
                        }
                      },
                      icon: const Icon(Icons.map_outlined, size: 18),
                      label: const Text('Open Default Maps App'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: textController,
                      decoration: InputDecoration(
                        labelText: 'Coordinates or Maps Link',
                        hintText: 'e.g., 12.971598, 77.594566',
                        prefixIcon: const Icon(Icons.pin_drop_outlined, size: 20),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.content_paste, size: 20),
                          tooltip: 'Paste from Clipboard',
                          onPressed: () async {
                            final data = await Clipboard.getData(Clipboard.kTextPlain);
                            final text = data?.text?.trim() ?? '';
                            if (text.isNotEmpty) {
                              textController.text = text;
                              updateParsed(text);
                            }
                          },
                        ),
                      ),
                      onChanged: updateParsed,
                    ),
                    const SizedBox(height: 12),
                    if (parsedCoords != null)
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.green, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Lat: ${parsedCoords!.latitude.toStringAsFixed(6)}\nLng: ${parsedCoords!.longitude.toStringAsFixed(6)}',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green),
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (textController.text.trim().isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Could not parse coordinates. Please enter a valid decimal pair or Google Maps URL.',
                          style: TextStyle(fontSize: 11, color: Colors.red),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: parsedCoords == null
                    ? null
                    : () {
                        onSelect(parsedCoords!.latitude, parsedCoords!.longitude);
                        Navigator.pop(dialogCtx);
                      },
                child: const Text('Set Coordinates'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddEditLocationDialog([LocationConfig? location]) {
    final nameController = TextEditingController(text: location?.name);
    final blockController = TextEditingController(text: location?.block);
    double? latitude = location?.latitude;
    double? longitude = location?.longitude;
    bool isFetchingGps = false;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierColor: isDarkMode ? Colors.white.withValues(alpha: 0.12) : null,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(location == null ? 'Add Location' : 'Edit Location'),
          content: GestureDetector(
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            behavior: HitTestBehavior.translucent,
            child: SizedBox(
              width: 320,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Room / Location Name',
                        hintText: 'e.g., Room 402, Lab A',
                        hintStyle: TextStyle(color: Colors.grey),
                        prefixIcon: Icon(Icons.meeting_room_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: blockController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Block / Building (Optional)',
                        hintText: 'e.g., Block C, CSE Dept',
                        hintStyle: TextStyle(color: Colors.grey),
                        prefixIcon: Icon(Icons.business_outlined),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'GEOFENCE COORDINATES',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: latitude != null && longitude != null
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.gps_fixed, color: Colors.green, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Lat: ${latitude!.toStringAsFixed(6)}\nLng: ${longitude!.toStringAsFixed(6)}',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.clear, color: Colors.red, size: 18),
                                    onPressed: () {
                                      setDialogState(() {
                                        latitude = null;
                                        longitude = null;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            )
                          : Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: isDarkMode ? Colors.white12 : Colors.grey.shade300),
                              ),
                              child: Text(
                                'No geofence coordinates attached.\nAuto-attendance checking will be skipped.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 11, color: isDarkMode ? Colors.white60 : Colors.grey.shade600),
                              ),
                            ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: isFetchingGps
                                ? null
                                : () async {
                                    final hasPermission = await _handleLocationPermission();
                                    if (!hasPermission) return;

                                    setDialogState(() => isFetchingGps = true);
                                    try {
                                      Position? pos;
                                      try {
                                        pos = await Geolocator.getCurrentPosition(
                                          locationSettings: const LocationSettings(
                                            accuracy: LocationAccuracy.high,
                                            timeLimit: Duration(seconds: 15),
                                          ),
                                        );
                                      } catch (_) {
                                        pos = await Geolocator.getLastKnownPosition();
                                      }

                                      final currentPos = pos;
                                      if (currentPos != null) {
                                        final lat = currentPos.latitude;
                                        final lng = currentPos.longitude;
                                        setDialogState(() {
                                          latitude = lat;
                                          longitude = lng;
                                          isFetchingGps = false;
                                        });
                                      } else {
                                        setDialogState(() => isFetchingGps = false);
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Could not obtain current or last known GPS location. Please try again.')),
                                          );
                                        }
                                      }
                                    } catch (e) {
                                      setDialogState(() => isFetchingGps = false);
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Error getting coordinates: $e')),
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
                            label: Text(isFetchingGps ? 'GPS...' : 'Use Current'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              _showCoordinateInputDialog(
                                (lat, lng) {
                                  setDialogState(() {
                                    latitude = lat;
                                    longitude = lng;
                                  });
                                },
                                initialLat: latitude,
                                initialLng: longitude,
                              );
                            },
                            icon: const Icon(Icons.map_outlined, size: 16),
                            label: const Text('Paste / Maps'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
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
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a location name')),
                  );
                  return;
                }

                final block = blockController.text.trim().isEmpty ? null : blockController.text.trim();
                final db = DatabaseService();

                if (location == null) {
                  final newLoc = LocationConfig(
                    id: const Uuid().v4(),
                    name: name,
                    block: block,
                    latitude: latitude,
                    longitude: longitude,
                  );
                  await db.saveLocation(newLoc);
                } else {
                  final updatedLoc = location.copyWith(
                    name: name,
                    block: block,
                    latitude: latitude,
                    longitude: longitude,
                  );
                  await db.saveLocation(updatedLoc);
                }

                if (mounted && dialogCtx.mounted) {
                  Navigator.pop(dialogCtx);
                  _loadLocations();
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteLocation(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Location'),
        content: const Text(
          'Are you sure you want to delete this location? Classes assigned to this location will lose their geofence binding.',
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
      await DatabaseService().deleteLocation(id);
      _loadLocations();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Campus Locations'),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _locations.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.location_off_outlined, size: 64, color: colorScheme.outline),
                      const SizedBox(height: 16),
                      Text(
                        'No Locations Added',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          'Add your classrooms, lecture halls, or labs to enable precise automatic attendance tracking.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () => _showAddEditLocationDialog(),
                        icon: const Icon(Icons.add),
                        label: const Text('Add Location'),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 20, color: colorScheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'For active locations, geofencing considers attendance within 25m of the set location.',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.35,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ..._locations.map((loc) {
                      final hasGps = loc.latitude != null && loc.longitude != null;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                            width: 1,
                          ),
                        ),
                        elevation: 0,
                        color: colorScheme.surfaceContainerLowest,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: hasGps
                                  ? Colors.green.withValues(alpha: 0.12)
                                  : colorScheme.surfaceContainerHighest,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              hasGps ? Icons.gps_fixed : Icons.pin_drop_outlined,
                              color: hasGps ? Colors.green : colorScheme.outline,
                            ),
                          ),
                          title: Text(
                            loc.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          subtitle: loc.block != null
                              ? Text(
                                  'Block: ${loc.block!}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                )
                              : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.edit_outlined, color: colorScheme.primary),
                                onPressed: () => _showAddEditLocationDialog(loc),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                                onPressed: () => _deleteLocation(loc.id),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
      floatingActionButton: _locations.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showAddEditLocationDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Add Location'),
            ),
    );
  }
}
