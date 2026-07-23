import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Official Google Maps Interactive Location Picker Dialog
/// Displays interactive GoogleMap widget, draggable pin marker, 25m geofence radius circle overlay,
/// and physical coordinate boundary validation.
class InteractiveMapPickerDialog extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;

  const InteractiveMapPickerDialog({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
  });

  @override
  State<InteractiveMapPickerDialog> createState() => _InteractiveMapPickerDialogState();
}

class _InteractiveMapPickerDialogState extends State<InteractiveMapPickerDialog> {
  GoogleMapController? _mapController;
  late TextEditingController _latController;
  late TextEditingController _lngController;

  double _lat = 12.971593; // Default fallback (e.g. Bangalore center)
  double _lng = 77.594562;
  bool _isFetchingGps = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _lat = widget.initialLatitude!;
      _lng = widget.initialLongitude!;
    }
    _latController = TextEditingController(text: _lat.toStringAsFixed(6));
    _lngController = TextEditingController(text: _lng.toStringAsFixed(6));
  }

  @override
  void dispose() {
    _latController.dispose();
    _lngController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  void _updateCoordinates(
    double newLat,
    double newLng, {
    bool updateControllers = true,
    bool moveCamera = false,
  }) {
    final clampedLat = double.parse(newLat.clamp(-90.0, 90.0).toStringAsFixed(6));
    final clampedLng = double.parse(newLng.clamp(-180.0, 180.0).toStringAsFixed(6));

    setState(() {
      _lat = clampedLat;
      _lng = clampedLng;
      if (updateControllers) {
        _latController.text = _lat.toStringAsFixed(6);
        _lngController.text = _lng.toStringAsFixed(6);
      }
    });

    if (moveCamera && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLng(LatLng(_lat, _lng)),
      );
    }
  }

  Future<void> _fetchCurrentLocation() async {
    setState(() => _isFetchingGps = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location services are disabled. Please enable GPS.')),
          );
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Location permissions denied.')),
            );
          }
          return;
        }
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      _updateCoordinates(pos.latitude, pos.longitude, moveCamera: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error getting GPS location: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isFetchingGps = false);
      }
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null || data!.text!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Clipboard is empty.')),
        );
      }
      return;
    }

    final text = data.text!.trim();
    // 1. Standard comma separated lat, lng
    final regExp = RegExp(r'(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)');
    final match = regExp.firstMatch(text);
    if (match != null) {
      final parsedLat = double.tryParse(match.group(1) ?? '');
      final parsedLng = double.tryParse(match.group(2) ?? '');
      if (parsedLat != null && parsedLng != null) {
        _validateAndUpdate(parsedLat, parsedLng);
        return;
      }
    }

    // 2. Google Maps URL @lat,lng
    final urlRegExp = RegExp(r'@(-?\d+\.\d+),(-?\d+\.\d+)');
    final urlMatch = urlRegExp.firstMatch(text);
    if (urlMatch != null) {
      final parsedLat = double.tryParse(urlMatch.group(1) ?? '');
      final parsedLng = double.tryParse(urlMatch.group(2) ?? '');
      if (parsedLat != null && parsedLng != null) {
        _validateAndUpdate(parsedLat, parsedLng);
        return;
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not find valid coordinates in clipboard.')),
      );
    }
  }

  bool _validateAndUpdate(double lat, double lng) {
    if (lat < -90.0 || lat > 90.0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invalid Latitude $lat: Must be between -90.0° and +90.0°')),
      );
      return false;
    }
    if (lng < -180.0 || lng > 180.0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invalid Longitude $lng: Must be between -180.0° and +180.0°')),
      );
      return false;
    }

    _updateCoordinates(lat, lng, moveCamera: true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Coordinates updated successfully!')),
      );
    }
    return true;
  }

  void _onConfirm() {
    final lat = double.tryParse(_latController.text.trim());
    final lng = double.tryParse(_lngController.text.trim());

    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter valid numeric decimal coordinates.')),
      );
      return;
    }

    if (lat < -90.0 || lat > 90.0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Latitude ($lat) is out of bounds! Must be between -90.0° and +90.0°')),
      );
      return;
    }

    if (lng < -180.0 || lng > 180.0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Longitude ($lng) is out of bounds! Must be between -180.0° and +180.0°')),
      );
      return;
    }

    Navigator.of(context).pop({'latitude': lat, 'longitude': lng});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    final targetLatLng = LatLng(_lat, _lng);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: theme.scaffoldBackgroundColor,
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Icon(Icons.location_on_outlined, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Google Maps Geofence Picker',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Google Maps Canvas Viewport
            Expanded(
              child: Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: targetLatLng,
                      zoom: 17.5,
                    ),
                    onMapCreated: (controller) => _mapController = controller,
                    onTap: (pos) {
                      _updateCoordinates(pos.latitude, pos.longitude);
                    },
                    onCameraMove: (camPos) {
                      _updateCoordinates(camPos.target.latitude, camPos.target.longitude, updateControllers: true);
                    },
                    markers: {
                      Marker(
                        markerId: const MarkerId('geofence_center_marker'),
                        position: targetLatLng,
                        draggable: true,
                        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                        infoWindow: const InfoWindow(title: 'Geofence Location'),
                        onDragEnd: (newPos) {
                          _updateCoordinates(newPos.latitude, newPos.longitude);
                        },
                      ),
                    },
                    circles: {
                      Circle(
                        circleId: const CircleId('geofence_radius_circle'),
                        center: targetLatLng,
                        radius: 25.0, // 25 Metres Geofence Radius
                        fillColor: Colors.blue.withValues(alpha: 0.25),
                        strokeColor: Colors.blue.shade700,
                        strokeWidth: 2,
                      ),
                    },
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    compassEnabled: true,
                  ),

                  // Center Pin Reticle Overlay
                  Center(
                    child: PointerInterceptor(
                      child: IgnorePointer(
                        child: Icon(
                          Icons.location_searching,
                          size: 28,
                          color: Colors.red.shade700.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ),

                  // Radius Info Badge
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: (isDarkMode ? Colors.black : Colors.white).withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.withValues(alpha: 0.5)),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.adjust, size: 14, color: Colors.blue),
                          SizedBox(width: 6),
                          Text(
                            'Geofence Radius: 25m',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Map Action Buttons (My Location & Zoom)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Column(
                      children: [
                        FloatingActionButton.small(
                          heroTag: 'gmap_my_location',
                          onPressed: _fetchCurrentLocation,
                          backgroundColor: isDarkMode ? Colors.grey.shade800 : Colors.white,
                          child: Icon(
                            Icons.my_location,
                            color: isDarkMode ? Colors.white : Colors.black87,
                            size: 18,
                          ),
                        ),
                        const SizedBox(height: 8),
                        FloatingActionButton.small(
                          heroTag: 'gmap_zoom_in',
                          onPressed: () {
                            _mapController?.animateCamera(CameraUpdate.zoomIn());
                          },
                          backgroundColor: isDarkMode ? Colors.grey.shade800 : Colors.white,
                          child: Icon(Icons.add, color: isDarkMode ? Colors.white : Colors.black87, size: 18),
                        ),
                        const SizedBox(height: 6),
                        FloatingActionButton.small(
                          heroTag: 'gmap_zoom_out',
                          onPressed: () {
                            _mapController?.animateCamera(CameraUpdate.zoomOut());
                          },
                          backgroundColor: isDarkMode ? Colors.grey.shade800 : Colors.white,
                          child: Icon(Icons.remove, color: isDarkMode ? Colors.white : Colors.black87, size: 18),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Controls & Boundary Validation Panel
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isFetchingGps ? null : _fetchCurrentLocation,
                          icon: _isFetchingGps
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.my_location, size: 16),
                          label: Text(_isFetchingGps ? 'Locating...' : 'Use Current GPS'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pasteFromClipboard,
                          icon: const Icon(Icons.content_paste, size: 16),
                          label: const Text('Paste Link/GPS'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _latController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                          decoration: const InputDecoration(
                            labelText: 'Latitude (-90 to +90)',
                            hintText: 'e.g. 12.971593',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            isDense: true,
                          ),
                          onChanged: (val) {
                            final parsed = double.tryParse(val.trim());
                            if (parsed != null && parsed >= -90.0 && parsed <= 90.0) {
                              _updateCoordinates(parsed, _lng, updateControllers: false, moveCamera: true);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _lngController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                          decoration: const InputDecoration(
                            labelText: 'Longitude (-180 to +180)',
                            hintText: 'e.g. 77.594562',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            isDense: true,
                          ),
                          onChanged: (val) {
                            final parsed = double.tryParse(val.trim());
                            if (parsed != null && parsed >= -180.0 && parsed <= 180.0) {
                              _updateCoordinates(_lat, parsed, updateControllers: false, moveCamera: true);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: isDarkMode ? Colors.white70 : Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDarkMode ? Colors.white : Colors.black,
                          foregroundColor: isDarkMode ? Colors.black : Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: _onConfirm,
                        icon: Icon(
                          Icons.check,
                          size: 18,
                          color: isDarkMode ? Colors.black : Colors.white,
                        ),
                        label: Text(
                          'Confirm Location',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: isDarkMode ? Colors.black : Colors.white,
                          ),
                        ),
                      ),
                    ],
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

/// Helper widget to pass events safely when transparent overlays are above GoogleMap
class PointerInterceptor extends StatelessWidget {
  final Widget child;
  const PointerInterceptor({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
