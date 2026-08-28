import 'package:flutter/material.dart'; // Flutter UI framework
import 'package:cloud_firestore/cloud_firestore.dart'; // Firestore database access
import 'package:firebase_auth/firebase_auth.dart'; // Firebase authentication

import 'main.dart'
    show SF; // Import SF color helper for light/dark theme support

// QualityPage shows live fuel quality data fetched from Firestore sensors
class QualityPage extends StatelessWidget {
  const QualityPage(
      {super.key}); // Constructor with key for widget identification

  // Fetches the current logged-in user's UID and their active vehicle ID from Firestore
  Future<_UserVehiclePath> _path() async {
    final uid =
        FirebaseAuth.instance.currentUser!.uid; // Get current user's UID
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get(); // Fetch user document from Firestore
    final vehicleId = (userDoc.data() ?? {})['activeVehicleId']?.toString() ??
        'veh_1'; // Read active vehicle ID, fallback to 'veh_1'
    return _UserVehiclePath(
        uid: uid,
        vehicleId:
            vehicleId); // Return both UID and vehicle ID as a single object
  }

  // Formats a Firestore Timestamp into a readable date-time string
  String _fmtTs(dynamic ts) {
    if (ts is Timestamp) {
      // Check if the value is actually a Timestamp
      final dt = ts.toDate(); // Convert Timestamp to Dart DateTime
      final mm = dt.minute
          .toString()
          .padLeft(2, '0'); // Pad minutes to always show 2 digits e.g. 09
      return '${dt.day}-${dt.month}-${dt.year}  ${dt.hour}:$mm'; // Return formatted string e.g. 7-5-2025  14:09
    }
    return '--'; // Return placeholder if no valid timestamp
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >=
        900; // Check if screen is wide enough for sidebar layout

    return FutureBuilder<_UserVehiclePath>(
      future: _path(), // Trigger the async user/vehicle path fetch
      builder: (_, pSnap) {
        if (!pSnap.hasData) {
          return const Center(
              child:
                  CircularProgressIndicator()); // Show spinner while user path is loading
        }
        final p = pSnap.data!; // Unwrap the resolved user/vehicle path

        final sensorsRef = FirebaseFirestore.instance
            .collection('users')
            .doc(p.uid)
            .collection('vehicles')
            .doc(p.vehicleId)
            .collection('sensors')
            .doc(
                'latest'); // Reference to the latest sensor document in Firestore

        return Padding(
          padding: const EdgeInsets.all(
              16), // Add 16px padding around the whole page
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: sensorsRef
                .snapshots(), // Listen to real-time updates from the sensors/latest document
            builder: (_, sSnap) {
              final s = sSnap.data?.data() ??
                  {}; // Extract sensor data map, default to empty map if null

              // Read ultrasonic sensor status from Firestore, default to UNKNOWN if missing
              final ultrasonic =
                  (s['ultrasonicStatus']?.toString() ?? 'UNKNOWN')
                      .toUpperCase();

              // Read capacitive sensor status from Firestore, default to UNKNOWN if missing
              final capacitive =
                  (s['capacitiveStatus']?.toString() ?? 'UNKNOWN')
                      .toUpperCase();

              // Read water-in-fuel sensor status from Firestore, default to UNKNOWN if missing
              final waterStatus =
                  (s['waterInFuelStatus']?.toString() ?? 'UNKNOWN')
                      .toUpperCase();

              // Check if ultrasonic sensor is disconnected or offline
              final bool ultrasonicDisconnected =
                  ultrasonic == 'DISCONNECTED' || ultrasonic == 'OFFLINE';

              // Check if capacitive sensor is disconnected or offline
              final bool capacitiveDisconnected =
                  capacitive == 'DISCONNECTED' || capacitive == 'OFFLINE';

              // Check if water sensor is disconnected or offline
              final bool waterDisconnected =
                  waterStatus == 'DISCONNECTED' || waterStatus == 'OFFLINE';

              // Read the waterPresent boolean field; null if field is missing or not a bool
              final bool? waterPresent = (s['waterPresent'] is bool)
                  ? s['waterPresent'] as bool
                  : null;

              // Water is detected if waterPresent is true OR status is WARN or BAD
              final bool waterDetected = (waterPresent == true) ||
                  waterStatus == 'WARN' ||
                  waterStatus == 'BAD';

              // Decide what text to show in the Contaminants row
              String contaminantsText;
              if (waterDisconnected) {
                contaminantsText =
                    'Water sensor disconnected'; // Sensor not reachable
              } else if (waterDetected) {
                contaminantsText = 'Water present'; // Water contamination found
              } else if (waterPresent == false || waterStatus == 'OK') {
                contaminantsText = 'None'; // Fuel is clean
              } else {
                contaminantsText = 'Unknown'; // Not enough data to determine
              }

              // Decide the overall quality label and its display color
              String quality;
              Color qualityColor;

              if (ultrasonicDisconnected ||
                  capacitiveDisconnected ||
                  waterDisconnected) {
                quality = 'Sensor Issue'; // At least one sensor is offline
                qualityColor =
                    Colors.orangeAccent; // Orange to indicate a warning
              } else if (waterDetected) {
                quality = 'Warning'; // Water detected in fuel
                qualityColor = Colors.orangeAccent; // Orange warning color
              } else if (waterPresent == false || waterStatus == 'OK') {
                quality = 'Good'; // All sensors OK, no contamination
                qualityColor = Colors.greenAccent; // Green for healthy status
              } else {
                quality = 'Unknown'; // Cannot determine quality
                qualityColor =
                    SF.muted; // Use muted theme color for unknown state
              }

              final lastCheck = _fmtTs(
                  s['updatedAt']); // Format the last sensor update timestamp

              return Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start, // Align children to the left
                children: [
                  // TOP BAR — shows page title and hamburger menu on mobile
                  Row(
                    children: [
                      if (!isWide)
                        IconButton(
                          icon: Icon(Icons.menu,
                              color: SF
                                  .text), // Hamburger icon colored with theme text color
                          onPressed: () => Scaffold.of(context)
                              .openDrawer(), // Open the side drawer on tap
                        ),
                      Expanded(
                        child: Text(
                          'Quality', // Page title
                          style: TextStyle(
                            fontSize: 22, // Large title font size
                            fontWeight: FontWeight.bold, // Bold title
                            color: SF.text, // Theme-aware text color
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12), // Space between title and card

                  // QUALITY CARD — displays all sensor readings
                  Container(
                    width: 460, // Fixed card width
                    padding: const EdgeInsets.all(16), // Inner padding
                    decoration: BoxDecoration(
                      color: SF.card, // Theme-aware card background color
                      borderRadius:
                          BorderRadius.circular(16), // Rounded corners
                      border: Border.all(
                          color: SF.glass(
                              0.08)), // Subtle border using theme glass color
                    ),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start, // Left-align all rows
                      children: [
                        _row(
                            'Last Check',
                            lastCheck,
                            Icons
                                .schedule_rounded), // Show last sensor update time
                        const SizedBox(height: 10), // Spacing between rows

                        // Overall quality row — built inline because it needs a colored value
                        Row(
                          children: [
                            Icon(Icons.verified_rounded,
                                size: 15,
                                color:
                                    SF.muted), // Verified icon in muted color
                            const SizedBox(
                                width: 6), // Small gap between icon and label
                            Expanded(
                              child: Text('Overall',
                                  style:
                                      TextStyle(color: SF.muted)), // Label text
                            ),
                            Text(
                              quality, // e.g. Good / Warning / Sensor Issue / Unknown
                              style: TextStyle(
                                fontWeight: FontWeight.bold, // Bold value
                                color:
                                    qualityColor, // Dynamic color based on quality state
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10), // Spacing

                        _row('Contaminants', contaminantsText,
                            Icons.science_rounded), // Show contaminant status
                        const SizedBox(height: 10), // Spacing

                        // Show DISCONNECTED if sensor is offline, otherwise show raw status value
                        _row(
                            'Ultrasonic',
                            ultrasonicDisconnected
                                ? 'DISCONNECTED'
                                : ultrasonic,
                            Icons.radar_rounded),
                        const SizedBox(height: 10), // Spacing

                        _row(
                            'Capacitive',
                            capacitiveDisconnected
                                ? 'DISCONNECTED'
                                : capacitive,
                            Icons.electric_bolt_rounded),
                        const SizedBox(height: 10), // Spacing

                        _row(
                            'Water-in-Fuel',
                            waterDisconnected ? 'DISCONNECTED' : waterStatus,
                            Icons.water_drop_rounded),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16), // Space between card and button

                  // RECONNECT ALL BUTTON — resets all sensor statuses to OK in Firestore
                  _miniBtn(
                    text: 'Reconnect All',
                    onTap: () => sensorsRef.set(
                        {
                          // Write reset values to the sensors/latest document
                          'ultrasonicStatus': 'OK', // Reset ultrasonic to OK
                          'capacitiveStatus': 'OK', // Reset capacitive to OK
                          'waterInFuelStatus': 'OK', // Reset water sensor to OK
                          'waterPresent': false, // Mark water as not present
                          'updatedAt': FieldValue
                              .serverTimestamp(), // Set update time to server's current time
                        },
                        SetOptions(
                            merge:
                                true)), // Merge so other fields in the document are not deleted
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  // Helper widget — builds a single labeled row with an icon and a status value
  static Widget _row(String k, String v, [IconData? icon]) {
    Color valColor = SF.text; // Default value color is theme text color
    final vUp =
        v.toUpperCase(); // Uppercase the value for case-insensitive comparison
    if (vUp == 'OK' || vUp == 'GOOD' || vUp == 'NONE')
      valColor = Colors.greenAccent; // Green for healthy/clean statuses
    if (vUp == 'WARN' || vUp == 'WARNING' || vUp == 'WATER PRESENT')
      valColor = Colors.orangeAccent; // Orange for warning statuses
    if (vUp.contains('DISCONNECTED') || vUp == 'BAD' || vUp == 'SENSOR ISSUE')
      valColor = Colors.redAccent; // Red for error/disconnected statuses

    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon,
              size: 14, color: SF.muted), // Small icon in muted theme color
          const SizedBox(width: 6), // Gap between icon and label
        ],
        Expanded(
            child: Text(k,
                style: TextStyle(color: SF.muted))), // Label e.g. "Ultrasonic"
        Text(v,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: valColor)), // Value with status color
      ],
    );
  }

  // Helper widget — builds the green Reconnect All elevated button
  static Widget _miniBtn(
      {required String text, required Future<void> Function() onTap}) {
    return SizedBox(
      height: 40, // Fixed button height
      child: ElevatedButton(
        onPressed: () async =>
            onTap(), // Call the provided async function on press
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF35F28E), // Green button background
          foregroundColor: Colors.black, // Black text/icon on top of green
          shape: RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(12)), // Rounded button corners
        ),
        child: Text(text,
            style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12)), // Bold small button label
      ),
    );
  }
}

// Simple data class to hold the current user's UID and active vehicle ID together
class _UserVehiclePath {
  final String uid; // Firebase Auth user ID
  final String vehicleId; // Active vehicle document ID
  _UserVehiclePath(
      {required this.uid,
      required this.vehicleId}); // Constructor requiring both fields
}
