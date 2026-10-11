# Ambulance Tracking & Dispatch System — Baseline Report

> This report summarizes all locked-in architectural, technical, functional, and scope decisions established during the conceptualization phase for the Ambulance Tracking and Dispatch Simulation System.
> Source: Google Docs (shared)

## 1. Project Context & Constraints

- **Project Scope:** Internship conceptualization and implementation project (not a commercial production deployment).
- **Design Philosophy:** Keep execution streamlined, leverage established patterns from open-source systems, and use simulated data streams for real-time tracking (e.g., GPS pings, incoming emergencies).
- **Reference Architectural Patterns:** Inspired by open-source computer-aided dispatch (CAD) systems (qppd/ambulance-dispatch-management-system, anupamkushwaha85/emergency-dispatch-system) and enterprise fleet management systems (Geotab).

## 2. Target Roles & Requirements

### Patient / Caller App (Flutter Mobile)
- **Guest vs. Authenticated Modes:** Guest users can directly view fleet status and initiate dispatch requests. Registered users can log in to store persistent medical information (blood type, critical allergies, chronic conditions, emergency contacts) that auto-attaches to emergency requests.
- **Fleet Visibility:** View real-time locations of available ambulance units on a map.
- **Emergency Request Entry:** One-tap panic button for logged-in users or direct dispatcher hotline calling.
- **Live Mission Tracking:** View assigned ambulance location, dynamic ETA countdown, and route polyline overlay.
- **Status Updates:** Real-time push updates across the lifecycle (dispatched → enRoute → arrivingSoon → resolved).
- **Secure Communication:** One-tap voice/chat connection to the assigned crew or dispatcher.

### Dispatcher / Operator Dashboard (React Web)
- **Real-time Operations Map:** Interactive map displaying all registered ambulance units and active emergency requests.
- **Triage Request Queue:** Sequential request queue (FIFO, plain queue without priority weighting).
- **Manual Dispatching with Automated Guidance:** Manual assignment interface supplemented by an automated "Nearest Unit Suggestion" engine.
- **Dispatch Lifecycle Management:** Track active missions, manage accept/reject outcomes, and reassign upon timeout or rejection.
- **Communication Channel:** Direct voice or chat connection to callers and crew members.

### Ambulance Crew / Driver Interface (Flutter Mobile)
- **Authentication & Shift Status:** Driver login with on-duty/off-duty state toggling.
- **Dispatch Acceptance:** Receive incoming assignment notifications with patient location and attached medical profile, with accept/reject options.
- **Turn-by-Turn Route Navigation:** Map routing from unit position to patient pickup, and subsequently to target hospital.
- **One-Tap Status Lifecycle:** Simple status update triggers (enRoute → onScene → transporting → atHospital → available).
- **Automated Telemetry:** Background GPS location pings to maintain real-time position tracking.

### System Administrator Panel (React Web)
- **User & Access Management:** RBAC setup for dispatchers, ambulance crew members, and system users.
- **Fleet Management:** CRUD operations for vehicles, license plates, equipment, and structural operational states.
- **Audit & Performance Logs:** Activity logs and response time metrics analytics.

## 3. Core Tech Stack & Architecture

```
+-----------------------------------------------------------------------+
|                              FRONTENDS                                |
|   +----------------------------------+----------------------------+   |
|   | Patient & Crew Mobile Apps       | Dispatcher & Admin Dash    |   |
|   | (Flutter - Android / iOS)        | (React Web)                |   |
|   +----------------------------------+----------------------------+   |
+-----------------------------------||----------------------------------+
                                   ||
+-----------------------------------||----------------------------------+
|                           FIREBASE BACKEND                            |
|   +---------------------------------------------------------------+   |
|   | Firebase Auth (Custom Role Claims: Patient, Crew, Admin, etc.)|   |
|   +-------------------------------+-------------------------------+   |
|   | Firestore DB                  | Realtime DB (RTDB)            |   |
|   | (Users, Missions, Fleet Data) | (High-Frequency GPS Pings)   |   |
|   +-------------------------------+-------------------------------+   |
|   | Cloud Functions                                               |   |
|   | (Haversine Nearest-Unit Calc, ETA Engine, Dispatch Timeouts)  |   |
|   +-------------------------------+-------------------------------+   |
|   | Firebase Cloud Messaging (FCM)| Google Maps SDK / JS API      |   |
|   | (Push Notifications)          | (Polylines & Routing)         |   |
|   +---------------------------------------------------------------+   |
+-----------------------------------------------------------------------+
```

| Layer | Technology Choice | Function & Scope |
|---|---|---|
| Mobile Applications | Flutter (Dart) | Cross-platform builds (Android/iOS) for Patient and Crew mobile apps. |
| Web Applications | React (JS/TS) | High-performance Web dashboards for Dispatcher Triage and Admin Panels. |
| Backend Logic | Firebase Cloud Functions | Serverless execution of Haversine distance calculations, nearest-unit suggestions, ETA computations, and lifecycle state transitions. |
| Main Database | Cloud Firestore | Document database for structured entities (Users, Medical Profiles, Incident Records, Fleet Metadata). |
| Realtime Telemetry | Firebase Realtime Database (RTDB) | High-frequency low-cost GPS telemetry updates for active ambulances. |
| Authentication & RBAC | Firebase Auth | Identity management enforcing RBAC using custom user claims. |
| Push Notifications | Firebase Cloud Messaging (FCM) | Dispatch alerts to crew members and tracking state updates to patients. |
| Mapping & Routing | Google Maps SDK & JS API | Map rendering, route polyline visualization, and location tracking. |

## 4. Key Data Entities & Data Flow Overview

```
[Patient Request] --(Creates)--> [Incident Document (Firestore)]
                                          |
                                (Cloud Function Trigger)
                                          |
                                [Haversine Distance Engine]
                                          |
                                          v
[Realtime GPS (RTDB)] --------> [Nearest Unit Suggestion]
                                          |
                                          v
                               [Dispatcher Console (React)]
                                          |
                                  (Manual Assign)
                                          |
                                          v
[Patient Track Map] <--(FCM Push)-- [Crew Mobile App (Flutter)]
```

### Data Entities (Firestore & RTDB)

1. **Users Collection (Firestore):** `uid`, `role` (patient | dispatcher | crew | admin), `name`, `phone`, `medicalProfile` (bloodType, allergies, chronicConditions, emergencyContacts).
2. **Vehicles Collection (Firestore):** `vehicleId`, `plateNumber`, `status` (active | maintenance | retired), `assignedCrewUid`.
3. **Incidents Collection (Firestore):** `incidentId`, `patientUid` (optional), `pickupLocation` (lat, lng), `status` (pending | dispatched | enRoute | onScene | transporting | atHospital | resolved), `assignedVehicleId`, `timestamps`.
4. **Telemetry Node (Realtime DB):** `vehicleId: { latitude, longitude, heading, speed, lastUpdated }`.

## 5. Summary Baseline

| Component | Status | Locked Choice |
|---|---|---|
| Triage Strategy | Locked | Plain FIFO Request Queue |
| Dispatch Mode | Locked | Manual Decision with Automated Nearest-Unit Suggestion |
| Mobile Tech | Locked | Flutter |
| Web Dashboard Tech | Locked | React |
| Database & Realtime | Locked | Firestore (Data) + Realtime DB (GPS Telemetry) |
| Backend & Compute | Locked | Firebase Cloud Functions + FCM |