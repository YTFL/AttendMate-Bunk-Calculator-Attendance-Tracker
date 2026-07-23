import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/database_service.dart';
import 'location_map_picker.dart';
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
    _loadLocations();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleLocationPermission();
    });
  }

  Future<void> _loadLocations() async {
    setState(() => _isLoading = true);
    try {
      final locs = await DatabaseService().loadLocations();
      setState(() {
        _locations = locs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
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
              'Bunk needs "Precise" location to distinguish between classrooms within 25 metres. Please enable Precise location in your device settings.',
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
    // On Android 10+ background location is a separate permission level.
    // whileInUse = app must be open; always = works when app is closed.
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
        // requestPermission() on Android 10+ triggers the background upgrade
        // if foreground is already granted — but many launchers require
        // openAppSettings() for a clean UI. We try requestPermission first.
        final bgPermission = await Geolocator.requestPermission();
        if (bgPermission != LocationPermission.always && mounted) {
          await Geolocator.openAppSettings();
        }
      }
    }

    return true;
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
          content: SizedBox(
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
                                  setDialogState(() => isFetchingGps = true);
                                  final hasPermission = await _handleLocationPermission();
                                  if (hasPermission) {
                                    try {
                                      final pos = await Geolocator.getCurrentPosition(
                                        locationSettings: const LocationSettings(
                                          accuracy: LocationAccuracy.high,
                                        ),
                                      );
                                      setDialogState(() {
                                        latitude = pos.latitude;
                                        longitude = pos.longitude;
                                        isFetchingGps = false;
                                      });
                                    } catch (e) {
                                      setDialogState(() => isFetchingGps = false);
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Error getting coordinates: $e')),
                                        );
                                      }
                                    }
                                  } else {
                                    setDialogState(() => isFetchingGps = false);
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
                            _showMapPickerDialog(
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
                          label: const Text('Select Map'),
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
                    const SnackBar(content: Text('Room / Location Name is required')),
                  );
                  return;
                }

                if (latitude != null && (latitude! < -90.0 || latitude! > 90.0)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Invalid Latitude $latitude: Must be between -90.0° and +90.0°')),
                  );
                  return;
                }

                if (longitude != null && (longitude! < -180.0 || longitude! > 180.0)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Invalid Longitude $longitude: Must be between -180.0° and +180.0°')),
                  );
                  return;
                }

                final newLoc = LocationConfig(
                  id: location?.id ?? const Uuid().v4(),
                  name: name,
                  block: blockController.text.trim().isEmpty ? null : blockController.text.trim(),
                  latitude: latitude,
                  longitude: longitude,
                );

                Navigator.pop(dialogCtx);
                setState(() => _isLoading = true);
                await DatabaseService().saveLocation(newLoc);
                _loadLocations();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteLocation(String id) async {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: isDarkMode ? Colors.white.withValues(alpha: 0.12) : null,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Location'),
        content: const Text(
          'Are you sure you want to delete this location? Subjects linked to this room will revert to text-only mode.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      await DatabaseService().deleteLocation(id);
      _loadLocations();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Locations & Geofencing'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _locations.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.pin_drop_outlined, size: 64, color: colorScheme.onSurface.withValues(alpha: 0.3)),
                      const SizedBox(height: 16),
                      Text(
                        'No Locations Configured',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.onSurface.withValues(alpha: 0.7)),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          'Add rooms or lecture halls, set coordinates, and enable auto-attendance.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: colorScheme.onSurface.withValues(alpha: 0.5)),
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () => _showAddEditLocationDialog(),
                        icon: const Icon(Icons.add),
                        label: const Text('Add Location'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _locations.length,
                  itemBuilder: (ctx, index) {
                    final loc = _locations[index];
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
                            color: hasGps ? Colors.green.withValues(alpha: 0.1) : colorScheme.surfaceContainerHigh,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            hasGps ? Icons.gps_fixed : Icons.pin_drop_outlined,
                            color: hasGps ? Colors.green : colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        title: Text(
                          loc.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (loc.block != null)
                              Text(
                                'Block: ${loc.block!}',
                                style: const TextStyle(fontSize: 13),
                              ),
                            const SizedBox(height: 4),
                            Text(
                              hasGps ? 'Geofence Active (25m radius)' : 'Text label (No Geofence)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: hasGps ? Colors.green.shade700 : Colors.grey,
                              ),
                            ),
                          ],
                        ),
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
                  },
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
