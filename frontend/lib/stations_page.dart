// stations_page.dart
//
// Part of the SmartFuel app library declared in main.dart.
// Uses SF, _PageShell, _GlassBox, _ChipBtn, _GradBtn from main.dart
// without re-importing them.
//
// ── What this file adds ───────────────────────────────────────────────────────
//  • Real GPS location via geolocator
//  • Real petrol/fuel pump search via Google Places Nearby Search API
//  • Google Maps (google_maps_flutter) with dark style matching the app
//  • Green markers for each real station found within 5 km
//  • Real-time distance (live, updates as user moves)
//  • Tap marker OR list row → bottom sheet with name / address / distance
//  • "Get Directions" button → opens Google Maps app (or browser) with driving route
//  • Tap anywhere on map → navigate to that point
//  • Auto-refresh every 200 m of movement
//
// ── One-time setup ────────────────────────────────────────────────────────────
//  See README at bottom of this file for pubspec, AndroidManifest, Info.plist.

part of 'main.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ⚠️  PUT YOUR KEY HERE
//    Google Cloud Console → APIs & Services → Credentials → Create API key
//    Enable: Maps SDK for Android, Maps SDK for iOS, Places API
// ─────────────────────────────────────────────────────────────────────────────
String get _kApiKey => dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

// ─────────────────────────────────────────────────────────────────────────────
// MODEL
// ─────────────────────────────────────────────────────────────────────────────
class _NearbyStation {
  final String placeId;
  final String name;
  final String address;
  final double lat;
  final double lng;
  final double? rating;
  final bool openNow;
  // Driving distance in metres — populated after Distance Matrix call
  final double? drivingDistanceM;

  const _NearbyStation({
    required this.placeId,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    this.rating,
    this.openNow = false,
    this.drivingDistanceM,
  });

  factory _NearbyStation.fromJson(Map<String, dynamic> j) {
    final geo = j['geometry']['location'] as Map<String, dynamic>;
    final oh = j['opening_hours'] as Map<String, dynamic>?;
    return _NearbyStation(
      placeId: j['place_id'] as String,
      name: j['name'] as String,
      address: (j['vicinity'] ?? j['formatted_address'] ?? '') as String,
      lat: (geo['lat'] as num).toDouble(),
      lng: (geo['lng'] as num).toDouble(),
      rating: (j['rating'] as num?)?.toDouble(),
      openNow: oh?['open_now'] as bool? ?? false,
    );
  }

  _NearbyStation withDriving(double metres) => _NearbyStation(
        placeId: placeId,
        name: name,
        address: address,
        lat: lat,
        lng: lng,
        rating: rating,
        openNow: openNow,
        drivingDistanceM: metres,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// STATIONS PAGE
// ─────────────────────────────────────────────────────────────────────────────
class StationsPage extends StatefulWidget {
  const StationsPage({super.key});

  @override
  State<StationsPage> createState() => _StationsPageState();
}

class _StationsPageState extends State<StationsPage> {
  final Completer<GoogleMapController> _ctrl = Completer();

  Position? _userPos;
  List<_NearbyStation> _stations = [];
  List<_NearbyStation> _firestoreStations = [];
  Set<Marker> _markers = {};
  bool _locLoading = true;
  bool _fetching = false;
  String? _error;

  StreamSubscription<Position>? _posSub;
  // placeId → driving distance metres (from Distance Matrix API)
  final Map<String, double> _drivingDist = {};

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _startLocation();
    _fetchFirestoreStations();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    super.dispose();
  }

  // ── Firestore /stations ───────────────────────────────────────────────────────

  Future<void> _fetchFirestoreStations() async {
    try {
      final snap =
          await FirebaseFirestore.instance.collection('stations').get();
      final loaded = snap.docs.map((doc) {
        final d = doc.data();
        return _NearbyStation(
          placeId: 'fs_${doc.id}',
          name: d['name']?.toString() ?? doc.id,
          address: d['address']?.toString() ?? '',
          lat: (d['lat'] as num).toDouble(),
          lng: (d['lng'] as num).toDouble(),
          rating: (d['rating'] as num?)?.toDouble(),
          openNow: d['openNow'] as bool? ?? false,
        );
      }).toList();
      if (!mounted) return;
      setState(() => _firestoreStations = loaded);
      // If GPS is already ready, rebuild markers to include Firestore stations
      if (_userPos != null) _applyStations(_stations, _userPos!);
    } catch (_) {
      // Firestore fetch failure — existing Google Places flow unaffected
    }
  }

  // ── GPS ──────────────────────────────────────────────────────────────────────

  Future<void> _startLocation() async {
    setState(() {
      _locLoading = true;
      _error = null;
    });

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _setError('Location services are disabled.\nPlease turn on GPS.');
        return;
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _setError('Location permission denied.\nSettings → App → Location.');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );

      if (!mounted) return;
      setState(() {
        _userPos = pos;
        _locLoading = false;
      });
      _moveCamera(pos);
      await _fetchStations(pos);

      // Re-fetch when user moves ≥ 200 m
      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 200,
        ),
      ).listen((p) {
        if (!mounted) return;
        setState(() => _userPos = p);
        _moveCamera(p);
        _fetchStations(p);
      });
    } catch (e) {
      _setError('Could not get location.\n$e');
    }
  }

  void _setError(String m) {
    if (mounted)
      setState(() {
        _error = m;
        _locLoading = false;
      });
  }

  Future<void> _moveCamera(Position pos) async {
    if (!_ctrl.isCompleted) return;
    final c = await _ctrl.future;
    c.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 14.5));
  }

  // ── Google Places Nearby Search ──────────────────────────────────────────────
  //  Searches for real petrol / gas stations within 5 km of user.
  //  type=gas_station covers: petrol pumps, CNG, diesel stations.

  Future<void> _fetchStations(Position pos) async {
    if (_fetching) return;
    setState(() => _fetching = true);

    try {
      List<_NearbyStation> results = [];

      if (_kApiKey != 'YOUR_GOOGLE_API_KEY_HERE') {
        final uri = Uri.https(
          'maps.googleapis.com',
          '/maps/api/place/nearbysearch/json',
          {
            'location': '${pos.latitude},${pos.longitude}',
            'radius': '5000', // 5 km — adjust as needed
            'type': 'gas_station',
            'key': _kApiKey,
          },
        );

        final res = await http.get(uri).timeout(const Duration(seconds: 10));
        if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');

        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final status = body['status'] as String;

        if (status == 'OK') {
          results = (body['results'] as List)
              .map((r) => _NearbyStation.fromJson(r as Map<String, dynamic>))
              .toList();
        } else if (status != 'ZERO_RESULTS') {
          throw Exception('Places API returned: $status');
        }
      }

      _applyStations(results, pos);
    } catch (_) {
      // Don't crash — just show empty state
      _applyStations([], pos);
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  void _applyStations(List<_NearbyStation> stations, Position userPos) {
    final allStations = [
      ...stations,
      ..._firestoreStations
          .where((fs) => stations.every((s) => s.placeId != fs.placeId)),
    ];

    final markers = <Marker>{
      // User's blue dot
      Marker(
        markerId: const MarkerId('__me__'),
        position: LatLng(userPos.latitude, userPos.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: 'You are here'),
        zIndex: 3,
      ),
    };

    for (final s in allStations) {
      markers.add(Marker(
        markerId: MarkerId(s.placeId),
        position: LatLng(s.lat, s.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(s.placeId.startsWith('fs_')
            ? BitmapDescriptor.hueOrange
            : BitmapDescriptor.hueGreen),
        zIndex: 1,
        onTap: () => _showSheet(s),
      ));
    }

    if (mounted)
      setState(() {
        _stations = allStations;
        _markers = markers;
      });

    // Fetch real driving distances in the background
    if (allStations.isNotEmpty) {
      _fetchDrivingDistances(allStations, userPos);
    }
  }

  // ── Distance Matrix API ──────────────────────────────────────────────────────────────────────────
  //  Calls Google Distance Matrix for up to 25 destinations at once.
  //  Updates _stations in place and rebuilds the list.

  Future<void> _fetchDrivingDistances(
      List<_NearbyStation> stations, Position origin) async {
    if (_kApiKey == 'YOUR_GOOGLE_API_KEY_HERE') return;

    try {
      // Build destinations string (max 25 per request)
      final batch = stations.take(25).toList();
      final destinations = batch.map((s) => '\${s.lat},\${s.lng}').join('|');

      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/distancematrix/json',
        {
          'origins': '\${origin.latitude},\${origin.longitude}',
          'destinations': destinations,
          'mode': 'driving',
          'units': 'metric',
          'key': _kApiKey,
        },
      );

      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return;

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['status'] != 'OK') return;

      final rows = body['rows'] as List?;
      if (rows == null || rows.isEmpty) return;
      final elements = (rows[0] as Map)['elements'] as List;

      final updated = <_NearbyStation>[];
      for (int i = 0; i < batch.length; i++) {
        final el = elements[i] as Map<String, dynamic>;
        if (el['status'] == 'OK') {
          final metres = ((el['distance'] as Map)['value'] as num).toDouble();
          _drivingDist[batch[i].placeId] = metres;
          updated.add(batch[i].withDriving(metres));
        } else {
          updated.add(batch[i]);
        }
      }

      // Append any stations beyond the 25-item batch unchanged
      if (stations.length > 25) updated.addAll(stations.sublist(25));

      // Re-sort by driving distance (fallback to straight-line)
      updated.sort((a, b) {
        final da = a.drivingDistanceM ??
            (_userPos == null
                ? 0.0
                : Geolocator.distanceBetween(
                    _userPos!.latitude, _userPos!.longitude, a.lat, a.lng));
        final db = b.drivingDistanceM ??
            (_userPos == null
                ? 0.0
                : Geolocator.distanceBetween(
                    _userPos!.latitude, _userPos!.longitude, b.lat, b.lng));
        return da.compareTo(db);
      });

      if (mounted) setState(() => _stations = updated);
    } catch (_) {
      // Distance Matrix failed — straight-line distances remain visible
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  /// Returns driving distance if available, else straight-line fallback.
  String _dist(_NearbyStation s) {
    // Prefer driving distance from Distance Matrix API
    final driving = s.drivingDistanceM ?? _drivingDist[s.placeId];
    if (driving != null) {
      return driving < 1000
          ? '${driving.toStringAsFixed(0)} m (driving)'
          : '${(driving / 1000).toStringAsFixed(1)} km (driving)';
    }
    // Fallback: straight-line
    if (_userPos == null) return '';
    final m = Geolocator.distanceBetween(
        _userPos!.latitude, _userPos!.longitude, s.lat, s.lng);
    return m < 1000
        ? '${m.toStringAsFixed(0)} m (≈straight line)'
        : '${(m / 1000).toStringAsFixed(1)} km (≈straight line)';
  }

  Future<void> _openNav(double lat, double lng) async {
    final app = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    final web = Uri.parse('https://www.google.com/maps/dir/?api=1'
        '&destination=$lat,$lng&travelmode=driving');
    if (await canLaunchUrl(app)) {
      await launchUrl(app, mode: LaunchMode.externalApplication);
    } else {
      await launchUrl(web, mode: LaunchMode.externalApplication);
    }
  }

  void _showSheet(_NearbyStation s) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _StationSheet(
        station: s,
        distance: _dist(s),
        onNavigate: () => _openNav(s.lat, s.lng),
      ),
    );
  }

  Future<void> _focusStation(_NearbyStation s) async {
    final c = await _ctrl.future;
    c.animateCamera(CameraUpdate.newLatLngZoom(LatLng(s.lat, s.lng), 16));
    _showSheet(s);
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return _PageShell(
      title: 'Fuel Stations',
      subtitle: _locLoading
          ? 'Finding your location…'
          : _stations.isEmpty
              ? 'No petrol pumps found nearby'
              : '${_stations.length} fuel stations within 5 km',
      actions: [
        if (_fetching)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: SF.green),
            ),
          ),
        if (!_locLoading && _error == null && _userPos != null)
          _ChipBtn(
            label: 'Refresh',
            onTap: () => _fetchStations(_userPos!),
          ),
        const SizedBox(width: 8),
      ],
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_locLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: SF.green),
            const SizedBox(height: 16),
            Text('Getting your location…', style: TextStyle(color: SF.muted)),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_off, color: SF.muted, size: 48),
              const SizedBox(height: 16),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: SF.muted, fontSize: 14)),
              const SizedBox(height: 20),
              _GradBtn(text: 'Try again', onTap: _startLocation),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // ── Google Map ─────────────────────────────────────────────────────
        Expanded(
          flex: 5,
          child: Stack(
            children: [
              GoogleMap(
                onMapCreated: (c) {
                  if (!_ctrl.isCompleted) _ctrl.complete(c);
                },
                initialCameraPosition: CameraPosition(
                  target: LatLng(_userPos!.latitude, _userPos!.longitude),
                  zoom: 14.5,
                ),
                markers: _markers,
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                mapType: MapType.normal,
                style: _kDarkMapStyle,
                // Tap anywhere on map → open navigation to that point
                onTap: (ll) => _openNav(ll.latitude, ll.longitude),
              ),

              // My location FAB
              Positioned(
                bottom: 16,
                right: 16,
                child: FloatingActionButton.small(
                  heroTag: 'sfMyLoc',
                  backgroundColor: SF.card,
                  onPressed: () {
                    if (_userPos != null) _moveCamera(_userPos!);
                  },
                  child: Icon(Icons.my_location, color: SF.green),
                ),
              ),

              // Station count badge
              if (_stations.isNotEmpty)
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: SF.card.withAlpha(230),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: SF.green.withAlpha(80)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: SF.green,
                          boxShadow: [
                            BoxShadow(
                                color: SF.green.withAlpha(120), blurRadius: 6)
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('${_stations.length} stations',
                          style: TextStyle(
                              color: SF.green,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),

              // API key banner
              if (_kApiKey == 'YOUR_GOOGLE_API_KEY_HERE')
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withAlpha(230),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(children: [
                      Icon(Icons.vpn_key, size: 16, color: Colors.black),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Set _kApiKey in stations_page.dart to see real fuel stations.',
                          style: TextStyle(
                              color: Colors.black,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ]),
                  ),
                ),
            ],
          ),
        ),

        // ── Station list ────────────────────────────────────────────────────
        Expanded(
          flex: 4,
          child: _stations.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.local_gas_station,
                            color: SF.muted, size: 40),
                        const SizedBox(height: 12),
                        Text(
                          _kApiKey == 'YOUR_GOOGLE_API_KEY_HERE'
                              ? 'Add your Google API key to see real petrol pumps near you.'
                              : 'No fuel stations found within 5 km of your location.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: SF.muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: _stations.length,
                  separatorBuilder: (_, __) =>
                      Divider(color: SF.glass(0.06), height: 1),
                  itemBuilder: (_, i) {
                    final s = _stations[i];
                    return _StationListTile(
                      station: s,
                      distance: _dist(s),
                      onTap: () => _focusStation(s),
                      onNavigate: () => _openNav(s.lat, s.lng),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STATION LIST TILE
// ─────────────────────────────────────────────────────────────────────────────
class _StationListTile extends StatelessWidget {
  final _NearbyStation station;
  final String distance;
  final VoidCallback onTap;
  final VoidCallback onNavigate;

  const _StationListTile({
    required this.station,
    required this.distance,
    required this.onTap,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: SF.green.withAlpha(28),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: SF.green.withAlpha(60)),
              ),
              child: Icon(Icons.local_gas_station, color: SF.green, size: 22),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(station.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (station.address.isNotEmpty)
                    Text(station.address,
                        style: TextStyle(color: SF.muted, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Row(children: [
                    Icon(Icons.near_me, size: 12, color: SF.green),
                    const SizedBox(width: 3),
                    Text(distance,
                        style: TextStyle(
                            color: SF.green,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                    if (station.rating != null) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.star, size: 12, color: Colors.amber),
                      const SizedBox(width: 2),
                      Text(station.rating!.toStringAsFixed(1),
                          style: TextStyle(color: SF.muted, fontSize: 11)),
                    ],
                    if (station.openNow) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: SF.green.withAlpha(30),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('Open',
                            style: TextStyle(
                                color: SF.green,
                                fontSize: 9,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ]),
                ],
              ),
            ),

            // Navigate icon
            IconButton(
              icon: const Icon(Icons.navigation),
              color: SF.green,
              tooltip: 'Navigate',
              onPressed: onNavigate,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOTTOM SHEET
// ─────────────────────────────────────────────────────────────────────────────
class _StationSheet extends StatelessWidget {
  final _NearbyStation station;
  final String distance;
  final VoidCallback onNavigate;

  const _StationSheet({
    required this.station,
    required this.distance,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: SF.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SF.green.withAlpha(60)),
        boxShadow: [BoxShadow(color: SF.shadow(), blurRadius: 24)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: SF.glass(0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: SF.green.withAlpha(28),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: SF.green.withAlpha(60)),
              ),
              child: Icon(Icons.local_gas_station, color: SF.green, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(station.name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  if (station.address.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(station.address,
                        style: TextStyle(color: SF.muted, fontSize: 12),
                        maxLines: 2),
                  ],
                ],
              ),
            ),
          ]),
          const SizedBox(height: 14),

          // Chips
          Wrap(spacing: 8, runSpacing: 6, children: [
            _chip(Icons.near_me, distance),
            if (station.rating != null)
              _chip(Icons.star, '${station.rating!.toStringAsFixed(1)} rating'),
            if (station.openNow) _chip(Icons.check_circle_outline, 'Open now'),
          ]),
          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                onNavigate();
              },
              icon: const Icon(Icons.navigation),
              label: const Text('Get Directions'),
              style: ElevatedButton.styleFrom(
                backgroundColor: SF.green,
                foregroundColor: Colors.black,
                textStyle:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: SF.green.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: SF.green.withAlpha(50)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: SF.green),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                color: SF.green, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DARK MAP STYLE  — hex colours match SF.bg / SF.card / SF.green exactly
// ─────────────────────────────────────────────────────────────────────────────
const String _kDarkMapStyle = r'''
[
  {"elementType":"geometry","stylers":[{"color":"#07110f"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#9bbfb0"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#07110f"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#0b1a16"}]},
  {"featureType":"administrative.country","elementType":"labels.text.fill","stylers":[{"color":"#9e9e9e"}]},
  {"featureType":"administrative.land_parcel","stylers":[{"visibility":"off"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#bdbdbd"}]},
  {"featureType":"poi","elementType":"labels.text","stylers":[{"visibility":"on"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#0b1a16"}]},
  {"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#2ecc71"}]},
  {"featureType":"road","elementType":"geometry.fill","stylers":[{"color":"#1a2e26"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#9ca5a0"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#213d32"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#2e5244"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#1a3328"}]},
  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#b0bec5"}]},
  {"featureType":"road.local","elementType":"labels.text.fill","stylers":[{"color":"#616161"}]},
  {"featureType":"transit","elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#04150e"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#515c53"}]}
]
''';
