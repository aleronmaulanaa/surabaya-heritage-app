import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../providers/place_provider.dart';
import '../../models/place_model.dart';
import '../detail/detail_screen.dart';
import '../../models/review_model.dart';
import '../../utils/app_notification.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  GoogleMapController? _mapController;
  Position? _userPosition;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  PlaceModel? _selectedPlace;
  bool _isLoadingLocation = false;
  bool _isLoadingRoute = false;
  bool _showBottomSheet = false;
  bool _isHoursExpanded = false;
  double _bottomSheetHeight = 0;
  int _slidePage = 0;
  bool _isExpanded = false;
  double _dragOffset = 0;
  double _normalSheetHeight = 0;
  double _overscrollAccum = 0;
  final PageController _slideController = PageController();

  // Navigation route preview
  bool _showRoutePreview = false;
  double _routeEntryOffset = 1.0;
  String _transportMode = 'walking';
  double _routeDistance = 0;
  double _routeDuration = 0;
  List<Map<String, dynamic>> _routeSteps = [];
  List<LatLng> _routePoints = [];

  // Live navigation mode
  bool _isNavigating = false;
  StreamSubscription<Position>? _positionStream;
  bool _isMuted = false;
  bool _isMapCentered = true;
  int _currentStepIndex = 0;
  double _remainingDistance = 0;
  double _remainingDuration = 0;
  int _advanceWarnedStep = -1;
  final FlutterTts _flutterTts = FlutterTts();
  Marker? _userVehicleMarker;
  bool _awaitingLocationPermission = false;
  bool _awaitingGpsEnable = false;

  // Navigation enter/exit animation
  late final AnimationController _navEnterController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );
  late final Animation<double> _navFadeIn = CurvedAnimation(
    parent: _navEnterController,
    curve: Curves.easeOutCubic,
  );
  // Nav bottom sheet
  late final AnimationController _navSheetCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  )..addListener(() => setState(() {}));

  static const CameraPosition _surabayaCenter = CameraPosition(
    target: LatLng(-7.2575, 112.7521),
    zoom: 13,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _getUserLocation();
    _initTts();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _buildMarkers();
    });
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage('id-ID');
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _slideController.dispose();
    _positionStream?.cancel();
    _flutterTts.stop();
    _navEnterController.dispose();
    _navSheetCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        (_awaitingLocationPermission || _awaitingGpsEnable)) {
      _recheckLocationAfterSettings();
    }
  }

  Future<void> _recheckLocationAfterSettings() async {
    if (_awaitingLocationPermission) {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        _awaitingLocationPermission = false;
        _showSnack('Izin lokasi berhasil diberikan!', type: NotifType.success);
        _getUserLocation();
        return;
      }
      _showLocationPermissionNotif();
      return;
    }
    if (_awaitingGpsEnable) {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (enabled) {
        _awaitingGpsEnable = false;
        _showSnack('GPS berhasil diaktifkan!', type: NotifType.success);
        _getUserLocation();
        return;
      }
      _showGpsDisabledNotif();
    }
  }

  void _showLocationPermissionNotif() {
    AppNotification.persistent(
      context,
      message: 'Izin lokasi diblokir. Ketuk untuk membuka pengaturan.',
      type: NotifType.error,
      actionLabel: 'Pengaturan',
      onAction: () {
        _awaitingLocationPermission = true;
        Geolocator.openAppSettings();
      },
    );
  }

  void _showGpsDisabledNotif() {
    AppNotification.persistent(
      context,
      message: 'GPS tidak aktif. Ketuk untuk mengaktifkan.',
      type: NotifType.warning,
      actionLabel: 'Aktifkan',
      onAction: () {
        _awaitingGpsEnable = true;
        Geolocator.openLocationSettings();
      },
    );
  }

  // ── GPS ────────────────────────────────────────────────────
  Future<void> _getUserLocation() async {
    setState(() => _isLoadingLocation = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _isLoadingLocation = false);
        _showGpsDisabledNotif();
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _isLoadingLocation = false);
          _showLocationPermissionNotif();
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() => _isLoadingLocation = false);
        _showLocationPermissionNotif();
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      setState(() {
        _userPosition = position;
        _isLoadingLocation = false;
      });
      if (mounted) {
        context.read<PlaceProvider>().setUserLocation(
          position.latitude,
          position.longitude,
        );
      }
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(position.latitude, position.longitude),
          15,
        ),
      );
    } catch (e) {
      setState(() => _isLoadingLocation = false);
      _showSnack('Gagal menemukan lokasi. Pastikan GPS aktif dan coba lagi.', type: NotifType.error);
    }
  }

  // ── Custom Marker ──────────────────────────────────────────
  Future<BitmapDescriptor> _createCustomMarker(
    String categoryName,
    String placeName,
  ) async {
    final color = _getCategoryColor(categoryName);
    final iconData = _getCategoryIcon(categoryName, placeName);

    const double circleRadius = 60.0;
    const double pinWidth = circleRadius * 2 + 8;
    const double tailHeight = 28.0;
    const double circleY = circleRadius + 4;
    const double totalHeight = circleY + circleRadius + tailHeight + 4;
    const double iconSize = 58.0;

    final shortName = placeName.length > 20
        ? '${placeName.substring(0, 20)}...'
        : placeName;

    final textPainterMeasure = TextPainter(
      text: TextSpan(
        text: shortName,
        style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final double labelWidth = textPainterMeasure.width + 8;
    final double canvasWidth = labelWidth > pinWidth ? labelWidth : pinWidth;
    final double canvasHeight = totalHeight + textPainterMeasure.height + 6;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final double centerX = canvasWidth / 2;

    // ── Shadow ────────────────────────────────────────────
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(
      Offset(centerX + 2, circleY + 2),
      circleRadius,
      shadowPaint,
    );

    // ── Lingkaran utama ───────────────────────────────────
    canvas.drawCircle(
      Offset(centerX, circleY),
      circleRadius,
      Paint()..color = color,
    );

    // ── Border putih ──────────────────────────────────────
    canvas.drawCircle(
      Offset(centerX, circleY),
      circleRadius,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke,
    );

    // ── Ekor pin ──────────────────────────────────────────
    final tailPath = Path()
      ..moveTo(centerX - 10, circleY + circleRadius - 2)
      ..lineTo(centerX + 10, circleY + circleRadius - 2)
      ..lineTo(centerX, circleY + circleRadius + tailHeight)
      ..close();
    canvas.drawPath(tailPath, Paint()..color = color);

    // ── Icon ──────────────────────────────────────────────
    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(iconData.codePoint),
        style: TextStyle(
          fontSize: iconSize,
          fontFamily: iconData.fontFamily,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    iconPainter.paint(
      canvas,
      Offset(centerX - iconPainter.width / 2, circleY - iconPainter.height / 2),
    );

    // ── Nama lokasi dengan outline ────────────────────────
    final double labelY = circleY + circleRadius + tailHeight + 4;
    final double labelX = centerX - textPainterMeasure.width / 2;

    // Outline hitam 8 arah
    final outlinePainter = TextPainter(
      text: TextSpan(
        text: shortName,
        style: const TextStyle(
          fontSize: 44,
          fontWeight: FontWeight.w700,
          color: Colors.black,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const offsets = [
      Offset(-1, -1),
      Offset(0, -1),
      Offset(1, -1),
      Offset(-1, 0),
      Offset(1, 0),
      Offset(-1, 1),
      Offset(0, 1),
      Offset(1, 1),
    ];
    for (final o in offsets) {
      outlinePainter.paint(canvas, Offset(labelX + o.dx, labelY + o.dy));
    }

    // Teks utama — warna sesuai kategori
    final labelPainter = TextPainter(
      text: TextSpan(
        text: shortName,
        style: TextStyle(
          fontSize: 44,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    labelPainter.paint(canvas, Offset(labelX, labelY));

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      canvasWidth.toInt() + 4,
      canvasHeight.toInt() + 4,
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  Color _getCategoryColor(String? name) {
    switch (name) {
      case 'Museum':
        return const Color(0xFF4CAF50);
      case 'Monumen & Tugu':
        return const Color(0xFF2196F3);
      case 'Bangunan Kolonial':
        return const Color(0xFFFF9800);
      case 'Kawasan Bersejarah':
        return const Color(0xFF9C27B0);
      case 'Tempat Ibadah Bersejarah':
        return const Color(0xFFE91E63);
      default:
        return const Color(0xFF1E3A5F);
    }
  }

  IconData _getCategoryIcon(String? categoryName, String placeName) {
    if (categoryName == 'Tempat Ibadah Bersejarah') {
      final lower = placeName.toLowerCase();
      if (lower.contains('masjid')) return Icons.mosque;
      if (lower.contains('gereja') || lower.contains('church'))
        return Icons.church;
      if (lower.contains('klenteng') || lower.contains('vihara'))
        return Icons.temple_hindu;
      return Icons.place;
    }
    switch (categoryName) {
      case 'Museum':
        return Icons.museum;
      case 'Monumen & Tugu':
        return Icons.account_balance;
      case 'Bangunan Kolonial':
        return Icons.domain;
      case 'Kawasan Bersejarah':
        return Icons.location_city;
      default:
        return Icons.place;
    }
  }

  // ── Kumpulkan foto dari review ────────────────────────────
  List<String> _getReviewPhotos(PlaceModel place) {
    final List<String> photos = [];
    for (final r in place.reviews) {
      if (r.photoUrl != null && r.photoUrl!.isNotEmpty) photos.add(r.photoUrl!);
      if (r.photoUrl2 != null && r.photoUrl2!.isNotEmpty)
        photos.add(r.photoUrl2!);
    }
    return photos;
  }

  // ── Markers ────────────────────────────────────────────────
  Future<void> _buildMarkers() async {
    final places = context.read<PlaceProvider>().allPlaces;
    final markers = <Marker>{};

    for (final place in places) {
      final icon = await _createCustomMarker(
        place.category?.name ?? '',
        place.name,
      );
      markers.add(
        Marker(
          markerId: MarkerId(place.id.toString()),
          position: LatLng(place.lat, place.lng),
          icon: icon,
          anchor: const Offset(0.5, 1.0),
          onTap: () => _onMarkerTapped(place),
        ),
      );
    }
    setState(() => _markers = markers);
  }

  Future<BitmapDescriptor> _createVehicleIcon(String mode) async {
    const double canvasSize = 160.0;
    const double radius = 52.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = Offset(canvasSize / 2, canvasSize / 2);
    const Color blue = Color(0xFF4285F4);

    // Outer glow
    canvas.drawCircle(
      center,
      radius + 14,
      Paint()
        ..color = blue.withOpacity(0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    // Drop shadow
    canvas.drawCircle(
      Offset(center.dx + 1, center.dy + 2),
      radius + 3,
      Paint()
        ..color = Colors.black.withOpacity(0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // White outer ring
    canvas.drawCircle(center, radius + 3, Paint()..color = Colors.white);

    // Blue fill
    canvas.drawCircle(center, radius, Paint()..color = blue);

    // Navigation arrow (white, pointing up)
    final arrowSize = radius * 0.95;
    final arrowPath = Path()
      ..moveTo(center.dx, center.dy - arrowSize * 0.65)
      ..lineTo(center.dx + arrowSize * 0.45, center.dy + arrowSize * 0.5)
      ..lineTo(center.dx, center.dy + arrowSize * 0.2)
      ..lineTo(center.dx - arrowSize * 0.45, center.dy + arrowSize * 0.5)
      ..close();
    canvas.drawPath(arrowPath, Paint()..color = Colors.white);

    final picture = recorder.endRecording();
    final image = await picture.toImage(canvasSize.toInt(), canvasSize.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  void _updateUserVehicleMarker(double lat, double lng, double heading) {
    if (_userVehicleMarker == null) return;
    setState(() {
      _userVehicleMarker = _userVehicleMarker!.copyWith(
        positionParam: LatLng(lat, lng),
        rotationParam: heading,
      );
      _markers = {
        ..._markers.where((m) => m.markerId.value != '__user_vehicle__'),
        _userVehicleMarker!,
      };
    });
  }

  void _onMarkerTapped(PlaceModel place) {
    if (_isNavigating) return;
    setState(() {
      _selectedPlace = place;
      _polylines = {};
      _showBottomSheet = true;
      _showRoutePreview = false;
      _isHoursExpanded = false;
      _isExpanded = false;
      _slidePage = 0;
      _dragOffset = 0;
      _normalSheetHeight = 0;
      _routeSteps = [];
      _routeDistance = 0;
      _routeDuration = 0;
    });
    _mapController?.animateCamera(
      CameraUpdate.newLatLng(LatLng(place.lat - 0.003, place.lng)),
    );
    if (place.reviews.isEmpty) {
      _fetchPlaceDetail(place.id);
    }
  }

  Future<void> _fetchPlaceDetail(int placeId) async {
    final provider = context.read<PlaceProvider>();
    await provider.fetchPlaceDetail(placeId);
    final detailed = provider.selectedPlace;
    if (detailed != null && mounted && _selectedPlace?.id == placeId) {
      setState(() => _selectedPlace = detailed);
    }
  }

  void _closeBottomSheet() {
    setState(() {
      _showBottomSheet = false;
      _showRoutePreview = false;
      _polylines = {};
      _isExpanded = false;
      _bottomSheetHeight = 0;
      _dragOffset = 0;
      _normalSheetHeight = 0;
      _routeSteps = [];
      _routeDistance = 0;
      _routeDuration = 0;
    });
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _selectedPlace = null);
    });
  }

  // ── Routing via OSRM ───────────────────────────────────────
  String _osrmProfile(String mode) {
    switch (mode) {
      case 'walking':
        return 'foot';
      case 'motorcycle':
      case 'driving':
      default:
        return 'car';
    }
  }

  Future<void> _getRoute(PlaceModel destination, {bool showPreview = false, bool isReroute = false}) async {
    if (_userPosition == null) {
      _showSnack('Lokasi kamu belum ditemukan. Tunggu GPS menemukan posisimu.', type: NotifType.warning);
      return;
    }
    setState(() {
      if (!isReroute) {
        _isLoadingRoute = true;
        _polylines = {};
      }
    });
    try {
      final profile = _osrmProfile(_transportMode);
      final url =
          'http://router.project-osrm.org/route/v1/$profile/'
          '${_userPosition!.longitude},${_userPosition!.latitude};'
          '${destination.lng},${destination.lat}'
          '?overview=full&geometries=polyline&steps=true';

      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 'Ok' && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final encoded = route['geometry'] as String;
          final distance = (route['distance'] as num).toDouble();
          final duration = (route['duration'] as num).toDouble();

          final points = PolylinePoints()
              .decodePolyline(encoded)
              .map((p) => LatLng(p.latitude, p.longitude))
              .toList();

          final steps = <Map<String, dynamic>>[];
          final legs = route['legs'] as List;
          for (final leg in legs) {
            for (final step in leg['steps'] as List) {
              final maneuver = step['maneuver'] as Map<String, dynamic>;
              final modifier = maneuver['modifier'] as String? ?? '';
              final type = maneuver['type'] as String? ?? '';
              final name = step['name'] as String? ?? '';
              final stepDist = (step['distance'] as num).toDouble();
              if (type == 'arrive' || type == 'depart' || stepDist < 5) {
                if (type == 'arrive') {
                  steps.add({
                    'type': type,
                    'modifier': modifier,
                    'name': 'Sampai di tujuan',
                    'distance': stepDist,
                  });
                }
                continue;
              }
              steps.add({
                'type': type,
                'modifier': modifier,
                'name': name.isEmpty ? 'Jalan tanpa nama' : name,
                'distance': stepDist,
              });
            }
          }

          final isWalking = _transportMode == 'walking';
          final double actualDuration = isWalking
              ? distance / 1.39
              : duration;
          setState(() {
            _polylines = {
              Polyline(
                polylineId: const PolylineId('route'),
                points: points,
                color: const Color(0xFF1E3A5F),
                width: 5,
                patterns: isWalking
                    ? [PatternItem.dash(20), PatternItem.gap(12)]
                    : [],
              ),
            };
            _routePoints = points;
            _routeDistance = distance;
            _routeDuration = actualDuration;
            _routeSteps = steps;
            _isLoadingRoute = false;
            if (showPreview) {
              _showRoutePreview = true;
              _routeEntryOffset = 1.0;
              _isExpanded = false;
              _dragOffset = 0;
              _normalSheetHeight = 0;
              _overscrollAccum = 0;
            }
          });

          if (showPreview) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _routeEntryOffset = 0.0);
            });
          }

          if (!isReroute && points.isNotEmpty && _mapController != null) {
            double minLat = points
                .map((p) => p.latitude)
                .reduce((a, b) => a < b ? a : b);
            double maxLat = points
                .map((p) => p.latitude)
                .reduce((a, b) => a > b ? a : b);
            double minLng = points
                .map((p) => p.longitude)
                .reduce((a, b) => a < b ? a : b);
            double maxLng = points
                .map((p) => p.longitude)
                .reduce((a, b) => a > b ? a : b);
            _mapController!.animateCamera(
              CameraUpdate.newLatLngBounds(
                LatLngBounds(
                  southwest: LatLng(minLat, minLng),
                  northeast: LatLng(maxLat, maxLng),
                ),
                80,
              ),
            );
          }
        }
      }
    } catch (e) {
      setState(() => _isLoadingRoute = false);
      _showSnack('Gagal mengambil rute. Periksa koneksi internet Anda.', type: NotifType.error);
    }
  }

  void _cancelRoutePreview() {
    _stopNavigation();
    setState(() => _routeEntryOffset = 1.0);
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      setState(() {
        _showRoutePreview = false;
        _polylines = {};
        _routeSteps = [];
        _routePoints = [];
        _routeDistance = 0;
        _routeDuration = 0;
        _normalSheetHeight = 0;
        _isExpanded = false;
        _dragOffset = 0;
        _overscrollAccum = 0;
        _routeEntryOffset = 1.0;
      });
    });
  }

  // ── Live navigation ─────────────────────────────────────────
  Future<void> _startNavigation() async {
    if (_selectedPlace == null || _routeSteps.isEmpty || _userPosition == null) {
      return;
    }

    final vehicleIcon = await _createVehicleIcon(_transportMode);

    setState(() {
      _isNavigating = true;
      _showRoutePreview = false;
      _showBottomSheet = false;
      _isMapCentered = true;
      _currentStepIndex = 0;
      _advanceWarnedStep = -1;
      _remainingDistance = _routeDistance;
      _remainingDuration = _routeDuration;
      _navSheetCtrl.value = 0;

      _userVehicleMarker = Marker(
        markerId: const MarkerId('__user_vehicle__'),
        position: LatLng(_userPosition!.latitude, _userPosition!.longitude),
        icon: vehicleIcon,
        anchor: const Offset(0.5, 0.5),
        flat: true,
        rotation: _userPosition!.heading,
        zIndex: 999,
      );
      _markers = {..._markers, _userVehicleMarker!};
    });

    _navEnterController.forward(from: 0.0);

    if (_routeSteps.isNotEmpty && !_isMuted) {
      final step = _routeSteps[0];
      final text = 'Navigasi dimulai. ${_maneuverText(
        step['type'] as String,
        step['modifier'] as String,
        step['name'] as String,
      )}';
      _flutterTts.speak(text);
    }

    _positionStream?.cancel();
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(_onPositionUpdate);

    if (_mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(
              _userPosition!.latitude,
              _userPosition!.longitude,
            ),
            zoom: 18,
            tilt: 50,
            bearing: _userPosition!.heading,
          ),
        ),
      );
    }
  }

  void _stopNavigation() {
    _positionStream?.cancel();
    _positionStream = null;
    _flutterTts.stop();
    if (!mounted) return;

    _navEnterController.reverse().then((_) {
      if (!mounted) return;
      setState(() {
        _isNavigating = false;
        _isMapCentered = true;
        _currentStepIndex = 0;
        _advanceWarnedStep = -1;
        _showRoutePreview = true;
        _routeEntryOffset = 0.0;
        _isExpanded = false;
        _dragOffset = 0;
        _navSheetCtrl.value = 0;
        _userVehicleMarker = null;
        _markers = _markers.where((m) => m.markerId.value != '__user_vehicle__').toSet();
      });
    });

    if (_mapController != null) {
      final lat = _userPosition?.latitude ?? -7.2575;
      final lng = _userPosition?.longitude ?? 112.7521;
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: LatLng(lat, lng), zoom: 15),
        ),
      );
    }
  }

  void _onPositionUpdate(Position position) {
    if (!mounted || !_isNavigating) return;
    _userPosition = position;

    _updateUserVehicleMarker(
      position.latitude,
      position.longitude,
      position.heading,
    );

    if (_routePoints.isEmpty) return;

    final userLatLng = LatLng(position.latitude, position.longitude);
    final nearestIdx = _findNearestRoutePointIndex(userLatLng);

    double remaining = 0;
    for (int i = nearestIdx; i < _routePoints.length - 1; i++) {
      remaining += _distanceBetween(_routePoints[i], _routePoints[i + 1]);
    }

    final proportion =
        _routeDistance > 0 ? remaining / _routeDistance : 0.0;
    final remainingDur = _routeDuration * proportion;
    final stepIdx = _findCurrentStep(nearestIdx);

    final stepChanged = stepIdx != _currentStepIndex;

    final trimmedPoints = [userLatLng, ..._routePoints.sublist(nearestIdx)];
    final isWalking = _transportMode == 'walking';

    setState(() {
      _remainingDistance = remaining;
      _remainingDuration = remainingDur;
      _currentStepIndex = stepIdx;
      _polylines = {
        Polyline(
          polylineId: const PolylineId('route'),
          points: trimmedPoints,
          color: const Color(0xFF1E3A5F),
          width: 5,
          patterns: isWalking
              ? [PatternItem.dash(20), PatternItem.gap(12)]
              : [],
        ),
      };
    });

    if (stepChanged && stepIdx < _routeSteps.length) {
      _advanceWarnedStep = -1;
      final step = _routeSteps[stepIdx];
      final text = _maneuverText(
        step['type'] as String,
        step['modifier'] as String,
        step['name'] as String,
      );
      if (!_isMuted) {
        _flutterTts.speak(text);
      }
    }

    final nextStepIdx = stepIdx + 1;
    if (nextStepIdx < _routeSteps.length && _advanceWarnedStep != nextStepIdx) {
      final distToNextStep = _distanceToStepManeuver(nearestIdx, nextStepIdx);
      if (distToNextStep <= 200 && distToNextStep > 10) {
        _advanceWarnedStep = nextStepIdx;
        final nextStep = _routeSteps[nextStepIdx];
        final warning = 'Dalam ${distToNextStep.toStringAsFixed(0)} meter, ${_maneuverText(
          nextStep['type'] as String,
          nextStep['modifier'] as String,
          nextStep['name'] as String,
        )}';
        if (!_isMuted) {
          _flutterTts.speak(warning);
        }
      }
    }

    if (_isMapCentered && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(position.latitude, position.longitude),
            zoom: 18,
            tilt: 50,
            bearing: position.heading,
          ),
        ),
      );
    }

    // Check if off-route (>50m)
    final nearestDist =
        _distanceBetween(userLatLng, _routePoints[nearestIdx]);
    if (nearestDist > 50) {
      _rerouteFromCurrentPosition();
    }

    // Check if arrived
    if (_selectedPlace != null) {
      final destDist = _distanceBetween(
        userLatLng,
        LatLng(_selectedPlace!.lat, _selectedPlace!.lng),
      );
      if (destDist < 30) {
        if (!_isMuted) {
          _flutterTts.speak('Kamu telah sampai di tujuan');
        }
        _showSnack('Kamu telah sampai di tujuan!', type: NotifType.success);
        _stopNavigation();
      }
    }
  }

  Future<void> _rerouteFromCurrentPosition() async {
    if (_selectedPlace == null || _userPosition == null) return;
    if (!_isMuted) _flutterTts.speak('Menghitung ulang rute');
    _showSnack('Menghitung ulang rute...', type: NotifType.info);
    await _getRoute(_selectedPlace!, isReroute: true);
    if (mounted) {
      setState(() {
        _remainingDistance = _routeDistance;
        _remainingDuration = _routeDuration;
        _currentStepIndex = 0;
        _advanceWarnedStep = -1;
      });
    }
  }

  int _findNearestRoutePointIndex(LatLng point) {
    if (_routePoints.isEmpty) return 0;
    int nearest = 0;
    double minDist = double.infinity;
    for (int i = 0; i < _routePoints.length; i++) {
      final d = _distanceBetween(point, _routePoints[i]);
      if (d < minDist) {
        minDist = d;
        nearest = i;
      }
    }
    return nearest;
  }

  double _distanceBetween(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = _toRad(b.latitude - a.latitude);
    final dLng = _toRad(b.longitude - a.longitude);
    final sinLat = math.sin(dLat / 2);
    final sinLng = math.sin(dLng / 2);
    final h = sinLat * sinLat +
        math.cos(_toRad(a.latitude)) *
            math.cos(_toRad(b.latitude)) *
            sinLng *
            sinLng;
    return r * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  double _toRad(double deg) => deg * math.pi / 180;

  int _findCurrentStep(int nearestRoutePointIdx) {
    double distFromStart = 0;
    for (int i = 0;
        i < nearestRoutePointIdx && i < _routePoints.length - 1;
        i++) {
      distFromStart +=
          _distanceBetween(_routePoints[i], _routePoints[i + 1]);
    }
    double cumulative = 0;
    for (int i = 0; i < _routeSteps.length; i++) {
      cumulative += (_routeSteps[i]['distance'] as double);
      if (cumulative > distFromStart) return i;
    }
    return _routeSteps.length - 1;
  }

  double _distanceToStepManeuver(int nearestRoutePointIdx, int targetStepIdx) {
    double cumStepDist = 0;
    for (int i = 0; i < targetStepIdx && i < _routeSteps.length; i++) {
      cumStepDist += (_routeSteps[i]['distance'] as double);
    }
    double distFromStart = 0;
    for (int i = 0;
        i < nearestRoutePointIdx && i < _routePoints.length - 1;
        i++) {
      distFromStart +=
          _distanceBetween(_routePoints[i], _routePoints[i + 1]);
    }
    return (cumStepDist - distFromStart).clamp(0, double.infinity);
  }

  void _recenterMap() {
    if (_userPosition == null || _mapController == null) return;
    setState(() => _isMapCentered = true);
    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(
            _userPosition!.latitude,
            _userPosition!.longitude,
          ),
          zoom: 18,
          tilt: 50,
          bearing: _userPosition!.heading,
        ),
      ),
    );
  }

  void _showRouteOverview() {
    if (_routePoints.isEmpty || _mapController == null) return;
    setState(() => _isMapCentered = false);
    double minLat =
        _routePoints.map((p) => p.latitude).reduce(math.min);
    double maxLat =
        _routePoints.map((p) => p.latitude).reduce(math.max);
    double minLng =
        _routePoints.map((p) => p.longitude).reduce(math.min);
    double maxLng =
        _routePoints.map((p) => p.longitude).reduce(math.max);
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        80,
      ),
    );
  }

  IconData _maneuverIcon(String type, String modifier) {
    if (type == 'arrive') return Icons.flag;
    if (type == 'roundabout' || type == 'rotary') return Icons.rotate_right;
    switch (modifier) {
      case 'left':
        return Icons.turn_left;
      case 'right':
        return Icons.turn_right;
      case 'slight left':
        return Icons.turn_slight_left;
      case 'slight right':
        return Icons.turn_slight_right;
      case 'sharp left':
        return Icons.turn_sharp_left;
      case 'sharp right':
        return Icons.turn_sharp_right;
      case 'uturn':
        return Icons.u_turn_left;
      case 'straight':
        return Icons.straight;
      default:
        return Icons.straight;
    }
  }

  String _maneuverText(String type, String modifier, String name) {
    if (type == 'arrive') return name;
    String action;
    switch (modifier) {
      case 'left':
        action = 'Belok kiri';
        break;
      case 'right':
        action = 'Belok kanan';
        break;
      case 'slight left':
        action = 'Serong kiri';
        break;
      case 'slight right':
        action = 'Serong kanan';
        break;
      case 'sharp left':
        action = 'Belok tajam kiri';
        break;
      case 'sharp right':
        action = 'Belok tajam kanan';
        break;
      case 'uturn':
        action = 'Putar balik';
        break;
      case 'straight':
        action = 'Lurus';
        break;
      default:
        action = 'Lanjutkan';
    }
    if (type == 'roundabout' || type == 'rotary') {
      action = 'Bundaran, keluar ke $modifier';
    }
    return '$action ke $name';
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  String _formatDuration(double seconds) {
    final min = (seconds / 60).round();
    if (min < 60) return '$min mnt';
    final h = min ~/ 60;
    final m = min % 60;
    return '$h jam ${m > 0 ? '$m mnt' : ''}';
  }

  // ── Fit all markers ────────────────────────────────────────
  void _fitAllMarkers() {
    if (_markers.isEmpty || _mapController == null) return;
    double minLat = 90, maxLat = -90;
    double minLng = 180, maxLng = -180;
    for (final m in _markers) {
      if (m.position.latitude < minLat) minLat = m.position.latitude;
      if (m.position.latitude > maxLat) maxLat = m.position.latitude;
      if (m.position.longitude < minLng) minLng = m.position.longitude;
      if (m.position.longitude > maxLng) maxLng = m.position.longitude;
    }
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        60,
      ),
    );
  }

  void _showSnack(String message, {NotifType type = NotifType.info}) {
    if (!mounted) return;
    AppNotification.show(context, message: message, type: type);
  }

  // ── Jam buka hari ini ──────────────────────────────────────
  String _getTodayHours(List<String> hours) {
    if (hours.isEmpty) return 'Jam buka tidak tersedia';
    final days = [
      'Senin',
      'Selasa',
      'Rabu',
      'Kamis',
      'Jumat',
      'Sabtu',
      'Minggu',
    ];
    final today = days[DateTime.now().weekday - 1];
    for (final h in hours) {
      if (h.toLowerCase().contains(today.toLowerCase())) return h;
    }
    return hours.first;
  }

  bool _isOpenNow(List<String> hours) {
    if (hours.isEmpty) return false;
    final todayHours = _getTodayHours(hours);
    final timeRegex = RegExp(
      r'(\d{1,2})[.:](\d{2})\s*[-–]\s*(\d{1,2})[.:](\d{2})',
    );
    final match = timeRegex.firstMatch(todayHours);
    if (match == null) return false;
    final now = TimeOfDay.now();
    final openH = int.parse(match.group(1)!);
    final openM = int.parse(match.group(2)!);
    final closeH = int.parse(match.group(3)!);
    final closeM = int.parse(match.group(4)!);
    final nowMinutes = now.hour * 60 + now.minute;
    final openMin = openH * 60 + openM;
    final closeMin = closeH * 60 + closeM;
    return nowMinutes >= openMin && nowMinutes <= closeMin;
  }

  void _checkPendingRoute() {
    final provider = context.read<PlaceProvider>();
    final pending = provider.consumePendingRoute();
    if (pending != null) {
      _onMarkerTapped(pending);
      _getRoute(pending, showPreview: true);
    }
  }

  void _checkPendingView() {
    final provider = context.read<PlaceProvider>();
    final pending = provider.consumePendingView();
    if (pending != null) {
      _onMarkerTapped(pending);
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(pending.lat - 0.002, pending.lng),
          16,
        ),
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlaceProvider>();
    if (provider.pendingRoutePlace != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _checkPendingRoute();
      });
    } else if (provider.pendingViewPlace != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _checkPendingView();
      });
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Peta Lokasi'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              _buildMarkers();
              _fitAllMarkers();
            },
            tooltip: 'Tampilkan Semua Lokasi',
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, bodyConstraints) {
        return Stack(
        children: [
          // ── Google Map ──────────────────────────────────────
          GoogleMap(
            initialCameraPosition: _surabayaCenter,
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: !_isNavigating,
            myLocationButtonEnabled: false,
            mapType: MapType.normal,
            zoomControlsEnabled: false,
            onMapCreated: (controller) {
              _mapController = controller;
              _buildMarkers();
              if (_userPosition != null) {
                controller.animateCamera(
                  CameraUpdate.newLatLngZoom(
                    LatLng(_userPosition!.latitude, _userPosition!.longitude),
                    15,
                  ),
                );
              }
            },
            onTap: (_) {
              if (_isNavigating) {
                setState(() => _isMapCentered = false);
              } else {
                _closeBottomSheet();
              }
            },
          ),

          // ── Loading lokasi ──────────────────────────────────
          if (_isLoadingLocation)
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Mencari lokasi kamu...'),
                    ],
                  ),
                ),
              ),
            ),

          // ── Loading rute ────────────────────────────────────
          if (_isLoadingRoute)
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E3A5F),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Menghitung rute...',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Tombol lokasi user ──────────────────────────────
          Builder(
            builder: (context) {
              if (_isNavigating) return const SizedBox.shrink();
              if ((_showBottomSheet || _showRoutePreview) && _isExpanded) {
                return const SizedBox.shrink();
              }

              double targetBottom;
              if (!_showBottomSheet && !_showRoutePreview) {
                targetBottom = 30;
              } else {
                final base = _normalSheetHeight > 0
                    ? _normalSheetHeight
                    : bodyConstraints.maxHeight * 0.6;
                final dragPixels = _dragOffset * base;
                targetBottom = base + 16 - dragPixels;
                if (targetBottom < 30) targetBottom = 30;
              }
              return AnimatedPositioned(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOut,
                bottom: targetBottom,
                right: 16,
                child: FloatingActionButton(
                  heroTag: 'myLocation',
                  mini: true,
                  backgroundColor: Colors.white,
                  onPressed: _getUserLocation,
                  child: const Icon(
                    Icons.my_location,
                    color: Color(0xFF1E3A5F),
                  ),
                ),
              );
            },
          ),

          // ── Tombol mulai navigasi (floating, saat route normal) ─
          if (_showRoutePreview && _selectedPlace != null)
            Builder(
              builder: (context) {
                final base = _normalSheetHeight > 0
                    ? _normalSheetHeight
                    : bodyConstraints.maxHeight * 0.6;
                final dragPixels = _dragOffset * base;
                double targetBottom = base + 16 - dragPixels;
                if (targetBottom < 30) targetBottom = 30;
                final bool showMulai =
                    !_isExpanded && _routeEntryOffset < 0.5;
                return AnimatedPositioned(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOut,
                  bottom: targetBottom,
                  left: 16,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: showMulai ? 1.0 : 0.0,
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 300),
                      scale: showMulai ? 1.0 : 0.0,
                      child: IgnorePointer(
                        ignoring: !showMulai,
                        child: FloatingActionButton.extended(
                          heroTag: 'startNavigation',
                          backgroundColor: const Color(0xFF1E3A5F),
                          elevation: 4,
                          onPressed: _startNavigation,
                          icon: const Icon(
                            Icons.navigation,
                            size: 18,
                            color: Colors.white,
                          ),
                          label: const Text(
                            'Mulai',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

          // ── Legend ──────────────────────────────────────────
          if (!_showBottomSheet && !_isNavigating)
            Positioned(
              bottom: 30,
              left: 16,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _LegendItem(
                      color: const Color(0xFF4CAF50),
                      label: 'Museum',
                      icon: Icons.museum,
                    ),
                    _LegendItem(
                      color: const Color(0xFF2196F3),
                      label: 'Monumen & Tugu',
                      icon: Icons.account_balance,
                    ),
                    _LegendItem(
                      color: const Color(0xFFFF9800),
                      label: 'Bangunan Kolonial',
                      icon: Icons.domain,
                    ),
                    _LegendItem(
                      color: const Color(0xFF9C27B0),
                      label: 'Kawasan Bersejarah',
                      icon: Icons.location_city,
                    ),
                    _LegendItem(
                      color: const Color(0xFFE91E63),
                      label: 'Tempat Ibadah:',
                      icon: Icons.place,
                      isIbadah: true,
                    ),
                  ],
                ),
              ),
            ),

          // ── Route preview bottom sheet ─────────────────────
          if (_showRoutePreview && _selectedPlace != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                offset: Offset(0, _routeEntryOffset),
                child: FractionalTranslation(
                  translation: Offset(0, _dragOffset),
                  child: _buildRoutePreviewSheet(
                    _selectedPlace!,
                    bodyConstraints.maxHeight,
                  ),
                ),
              ),
            ),

          // ── Bottom sheet dengan animasi slide ───────────────
          if (_showBottomSheet && _selectedPlace != null && !_showRoutePreview)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                offset: Offset(0, _dragOffset),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (details) {
                    setState(() {
                      _dragOffset = (_dragOffset + details.delta.dy / 300)
                          .clamp(0.0, 1.0);
                    });
                  },
                  onVerticalDragEnd: (details) {
                    final velocity = details.primaryVelocity ?? 0;
                    if (velocity < -300 && !_isExpanded) {
                      setState(() {
                        _isExpanded = true;
                        _dragOffset = 0;
                      });
                    } else if (velocity > 300) {
                      if (_isExpanded) {
                        setState(() {
                          _isExpanded = false;
                          _dragOffset = 0;
                          if (_normalSheetHeight > 0) {
                            _bottomSheetHeight = _normalSheetHeight;
                          }
                        });
                        Future.delayed(const Duration(milliseconds: 400), () {
                          if (mounted) setState(() {});
                        });
                      } else if (_dragOffset > 0.15) {
                        _closeBottomSheet();
                      } else {
                        setState(() => _dragOffset = 0);
                      }
                    } else {
                      if (_dragOffset > 0.3) {
                        _closeBottomSheet();
                      } else {
                        setState(() => _dragOffset = 0);
                      }
                    }
                  },
                  child: _buildBottomSheet(_selectedPlace!, bodyConstraints.maxHeight),
                ),
              ),
            ),

          // ── Navigation mode UI ─────────────────────────────
          if (_isNavigating && _selectedPlace != null) ...[
            // Tap outside to close expanded nav bottom sheet
            if (_navSheetCtrl.value > 0.1)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => _navSheetCtrl.reverse(),
                  behavior: HitTestBehavior.translucent,
                  child: const SizedBox.expand(),
                ),
              ),

            // Header: maneuver instruction
            Positioned(
              top: MediaQuery.of(context).padding.top + 4,
              left: 12,
              right: 12,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -1.5),
                  end: Offset.zero,
                ).animate(_navFadeIn),
                child: FadeTransition(
                  opacity: _navFadeIn,
                  child: _buildNavigationHeader(),
                ),
              ),
            ),

            // Floating buttons (right side)
            Positioned(
              right: 12,
              bottom: 110,
              child: FadeTransition(
                opacity: _navFadeIn,
                child: ScaleTransition(
                  scale: _navFadeIn,
                  alignment: Alignment.centerRight,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Sound toggle
                      _NavFloatingButton(
                        icon: _isMuted
                            ? Icons.volume_off
                            : Icons.volume_up,
                        iconColor: _isMuted ? Colors.red : null,
                        onTap: () {
                          setState(() => _isMuted = !_isMuted);
                          if (_isMuted) _flutterTts.stop();
                        },
                      ),
                      const SizedBox(height: 10),
                      // Recenter
                      _NavFloatingButton(
                        icon: Icons.my_location,
                        onTap: _recenterMap,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom bar
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 1.0),
                  end: Offset.zero,
                ).animate(_navFadeIn),
                child: _buildNavigationBottom(bodyConstraints.maxHeight),
              ),
            ),
          ],
        ],
        );
        },
      ),
    );
  }

  // ── Bottom Sheet Content ───────────────────────────────────
  Widget _buildBottomSheet(PlaceModel place, double bodyHeight) {
    final isOpen = _isOpenNow(place.openingHours);
    final todayHours = _getTodayHours(place.openingHours);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
      ),
      constraints: BoxConstraints(
        maxHeight: bodyHeight - 8,
      ),
      child: _MeasuredColumn(
        key: ValueKey(_selectedPlace?.id ?? 0),
        onHeightChanged: (h) {
          if (!mounted) return;
          final hUpdate = (h - _bottomSheetHeight).abs() > 1;
          final nUpdate = !_isExpanded && h > 0 && (h - _normalSheetHeight).abs() > 1;
          if (!hUpdate && !nUpdate) return;
          setState(() {
            _bottomSheetHeight = h;
            if (!_isExpanded && h > 0) _normalSheetHeight = h;
          });
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Handle bar ──────────────────────────
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // ── Scrollable content ──────────────────
            Flexible(
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (!_isExpanded) return false;
                  if (notification is ScrollUpdateNotification) {
                    if (notification.metrics.pixels <= 0 &&
                        (notification.dragDetails?.delta.dy ?? 0) > 0) {
                      _overscrollAccum += notification.dragDetails!.delta.dy;
                      if (_overscrollAccum > 60) {
                        _overscrollAccum = 0;
                        setState(() {
                          _isExpanded = false;
                          _dragOffset = 0;
                          if (_normalSheetHeight > 0) {
                            _bottomSheetHeight = _normalSheetHeight;
                          }
                        });
                        Future.delayed(const Duration(milliseconds: 400), () {
                          if (mounted) setState(() {});
                        });
                        return true;
                      }
                    } else {
                      _overscrollAccum = 0;
                    }
                  } else if (notification is ScrollEndNotification) {
                    _overscrollAccum = 0;
                  }
                  return false;
                },
                child: SingleChildScrollView(
                  physics: _isExpanded
                      ? const BouncingScrollPhysics()
                      : const NeverScrollableScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
              // ── Foto: animasi crossfade kecil ↔ besar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: AnimatedCrossFade(
                  duration: const Duration(milliseconds: 350),
                  firstCurve: Curves.easeInOut,
                  secondCurve: Curves.easeInOut,
                  sizeCurve: Curves.easeInOut,
                  crossFadeState: _isExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: IgnorePointer(
                    ignoring: _isExpanded,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: place.photos.isNotEmpty
                              ? Image.network(
                                  place.photos[0],
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 80,
                                    height: 80,
                                    color: _getCategoryColor(
                                      place.category?.name,
                                    ).withOpacity(0.1),
                                    child: Center(
                                      child: Icon(
                                        _getCategoryIcon(
                                          place.category?.name ?? '',
                                          place.name,
                                        ),
                                        size: 32,
                                        color: _getCategoryColor(
                                          place.category?.name,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              : Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    color: _getCategoryColor(
                                      place.category?.name,
                                    ).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Center(
                                    child: Icon(
                                      _getCategoryIcon(
                                        place.category?.name ?? '',
                                        place.name,
                                      ),
                                      size: 32,
                                      color: _getCategoryColor(
                                        place.category?.name,
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: _buildNameSection(place)),
                      ],
                    ),
                  ),
                  secondChild: IgnorePointer(
                    ignoring: !_isExpanded,
                    child: StatefulBuilder(
                    builder: (_, setSlideState) {
                      final reviewPhotos = _getReviewPhotos(place);
                      final allPhotos = <String>[
                        ...place.photos,
                        ...reviewPhotos,
                      ];
                      final reviewCount = reviewPhotos.length;

                      if (allPhotos.isEmpty) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                height: 180,
                                width: double.infinity,
                                color: _getCategoryColor(
                                  place.category?.name,
                                ).withOpacity(0.1),
                                child: Center(
                                  child: Icon(
                                    _getCategoryIcon(
                                      place.category?.name ?? '',
                                      place.name,
                                    ),
                                    size: 60,
                                    color: _getCategoryColor(
                                      place.category?.name,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildNameSection(place),
                          ],
                        );
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Foto slideshow
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              height: 180,
                              child: Stack(
                                children: [
                                  // Foto utama dengan PageView (sama seperti di halaman detail)
                                  PageView.builder(
                                    controller: _slideController,
                                    itemCount: allPhotos.length,
                                    onPageChanged: (i) {
                                      setSlideState(() => _slidePage = i);
                                      setState(() {});
                                    },
                                    itemBuilder: (_, i) => Image.network(
                                      allPhotos[i],
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        color: _getCategoryColor(
                                          place.category?.name,
                                        ).withOpacity(0.1),
                                        child: Center(
                                          child: Icon(
                                            _getCategoryIcon(
                                              place.category?.name ?? '',
                                              place.name,
                                            ),
                                            size: 60,
                                            color: _getCategoryColor(
                                              place.category?.name,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Badge "+N dari ulasan"
                                  if (reviewCount > 0)
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.photo_library,
                                              size: 12,
                                              color: Colors.white,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '+$reviewCount dari ulasan',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  // Indikator dots + counter
                                  if (allPhotos.length > 1)
                                    Positioned(
                                      bottom: 8,
                                      left: 0,
                                      right: 0,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.black45,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                ...List.generate(
                                                  allPhotos.length,
                                                  (i) => AnimatedContainer(
                                                    duration: const Duration(
                                                      milliseconds: 200,
                                                    ),
                                                    margin:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 3,
                                                        ),
                                                    width: _slidePage == i
                                                        ? 16
                                                        : 8,
                                                    height: 8,
                                                    decoration: BoxDecoration(
                                                      color: _slidePage == i
                                                          ? Colors.white
                                                          : Colors.white54,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            4,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  '${_slidePage + 1}/${allPhotos.length}',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildNameSection(place),
                        ],
                      );
                    },
                  ),
                  ),
                ),
              ),

              // ── Detail info ─────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 14,
                          color: Colors.red,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            place.address,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (place.phone.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.phone,
                            size: 14,
                            color: Colors.green,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            place.phone,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (place.website.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.language,
                            size: 14,
                            color: Colors.blue,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              place.website,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.blue,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (place.openingHours.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () => setState(
                          () => _isHoursExpanded = !_isHoursExpanded,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.access_time,
                                    size: 14,
                                    color: isOpen ? Colors.green : Colors.red,
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isOpen
                                          ? Colors.green.withOpacity(0.1)
                                          : Colors.red.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      isOpen ? 'Buka' : 'Tutup',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isOpen
                                            ? Colors.green
                                            : Colors.red,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      todayHours,
                                      style: const TextStyle(fontSize: 12),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Icon(
                                    _isHoursExpanded
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                    size: 16,
                                    color: Colors.grey,
                                  ),
                                ],
                              ),
                              if (_isHoursExpanded) ...[
                                const SizedBox(height: 8),
                                const Divider(height: 1),
                                const SizedBox(height: 8),
                                ...place.openingHours.map(
                                  (h) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 2,
                                    ),
                                    child: Row(
                                      children: [
                                        const SizedBox(width: 20),
                                        Text(
                                          h,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: _isLoadingRoute
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.directions, size: 18),
                            label: Text(
                              _isLoadingRoute
                                  ? 'Menghitung...'
                                  : 'Tampilkan Rute',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E3A5F),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: _isLoadingRoute
                                ? null
                                : () => _getRoute(place, showPreview: true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.info_outline, size: 18),
                            label: const Text('Lihat Detail'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF1E3A5F),
                              side: const BorderSide(color: Color(0xFF1E3A5F)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DetailScreen(placeId: place.id),
                              ),
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
      ),
          ],
        ),
      ),
    );
  }

  // ── Route Preview Sheet ─────────────────────────────────────
  Widget _buildRoutePreviewSheet(PlaceModel place, double bodyHeight) {
    final double normalMaxHeight = bodyHeight * 0.6;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
      ),
      constraints: BoxConstraints(
        maxHeight: _isExpanded ? bodyHeight - 8 : normalMaxHeight,
      ),
      child: _MeasuredColumn(
        key: ValueKey('route_${_selectedPlace?.id ?? 0}_$_transportMode'),
        onHeightChanged: (h) {
          if (!mounted) return;
          final hUpdate = (h - _bottomSheetHeight).abs() > 1;
          final nUpdate = !_isExpanded && h > 0 && (h - _normalSheetHeight).abs() > 1;
          if (!hUpdate && !nUpdate) return;
          setState(() {
            _bottomSheetHeight = h;
            if (!_isExpanded && h > 0) _normalSheetHeight = h;
          });
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Draggable header: nama + kendaraan ──
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (details) {
                setState(() {
                  _dragOffset = (_dragOffset + details.delta.dy / 300)
                      .clamp(0.0, 1.0);
                });
              },
              onVerticalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0;
                if (velocity < -300 && !_isExpanded) {
                  setState(() {
                    _isExpanded = true;
                    _dragOffset = 0;
                  });
                } else if (velocity > 300) {
                  if (_isExpanded) {
                    setState(() {
                      _isExpanded = false;
                      _dragOffset = 0;
                      if (_normalSheetHeight > 0) {
                        _bottomSheetHeight = _normalSheetHeight;
                      }
                    });
                    Future.delayed(const Duration(milliseconds: 400), () {
                      if (mounted) setState(() {});
                    });
                  } else if (_dragOffset > 0.15) {
                    _cancelRoutePreview();
                  } else {
                    setState(() => _dragOffset = 0);
                  }
                } else {
                  if (_dragOffset > 0.3) {
                    _cancelRoutePreview();
                  } else {
                    setState(() => _dragOffset = 0);
                  }
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // Nama tujuan + tombol batalkan kecil (animated)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.flag,
                          size: 18,
                          color: Color(0xFF1E3A5F),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            place.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E3A5F),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 250),
                          opacity: _isExpanded ? 0.0 : 1.0,
                          child: AnimatedScale(
                            duration: const Duration(milliseconds: 250),
                            scale: _isExpanded ? 0.0 : 1.0,
                            child: IgnorePointer(
                              ignoring: _isExpanded,
                              child: SizedBox(
                                width: 32,
                                height: 32,
                                child: Material(
                                  color: Colors.red.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: _cancelRoutePreview,
                                    child: const Icon(
                                      Icons.close,
                                      size: 16,
                                      color: Colors.red,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Transport mode selector
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        _TransportChip(
                          icon: Icons.directions_walk,
                          label: 'Jalan Kaki',
                          isSelected: _transportMode == 'walking',
                          onTap: () {
                            setState(() => _transportMode = 'walking');
                            _getRoute(place, showPreview: true);
                          },
                        ),
                        const SizedBox(width: 8),
                        _TransportChip(
                          icon: Icons.two_wheeler,
                          label: 'Motor',
                          isSelected: _transportMode == 'motorcycle',
                          onTap: () {
                            setState(() => _transportMode = 'motorcycle');
                            _getRoute(place, showPreview: true);
                          },
                        ),
                        const SizedBox(width: 8),
                        _TransportChip(
                          icon: Icons.directions_car,
                          label: 'Mobil',
                          isSelected: _transportMode == 'driving',
                          onTap: () {
                            setState(() => _transportMode = 'driving');
                            _getRoute(place, showPreview: true);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            // ── Konten: beda layout antara normal vs expanded ──
            if (_isExpanded) ...[
              // Expanded: ETA + label fixed, hanya steps yang scroll
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildEtaCard(),
              ),
              if (_routeSteps.isNotEmpty)
                const SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Text(
                      'Panduan Rute',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E3A5F),
                      ),
                    ),
                  ),
                ),
              if (_routeSteps.isNotEmpty)
                Flexible(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification is ScrollUpdateNotification) {
                        if (notification.metrics.pixels <= 0 &&
                            (notification.dragDetails?.delta.dy ?? 0) > 0) {
                          _overscrollAccum +=
                              notification.dragDetails!.delta.dy;
                          if (_overscrollAccum > 60) {
                            _overscrollAccum = 0;
                            setState(() {
                              _isExpanded = false;
                              _dragOffset = 0;
                              if (_normalSheetHeight > 0) {
                                _bottomSheetHeight = _normalSheetHeight;
                              }
                            });
                            Future.delayed(const Duration(milliseconds: 400), () {
                              if (mounted) setState(() {});
                            });
                            return true;
                          }
                        } else {
                          _overscrollAccum = 0;
                        }
                      } else if (notification is ScrollEndNotification) {
                        _overscrollAccum = 0;
                      }
                      return false;
                    },
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      physics: const BouncingScrollPhysics(),
                      itemCount: _routeSteps.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: Colors.grey.shade200,
                      ),
                      itemBuilder: (_, i) => _buildStepItem(_routeSteps[i]),
                    ),
                  ),
                ),
            ] else ...[
              // Normal: semua konten scrollable
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildEtaCard(),
                      if (_routeSteps.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Panduan Rute',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E3A5F),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: EdgeInsets.zero,
                          itemCount: _routeSteps.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            color: Colors.grey.shade200,
                          ),
                          itemBuilder: (_, i) =>
                              _buildStepItem(_routeSteps[i]),
                        ),
                      ],
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ],
            // ── Tombol aksi expanded (animated) ──
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              child: _isExpanded
                  ? AnimatedOpacity(
                      duration: const Duration(milliseconds: 250),
                      opacity: _isExpanded ? 1.0 : 0.0,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.navigation, size: 18),
                                label: const Text('Mulai'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1E3A5F),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: _startNavigation,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.close, size: 18),
                                label: const Text('Batalkan'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: _cancelRoutePreview,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : const SizedBox(width: double.infinity, height: 0),
            ),
          ],
        ),
      ),
    );
  }

  // ── ETA card (reusable) ────────────────────────────────────
  Widget _buildEtaCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E3A5F).withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Row(
            children: [
              const Icon(
                Icons.schedule,
                size: 18,
                color: Color(0xFF1E3A5F),
              ),
              const SizedBox(width: 6),
              Text(
                _formatDuration(_routeDuration),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E3A5F),
                ),
              ),
            ],
          ),
          Container(width: 1, height: 24, color: Colors.grey.shade300),
          Row(
            children: [
              const Icon(
                Icons.straighten,
                size: 18,
                color: Color(0xFF1E3A5F),
              ),
              const SizedBox(width: 6),
              Text(
                _formatDistance(_routeDistance),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E3A5F),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Step item (reusable) ───────────────────────────────────
  Widget _buildStepItem(Map<String, dynamic> step) {
    final type = step['type'] as String;
    final modifier = step['modifier'] as String;
    final name = step['name'] as String;
    final dist = step['distance'] as double;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: type == 'arrive'
                  ? Colors.green.withOpacity(0.1)
                  : const Color(0xFF1E3A5F).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _maneuverIcon(type, modifier),
              size: 20,
              color: type == 'arrive' ? Colors.green : const Color(0xFF1E3A5F),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _maneuverText(type, modifier, name),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (dist > 0 && type != 'arrive')
                  Text(
                    _formatDistance(dist),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Navigation header (maneuver bar) ────────────────────────
  Widget _buildNavigationHeader() {
    if (_routeSteps.isEmpty) return const SizedBox.shrink();
    final idx = _currentStepIndex.clamp(0, _routeSteps.length - 1);
    final step = _routeSteps[idx];
    final type = step['type'] as String;
    final modifier = step['modifier'] as String;
    final name = step['name'] as String;
    final dist = step['distance'] as double;

    final hasNext = idx + 1 < _routeSteps.length;
    final nextStep = hasNext ? _routeSteps[idx + 1] : null;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.2),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: Column(
        key: ValueKey(idx),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF0D6B58),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  _maneuverIcon(type, modifier),
                  color: Colors.white,
                  size: 36,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (dist > 0 && type != 'arrive')
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            _formatDistance(dist),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.75),
                              fontSize: 13,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Next step preview ("Lalu ↩")
          if (hasNext && nextStep != null)
            Container(
              margin: const EdgeInsets.only(left: 8, top: 4),
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF3C4043),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Lalu',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Icon(
                    _maneuverIcon(
                      nextStep['type'] as String,
                      nextStep['modifier'] as String,
                    ),
                    color: Colors.white,
                    size: 16,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Navigation bottom bar ──────────────────────────────────
  Widget _buildNavigationBottom(double maxHeight) {
    final eta = DateTime.now().add(
      Duration(seconds: _remainingDuration.round()),
    );
    final etaStr =
        '${eta.hour.toString().padLeft(2, '0')}.${eta.minute.toString().padLeft(2, '0')}';

    final double expandedMax = maxHeight * 0.6;
    final double stepsMaxHeight = expandedMax - 130;

    final double val = _navSheetCtrl.value;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -300 && _navSheetCtrl.value < 0.5) {
          _navSheetCtrl.forward();
        } else if (velocity > 300 && _navSheetCtrl.value > 0.5) {
          _navSheetCtrl.reverse();
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () {
                if (_navSheetCtrl.value > 0.5) {
                  _navSheetCtrl.reverse();
                } else {
                  _navSheetCtrl.forward();
                }
              },
              behavior: HitTestBehavior.opaque,
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatDuration(_remainingDuration),
                          style: const TextStyle(
                            color: Color(0xFF1B873B),
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_formatDistance(_remainingDistance)} · $etaStr',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.alt_route),
                      color: const Color(0xFF3C4043),
                      iconSize: 22,
                      onPressed: _showRouteOverview,
                      tooltip: 'Lihat rute',
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD93025),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    onPressed: _stopNavigation,
                    child: const Text(
                      'Keluar',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_routeSteps.isNotEmpty && val > 0)
              ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: val,
                  child: Opacity(
                    opacity: val,
                    child: SizedBox(
                      height: stepsMaxHeight,
                      child: Column(
                        children: [
                          Divider(height: 1, color: Colors.grey.shade300),
                          Padding(
                            padding:
                                const EdgeInsets.fromLTRB(16, 10, 16, 6),
                            child: Row(
                              children: [
                                const Text(
                                  'Panduan Rute',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1E3A5F),
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${_currentStepIndex + 1} / ${_routeSteps.length}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.separated(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              physics: const BouncingScrollPhysics(),
                              itemCount: _routeSteps.length,
                              separatorBuilder: (_, __) => Divider(
                                height: 1,
                                color: Colors.grey.shade200,
                              ),
                              itemBuilder: (_, i) {
                                final isCurrent = i == _currentStepIndex;
                                final isPast = i < _currentStepIndex;
                                return Opacity(
                                  opacity: isPast ? 0.4 : 1.0,
                                  child: Container(
                                    decoration: isCurrent
                                        ? BoxDecoration(
                                            color: const Color(0xFF0D6B58)
                                                .withOpacity(0.08),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          )
                                        : null,
                                    padding: isCurrent
                                        ? const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2)
                                        : EdgeInsets.zero,
                                    child:
                                        _buildStepItem(_routeSteps[i]),
                                  ),
                                );
                              },
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
    );
  }


  // ── Helper: nama + kategori + rating ────────────────────────
  Widget _buildNameSection(PlaceModel place) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          place.name,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E3A5F),
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (place.category != null) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _getCategoryColor(place.category!.name).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _getCategoryIcon(place.category!.name, place.name),
                  size: 12,
                  color: _getCategoryColor(place.category!.name),
                ),
                const SizedBox(width: 4),
                Text(
                  place.category!.name,
                  style: TextStyle(
                    fontSize: 11,
                    color: _getCategoryColor(place.category!.name),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 6),
        Row(
          children: [
            const Icon(Icons.star, size: 14, color: Colors.amber),
            const SizedBox(width: 4),
            Text(
              '${place.avgRating.toStringAsFixed(1)} (${place.reviewCount})',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(width: 10),
            Consumer<PlaceProvider>(
              builder: (_, pp, __) {
                final dist = pp.distanceTo(place.lat, place.lng);
                if (dist == null) return const SizedBox.shrink();
                return Row(
                  children: [
                    const Icon(
                      Icons.directions_walk,
                      size: 14,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      dist < 1000
                          ? '${dist.toStringAsFixed(0)} m'
                          : '${(dist / 1000).toStringAsFixed(1)} km',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}

// ── Legend Item ─────────────────────────────────────────────
class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final IconData icon;
  final bool isIbadah;

  const _LegendItem({
    required this.color,
    required this.label,
    required this.icon,
    this.isIbadah = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(icon, size: 13, color: Colors.white),
              ),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontSize: 11)),
            ],
          ),
          if (isIbadah) ...[
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                SizedBox(width: 28),
                Icon(Icons.mosque, size: 13, color: Colors.black54),
                SizedBox(width: 6),
                Icon(Icons.church, size: 13, color: Colors.black54),
                SizedBox(width: 6),
                Icon(Icons.temple_hindu, size: 13, color: Colors.black54),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MeasuredColumn extends StatefulWidget {
  final Widget child;
  final void Function(double) onHeightChanged;

  const _MeasuredColumn({
    super.key,
    required this.child,
    required this.onHeightChanged,
  });
  @override
  State<_MeasuredColumn> createState() => _MeasuredColumnState();
}

class _MeasuredColumnState extends State<_MeasuredColumn> {
  final GlobalKey _key = GlobalKey();
  double _lastHeight = 0;

  @override
  void initState() {
    super.initState();
    _lastHeight = 0; // reset saat recreate karena key berubah
  }

  void _measure() {
    final ctx = _key.currentContext;
    if (ctx != null) {
      final box = ctx.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        final h = box.size.height;
        if ((h - _lastHeight).abs() > 0.5) {
          _lastHeight = h;
          widget.onHeightChanged(h);
        }
      }
    }
  }

  @override
  void didUpdateWidget(covariant _MeasuredColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return Container(key: _key, child: widget.child);
  }
}

class _NavFloatingButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? iconColor;

  const _NavFloatingButton({
    required this.icon,
    required this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: iconColor ?? const Color(0xFF3C4043), size: 22),
      ),
    );
  }
}

class _TransportChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TransportChip({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF1E3A5F) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? const Color(0xFF1E3A5F) : Colors.grey.shade300,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 22,
                color: isSelected ? Colors.white : Colors.grey.shade600,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
