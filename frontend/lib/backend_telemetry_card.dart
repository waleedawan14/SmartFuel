import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'main.dart'; // for SF, kBackendBase

class BackendTelemetryCard extends StatefulWidget {
  const BackendTelemetryCard({super.key});

  @override
  State<BackendTelemetryCard> createState() => _BackendTelemetryCardState();
}

class _BackendTelemetryCardState extends State<BackendTelemetryCard> {
  Map<String, dynamic>? data;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    fetchTelemetry();
  }

  Future<void> fetchTelemetry() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final resp = await http.get(Uri.parse('$kBackendBase/telemetry/latest'));
      if (resp.statusCode == 200) {
        data = jsonDecode(resp.body) as Map<String, dynamic>;
      } else {
        error = 'Server returned ${resp.statusCode}';
      }
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _computeAlert(String? water, String? ultrasonic, String? capacitive) {
    water = (water ?? 'UNKNOWN').toUpperCase();
    ultrasonic = (ultrasonic ?? 'UNKNOWN').toUpperCase();
    capacitive = (capacitive ?? 'UNKNOWN').toUpperCase();

    if (water == 'BAD' ||
        ultrasonic == 'DISCONNECTED' ||
        capacitive == 'DISCONNECTED') {
      return '⚠ Check sensors';
    }
    if (water == 'WARN') return '⚠ Water detected (LOW)';
    if (water == 'OK') return 'No alerts';
    return 'Unknown';
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Center(child: CircularProgressIndicator(color: SF.green));
    }

    if (error != null) {
      return _GlassBox(
        child: Row(
          children: [
            const Icon(Icons.wifi_off_rounded,
                color: Colors.redAccent, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Backend offline: $error',
                  style:
                      const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ),
            _ChipBtn(label: 'Retry', onTap: fetchTelemetry),
          ],
        ),
      );
    }

    final fuelL = (data?['fuel_liters'] as num?)?.toDouble() ??
        (data?['fuelLiters'] as num?)?.toDouble() ??
        0.0;
    final fuelPct = (data?['fuel_percent'] as num?)?.toDouble() ??
        (data?['fuelPercent'] as num?)?.toDouble() ??
        0.0;
    final alerts = _computeAlert(
      data?['waterInFuelStatus']?.toString() ??
          data?['water_in_fuel']?.toString(),
      data?['ultrasonicStatus']?.toString(),
      data?['capacitiveStatus']?.toString(),
    );

    final alertColor = alerts.startsWith('⚠') ? Colors.orangeAccent : SF.green;

    return _GlassBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: SF.green.withAlpha(28),
                  borderRadius: BorderRadius.circular(8),
                ),
                child:
                    Icon(Icons.cloud_done_rounded, color: SF.green, size: 14),
              ),
              const SizedBox(width: 10),
              Text('Backend Telemetry',
                  style: TextStyle(
                      color: SF.green,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
              const Spacer(),
              _ChipBtn(label: 'Refresh', onTap: fetchTelemetry),
            ],
          ),
          const SizedBox(height: 14),

          // ── Stats ────────────────────────────────────────────────────────
          _KVRow(
              label: 'Fuel Level',
              value:
                  '${fuelL.toStringAsFixed(2)} L  (${fuelPct.toStringAsFixed(0)}%)'),
          _KVRow(label: 'Alerts', value: alerts, valueColor: alertColor),

          // show all remaining keys from the payload
          if (data != null) ...[
            const SizedBox(height: 8),
            Divider(color: SF.glass(0.06)),
            const SizedBox(height: 8),
            ...data!.entries
                .where((e) =>
                    e.key != 'fuel_liters' &&
                    e.key != 'fuelLiters' &&
                    e.key != 'fuel_percent' &&
                    e.key != 'fuelPercent')
                .map((e) => _KVRow(
                      label: e.key,
                      value: e.value?.toString() ?? '--',
                    )),
          ],
        ],
      ),
    );
  }
}

// ── Local helper widgets ──────────────────────────────────────────────────────

class _GlassBox extends StatelessWidget {
  final Widget child;
  const _GlassBox({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SF.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SF.glass(0.06)),
        boxShadow: [BoxShadow(color: SF.shadow(), blurRadius: 20)],
      ),
      child: child,
    );
  }
}

class _KVRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _KVRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text('$label:',
                style: TextStyle(color: SF.muted, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    color: valueColor ?? SF.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _ChipBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ChipBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: SF.green.withAlpha(28),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: SF.green.withAlpha(80)),
        ),
        child: Text(label,
            style: TextStyle(
                color: SF.green, fontSize: 11, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
