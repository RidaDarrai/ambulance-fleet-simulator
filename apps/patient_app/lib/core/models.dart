import 'package:latlong2/latlong.dart';

import 'mission_status.dart';

/// Simulated user location (Casablanca) and target hospital — demo defaults.
/// The Firebase repository replaces these with real geolocation + a hospital
/// lookup; they live here so both repositories share the same constants.
const LatLng kUserLocation = LatLng(33.573110, -7.589843);
const LatLng kHospital = LatLng(33.582300, -7.632500);
const String kHospitalName = "St. Mary's Hospital";

class EmergencyContact {
  String id;
  String name;
  String relationship;
  String phone;

  EmergencyContact({
    required this.id,
    required this.name,
    required this.relationship,
    required this.phone,
  });
}

/// Mutable medical profile (screen spec §11) — edits mark `pendingSync`
/// while offline and always refresh `lastUpdated`.
class MedicalProfile {
  String? bloodType;
  final List<String> allergies;
  final List<String> conditions;
  final List<EmergencyContact> contacts;
  DateTime lastUpdated;
  bool pendingSync;

  MedicalProfile({
    this.bloodType,
    List<String>? allergies,
    List<String>? conditions,
    List<EmergencyContact>? contacts,
    DateTime? lastUpdated,
    this.pendingSync = false,
  })  : allergies = allergies ?? [],
        conditions = conditions ?? [],
        contacts = contacts ?? [],
        lastUpdated = lastUpdated ?? DateTime.now();

  /// Demo seed — cleared via "Reset profile (demo)" to see the first-use
  /// empty state (spec §11).
  factory MedicalProfile.seeded() => MedicalProfile(
        bloodType: 'O+',
        allergies: ['Penicillin'],
        conditions: ['Asthma'],
        contacts: [
          EmergencyContact(
              id: 'c1',
              name: 'Sarah Alaoui',
              relationship: 'Sister',
              phone: '06 12 34 56 78'),
          EmergencyContact(
              id: 'c2',
              name: 'Dr. Benali',
              relationship: 'Doctor',
              phone: '05 22 98 76 54'),
        ],
        lastUpdated: DateTime.now().subtract(const Duration(days: 3)),
      );

  bool get isEmpty =>
      bloodType == null &&
      allergies.isEmpty &&
      conditions.isEmpty &&
      contacts.isEmpty;

  bool get incomplete => bloodType == null; // nudge target (spec §11)
}

class AmbulanceUnit {
  final String id;
  final String callsign;
  final int crewSize;
  final String vehicleType; // public crew info (spec §4)
  LatLng position;
  bool available;

  AmbulanceUnit({
    required this.id,
    required this.callsign,
    required this.crewSize,
    this.vehicleType = 'ALS',
    required this.position,
    this.available = true,
  });
}

class Incident {
  final String id;
  final LatLng pickup;
  final LatLng hospital;
  final DateTime createdAt;
  final int queuePosition; // FIFO position at submission (baseline: plain queue)
  MissionStatus status;
  int etaSeconds;
  String? unitId;
  bool addedToHistory;

  /// When each status was first reached — drives the §8 summary timestamps.
  final Map<MissionStatus, DateTime> statusTimes = {};

  /// Audit-trail snapshots (§10): captured at request/assignment time so the
  /// history stays accurate even if the fleet changes later.
  final bool medicalAttached;
  String? unitCallsign;

  Incident({
    required this.id,
    required this.pickup,
    required this.hospital,
    required this.createdAt,
    required this.status,
    this.queuePosition = 1,
    this.etaSeconds = 0,
    this.unitId,
    this.addedToHistory = false,
    this.medicalAttached = false,
    this.unitCallsign,
  }) {
    statusTimes[status] = createdAt;
  }
}
