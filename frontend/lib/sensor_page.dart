import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// If you already have SFTheme in main.dart and want to reuse it,
/// you can remove this class and import your theme.
/// But keeping it here makes this file independent.
class SFTheme {
  static const bg = Color(0xFF050A08);
  static const card = Color(0xFF0B1411);
  static const green = Color(0xFF35F28E);
  static const dim = Color(0x88FFFFFF);

  static Color alpha(Color c, double a) => c.withAlpha((a * 255).round());
}

class SensorsPageV2 extends StatelessWidget {
  const SensorsPageV2({super.key});

  Future<_UserVehiclePath> _path() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Not logged in');
    }

    final uid = user.uid;
    final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();

    final vehicleId =
        (userDoc.data() ?? {})['activeVehicleId']?.toString() ?? 'veh_1';

    return _UserVehiclePath(uid: uid, vehicleId: vehicleId);
  }

  String _fmtTs(dynamic ts) {
    if (ts is Timestamp) {
      final dt = ts.toDate();
      return '${dt.day.toString().padLeft(2, '0')}-'
          '${dt.month.toString().padLeft(2, '0')}-'
          '${dt.year} '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    }
    if (ts == null) return '--';
    return ts.toString();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    return FutureBuilder<_UserVehiclePath>(
      future: _path(),
      builder: (_, pSnap) {
        if (!pSnap.hasData) {
          return const Scaffold(
            backgroundColor: SFTheme.bg,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final p = pSnap.data!;
        final sensorsLatestRef = FirebaseFirestore.instance
            .collection('users')
            .doc(p.uid)
            .collection('vehicles')
            .doc(p.vehicleId)
            .collection('sensors')
            .doc('latest');

        return Scaffold(
          backgroundColor: SFTheme.bg,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ✅ Top bar with MENU on small screens (so you can go to other pages)
                  Row(
                    children: [
                      if (!isWide)
                        Builder(
                          builder: (ctx) => IconButton(
                            icon: const Icon(Icons.menu),
                            onPressed: () => Scaffold.of(ctx).openDrawer(),
                          ),
                        ),
                      const SizedBox(width: 6),
                      const Text(
                        'Sensors',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'This page reads REAL sensor status from Firestore (sensors/latest).',
                    style: TextStyle(color: SFTheme.dim),
                  ),
                  const SizedBox(height: 14),

                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: sensorsLatestRef.snapshots(),
                    builder: (_, snap) {
                      final d = snap.data?.data() ?? {};

                      final ultrasonic =
                          d['ultrasonicStatus']?.toString() ?? '--';
                      final capacitive =
                          d['capacitiveStatus']?.toString() ?? '--';
                      final water = d['waterInFuelStatus']?.toString() ?? '--';
                      final updatedAt = _fmtTs(d['updatedAt']);
                      final lastCalib = _fmtTs(d['lastCalibratedAt']);

                      Future<void> calibrate() async {
                        // Step 1: show "CALIBRATING..." immediately
                        await sensorsLatestRef.set({
                          'ultrasonicStatus': 'CALIBRATING...',
                          'capacitiveStatus': 'CALIBRATING...',
                          'waterInFuelStatus': 'CALIBRATING...',
                          'calibrateRequestedAt': FieldValue.serverTimestamp(),
                          'updatedAt': FieldValue.serverTimestamp(),
                        }, SetOptions(merge: true));

                        // Step 2: after 1.5s reset to OK (simulating real calibration)
                        await Future.delayed(
                            const Duration(milliseconds: 1500));

                        await sensorsLatestRef.set({
                          'ultrasonicStatus': 'OK',
                          'capacitiveStatus': 'OK',
                          'waterInFuelStatus': 'OK',
                          'lastCalibratedAt': FieldValue.serverTimestamp(),
                          'updatedAt': FieldValue.serverTimestamp(),
                        }, SetOptions(merge: true));
                      }

                      return Container(
                        width: 520,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: SFTheme.card,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: SFTheme.alpha(Colors.white, 0.08),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Sensors & Calibration',
                              style: TextStyle(
                                color: SFTheme.green,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _kv('Ultrasonic', ultrasonic),
                            _kv('Capacitive', capacitive),
                            _kv('Water-in-Fuel', water),
                            const SizedBox(height: 10),
                            _kv('Last Sync', updatedAt),
                            _kv('Last Calibrated', lastCalib),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                SizedBox(
                                  width: 160,
                                  height: 46,
                                  child: ElevatedButton(
                                    onPressed: () async {
                                      try {
                                        await calibrate();
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                  'Calibration completed ✅'),
                                            ),
                                          );
                                        }
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content:
                                                  Text('Calibrate failed: $e'),
                                              backgroundColor: Colors.redAccent,
                                            ),
                                          );
                                        }
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: SFTheme.green,
                                      foregroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    child: const Text(
                                      'Calibrate',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    snap.hasError ? 'Error: ${snap.error}' : '',
                                    style: const TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text('$k:',
                style: const TextStyle(color: SFTheme.dim, fontSize: 13)),
          ),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _UserVehiclePath {
  final String uid;
  final String vehicleId;
  _UserVehiclePath({required this.uid, required this.vehicleId});
}
