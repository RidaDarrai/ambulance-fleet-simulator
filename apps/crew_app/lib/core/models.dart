import 'package:latlong2/latlong.dart';

import 'mission_status.dart';

/// Patient medical snapshot carried on a mission (`patients/{uid}` in the
/// backend). Null fields render "None reported"; [name] null = guest caller.
class PatientProfile {
  final String? name;
  final String? bloodType;
  final List<String> allergies;
  final List<String> conditions;
  final List<String> contacts; // "Name · +212…"
  final String? contactPhone;

  const PatientProfile({
    this.name,
    this.bloodType,
    this.allergies = const [],
    this.conditions = const [],
    this.contacts = const [],
    this.contactPhone,
  });

  bool get isGuest => name == null && bloodType == null;

  /// One-line summary for the incoming-job card.
  String get summaryLine {
    if (isGuest) return 'Guest caller · no profile';
    return [
      ?bloodType,
      if (allergies.isNotEmpty) '${allergies.first} allergy',
      if (contacts.isNotEmpty)
        '${contacts.length} contact${contacts.length > 1 ? 's' : ''}',
    ].join(' · ');
  }
}

/// One mission as the crew sees it (`missions/{id}` + `timeline.*`).
class Mission {
  final String id;
  MissionStatus status;
  final PatientProfile patient;
  final String pickupLabel;
  final LatLng pickup;
  String? hospitalId;
  String? hospitalName;
  final DateTime createdAt;
  Map<MissionStatus, DateTime> timeline; // server timestamps
  int etaSeconds; // OSRM estimate — demo drives it down
  double distanceKm;
  bool offlinePending; // queued write (spec §14)

  // OSRM road geometry (null until fetched / when offline → straight line).
  List<LatLng>? routeToPickup;
  List<LatLng>? routeToHospital;
  int legTotalSeconds = 0; // ETA when the active leg started (progress)

  Mission({
    required this.id,
    required this.status,
    required this.patient,
    required this.pickupLabel,
    required this.pickup,
    this.hospitalId,
    this.hospitalName,
    required this.createdAt,
    this.timeline = const {},
    this.etaSeconds = 0,
    this.distanceKm = 0,
    this.offlinePending = false,
    this.routeToPickup,
    this.routeToHospital,
  });

  /// The leg the unit is currently driving (fallback: straight line).
  List<LatLng>? get activeRoute =>
      status == MissionStatus.transporting ||
              status == MissionStatus.atHospital
          ? routeToHospital
          : routeToPickup;
}

/// Hospital row (`hospitals/{id}`).
class Hospital {
  final String id;
  final String name;
  final LatLng location;
  const Hospital({required this.id, required this.name, required this.location});
}

/// Chat message (`missions/{id}/messages`).
class ChatMessage {
  final String text;
  final String senderRole; // crew | dispatcher | patient
  final DateTime at;
  final bool pending;
  const ChatMessage({
    required this.text,
    required this.senderRole,
    required this.at,
    this.pending = false,
  });
}

/// Completed mission row for History (§11).
class MissionHistoryEntry {
  final String id;
  final String route; // "Maârif → Ibn Sina"
  final String patientSummary; // "Guest" / "O+ patient"
  final DateTime endedAt;
  final Duration duration;

  // Mission detail (§12) — nullable so older missions show "—" placeholders.
  final String? hospital;
  final String? bloodType;
  final bool isGuest;
  final Map<MissionStatus, DateTime>? timeline; // server timestamps per phase

  const MissionHistoryEntry({
    required this.id,
    required this.route,
    required this.patientSummary,
    required this.endedAt,
    required this.duration,
    this.hospital,
    this.bloodType,
    this.isGuest = false,
    this.timeline,
  });

  /// Response leg: assigned → accepted.
  Duration? get response =>
      timeline == null ? null : _between(MissionStatus.assigned, MissionStatus.accepted);

  /// Transport leg: onScene → atHospital.
  Duration? get transport =>
      timeline == null ? null : _between(MissionStatus.onScene, MissionStatus.atHospital);

  Duration? _between(MissionStatus from, MissionStatus to) {
    final a = timeline?[from];
    final b = timeline?[to];
    if (a == null || b == null) return null;
    return b.difference(a);
  }
}
