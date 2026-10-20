import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Official Google Maps Interactive Location Picker Dialog
/// Displays interactive GoogleMap viewport, 25m geofence radius boundary overlay,
/// and an ordered, high-precision coordinate deck.
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
  late FocusNode _latFocusNode;
  late FocusNode _lngFocusNode;

  double _lat = 12.971593; // Default fallback (e.g. campus default)
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
    _latFocusNode = FocusNode();
    _lngFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _latFocusNode.dispose();
    _lngFocusNode.dispose();
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
        if (!_latFocusNode.hasFocus) {
          _latController.text = _lat.toStringAsFixed(6);
        }
        if (!_lngFocusNode.hasFocus) {
          _lngController.text = _lng.toStringAsFixed(6);
        }
      }
    });

    if (moveCamera && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLng(LatLng(_lat, _lng)),
      );
    }
  }

  Future<void> _fetchCurrentLocation() async {
    HapticFeedback.selectionClick();
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
        _updateCoordinates(currentPos.latitude, currentPos.longitude, moveCamera: true);
        HapticFeedback.lightImpact();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not obtain current GPS position. Try moving near a window.')),
          );
        }
      }
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
    HapticFeedback.selectionClick();
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
    HapticFeedback.lightImpact();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Coordinates updated from clipboard!')),
      );
    }
    return true;
  }

  void _onConfirm() {
    HapticFeedback.mediumImpact();
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
    final colorScheme = theme.colorScheme;
    final isDarkMode = theme.brightness == Brightness.dark;

    final targetLatLng = LatLng(_lat, _lng);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: isDarkMode ? Colors.white.withValues(alpha: 0.14) : Colors.black.withValues(alpha: 0.08),
          width: 1.0,
        ),
      ),
      backgroundColor: isDarkMode ? const Color(0xFF141418) : Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 16,
      shadowColor: Colors.black.withValues(alpha: 0.5),
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      child: GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        behavior: HitTestBehavior.translucent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header ───────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 12, 14),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: colorScheme.primary.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Icon(
                        Icons.pin_drop_rounded,
                        color: colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pin Geofence Location',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDarkMode ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            'Drag map to center 25m presence zone',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // ── Google Maps Viewport ──────────────────────────────────────
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
                        FocusManager.instance.primaryFocus?.unfocus();
                        _updateCoordinates(pos.latitude, pos.longitude);
                      },
                      onCameraMove: (camPos) {
                        _updateCoordinates(
                          camPos.target.latitude,
                          camPos.target.longitude,
                          updateControllers: !(_latFocusNode.hasFocus || _lngFocusNode.hasFocus),
                        );
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
                          fillColor: const Color(0xFF22C55E).withValues(alpha: 0.22),
                          strokeColor: const Color(0xFF16A34A),
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

                    // Top-Left: Geofence Radius Pill
                    Positioned(
                      top: 12,
                      left: 12,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: (isDarkMode ? const Color(0xFF121216) : Colors.white)
                                  .withValues(alpha: 0.88),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFF22C55E).withValues(alpha: 0.45),
                              ),
                              boxShadow: const [
                                BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.radar_rounded, size: 14, color: Color(0xFF22C55E)),
                                SizedBox(width: 6),
                                Text(
                                  '25m Safe Zone',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF22C55E),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Top-Right: Unified Frosted Map Controls (Locate + Zoom)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            width: 42,
                            decoration: BoxDecoration(
                              color: (isDarkMode ? const Color(0xFF181820) : Colors.white)
                                  .withValues(alpha: 0.88),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isDarkMode ? Colors.white12 : Colors.black12,
                              ),
                              boxShadow: const [
                                BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                InkWell(
                                  onTap: _isFetchingGps ? null : _fetchCurrentLocation,
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: _isFetchingGps
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : Icon(
                                            Icons.my_location,
                                            size: 20,
                                            color: colorScheme.primary,
                                          ),
                                  ),
                                ),
                                Divider(
                                  height: 1,
                                  color: isDarkMode ? Colors.white12 : Colors.black12,
                                ),
                                InkWell(
                                  onTap: () => _mapController?.animateCamera(CameraUpdate.zoomIn()),
                                  child: const Padding(
                                    padding: EdgeInsets.all(10),
                                    child: Icon(Icons.add, size: 20),
                                  ),
                                ),
                                Divider(
                                  height: 1,
                                  color: isDarkMode ? Colors.white12 : Colors.black12,
                                ),
                                InkWell(
                                  onTap: () => _mapController?.animateCamera(CameraUpdate.zoomOut()),
                                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                                  child: const Padding(
                                    padding: EdgeInsets.all(10),
                                    child: Icon(Icons.remove, size: 20),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Ordered Bottom Control Deck ──────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                decoration: BoxDecoration(
                  color: isDarkMode ? const Color(0xFF101014) : const Color(0xFFF8F9FA),
                  border: Border(
                    top: BorderSide(
                      color: isDarkMode ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Row 1: Quick Action Tool Pills
                    Row(
                      children: [
                        // Live Monospace Coordinates Pill
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: isDarkMode
                                  ? Colors.white.withValues(alpha: 0.05)
                                  : Colors.black.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDarkMode ? Colors.white10 : Colors.black12,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.pin_drop, size: 14, color: Color(0xFF22C55E)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${_lat.toStringAsFixed(6)}°, ${_lng.toStringAsFixed(6)}°',
                                    style: GoogleFonts.robotoMono(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isDarkMode ? Colors.white : Colors.black87,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Action: Paste Coordinates
                        OutlinedButton.icon(
                          onPressed: _pasteFromClipboard,
                          icon: const Icon(Icons.content_paste_rounded, size: 15),
                          label: const Text('Paste', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            side: BorderSide(
                              color: isDarkMode ? Colors.white24 : Colors.black26,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    // Row 2: Symmetrical, Clean Coordinate Inputs
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _latController,
                            focusNode: _latFocusNode,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                            style: GoogleFonts.robotoMono(fontSize: 12.5, fontWeight: FontWeight.bold),
                            decoration: InputDecoration(
                              prefixText: 'LAT: ',
                              prefixStyle: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                              hintText: '12.971593',
                              filled: true,
                              fillColor: isDarkMode
                                  ? Colors.white.withValues(alpha: 0.04)
                                  : Colors.white,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: isDarkMode ? Colors.white12 : Colors.grey.shade300),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: isDarkMode ? Colors.white12 : Colors.grey.shade300),
                              ),
                            ),
                            onChanged: (val) {
                              final parsed = double.tryParse(val.trim());
                              if (parsed != null && parsed >= -90.0 && parsed <= 90.0) {
                                _updateCoordinates(parsed, _lng, updateControllers: false, moveCamera: true);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _lngController,
                            focusNode: _lngFocusNode,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                            style: GoogleFonts.robotoMono(fontSize: 12.5, fontWeight: FontWeight.bold),
                            decoration: InputDecoration(
                              prefixText: 'LNG: ',
                              prefixStyle: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                              hintText: '77.594562',
                              filled: true,
                              fillColor: isDarkMode
                                  ? Colors.white.withValues(alpha: 0.04)
                                  : Colors.white,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: isDarkMode ? Colors.white12 : Colors.grey.shade300),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: isDarkMode ? Colors.white12 : Colors.grey.shade300),
                              ),
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

                    const SizedBox(height: 14),

                    // Row 3: Action Buttons (Cancel & Confirm Location)
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                color: isDarkMode ? Colors.white70 : Colors.black87,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: _onConfirm,
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: const Text(
                              'Confirm Location',
                              style: TextStyle(fontWeight: FontWeight.bold),
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
