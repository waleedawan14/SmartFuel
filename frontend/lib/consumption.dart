// consumption.dart
// Part of the SmartFuel app library declared in main.dart.
// Uses all shared classes from main.dart (SF, _PageShell, _StatTile,
// _GlassBox, _BarChartWidget) without any re-imports.

part of 'main.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CONSUMPTION PAGE
//
// Matches code2.html consumption section:
//   Avg Daily   (id="avgDaily")   = total liters last 30 days ÷ 30
//   Weekly      (id="weekly")     = sum of liters in last 7 days
//   Last Refuel (id="lastRefuel") = timestamp of last entry with type=='refuel'
//
// Data source: Firestore  users/{uid}/vehicles/{vid}/telemetry/history/items
// Fields read: createdAt (Timestamp)  |  liters (num)  |  type (String)
// ─────────────────────────────────────────────────────────────────────────────
class ConsumptionPage extends StatefulWidget {
  const ConsumptionPage({super.key});

  @override
  State<ConsumptionPage> createState() => _ConsumptionState();
}

class _ConsumptionState extends State<ConsumptionPage> {
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;

  double _avgDaily = 0;
  double _weekly = 0;
  String _lastRefuel = '--';

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _histSub;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _histSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final vid =
        (userDoc.data() ?? {})['activeVehicleId']?.toString() ?? 'veh_1';

    await _histSub?.cancel();
    _histSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('vehicles')
        .doc(vid)
        .collection('telemetry')
        .doc('history')
        .collection('items')
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots()
        .listen((snap) {
      final history = snap.docs.map((d) => d.data()).toList();

      final now = DateTime.now();
      final ago30 = now.subtract(const Duration(days: 30));
      final ago7 = now.subtract(const Duration(days: 7));

      double total30 = 0;
      double total7 = 0;
      String lastRefuel = '--';

      for (final entry in history) {
        final ts = entry['createdAt'];
        if (ts is! Timestamp) continue;

        final dt = ts.toDate();
        final liters = (entry['liters'] as num?)?.toDouble() ?? 0;
        final type = entry['type']?.toString() ?? '';

        if (dt.isAfter(ago30)) total30 += liters;
        if (dt.isAfter(ago7)) total7 += liters;

        if (lastRefuel == '--' && type == 'refuel') {
          lastRefuel = '${dt.day.toString().padLeft(2, '0')}/'
              '${dt.month.toString().padLeft(2, '0')}/'
              '${dt.year}  '
              '${dt.hour.toString().padLeft(2, '0')}:'
              '${dt.minute.toString().padLeft(2, '0')}';
        }
      }

      if (mounted) {
        setState(() {
          _history = history;
          _avgDaily = total30 / 30;
          _weekly = total7;
          _lastRefuel = lastRefuel;
          _loading = false;
        });
      }
    });
  }

  String _fmtTs(dynamic ts) {
    if (ts is! Timestamp) return '--';
    final dt = ts.toDate();
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return _PageShell(
      title: 'Refueling History',
      subtitle: 'Daily, weekly & refuel stats',
      child: _loading
          ? Center(child: CircularProgressIndicator(color: SF.green))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 3 stat tiles ─────────────────────────────────────────
                  LayoutBuilder(builder: (_, bc) {
                    final cols = bc.maxWidth >= 600 ? 3 : 1;
                    return GridView.count(
                      crossAxisCount: cols,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.6,
                      children: [
                        _StatTile(
                          icon: Icons.today_outlined,
                          label: 'Avg Daily',
                          value: '${_avgDaily.toStringAsFixed(2)} L',
                          sub: 'last 30 days ÷ 30',
                        ),
                        _StatTile(
                          icon: Icons.date_range_outlined,
                          label: 'Weekly',
                          value: '${_weekly.toStringAsFixed(2)} L',
                          sub: 'last 7 days total',
                        ),
                        _StatTile(
                          icon: Icons.local_gas_station_outlined,
                          label: 'Last Refuel',
                          value: _lastRefuel,
                          sub: _lastRefuel == '--'
                              ? 'no refuel recorded yet'
                              : 'most recent top-up',
                          valueFontSize: _lastRefuel == '--' ? 18 : 13,
                        ),
                      ],
                    );
                  }),
                  const SizedBox(height: 16),

                  // ── Bar chart ─────────────────────────────────────────────
                  if (_history.isNotEmpty) ...[
                    _GlassBox(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Consumption Trend',
                            style: TextStyle(
                              color: SF.green,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Last 12 readings',
                            style: TextStyle(color: SF.muted, fontSize: 11),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 180,
                            child: _BarChartWidget(history: _history),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── History table ─────────────────────────────────────────
                  _GlassBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(
                              'Refuel History',
                              style: TextStyle(
                                color: SF.green,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Text(
                            '${_history.length} entries',
                            style: TextStyle(color: SF.muted, fontSize: 11),
                          ),
                        ]),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                              child: Text('Time',
                                  style: TextStyle(
                                      color: SF.muted, fontSize: 12))),
                          Expanded(
                              child: Text('Type',
                                  style: TextStyle(
                                      color: SF.muted, fontSize: 12))),
                          Expanded(
                              child: Text('Liters',
                                  style: TextStyle(
                                      color: SF.muted, fontSize: 12))),
                        ]),
                        Divider(color: SF.glass(0.08)),
                        if (_history.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'No history yet — press Simulate on the Home page.',
                              style: TextStyle(color: SF.muted, fontSize: 13),
                            ),
                          )
                        else
                          ..._history.take(50).map(
                                (entry) => Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 6),
                                  child: Row(children: [
                                    Expanded(
                                      child: Text(
                                        _fmtTs(entry['createdAt']),
                                        style: TextStyle(
                                            color: SF.muted, fontSize: 12),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        entry['type']?.toString() ?? '--',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: entry['type'] == 'refuel'
                                              ? SF.green
                                              : SF.text,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        '${(entry['liters'] as num?)?.toStringAsFixed(2) ?? '--'} L',
                                        style: TextStyle(
                                          color: SF.green,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ]),
                                ),
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
