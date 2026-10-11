import 'dart:async';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/app_state.dart';
import '../core/mission_status.dart';
import '../core/tokens.dart';
import '../widgets/atoms.dart';
import 'mission_screen.dart';

/// Stage-3 flow (screen spec §5 + §6):
///   RequestFlowScreen — single screen, stacked steps, ≤2 taps to send
///   RequestQueuedScreen — FIFO wait (pending), full map states.

// ─────────────────────────────────────────────────────────────────────
// §5  Panic request flow
// ─────────────────────────────────────────────────────────────────────

class RequestFlowScreen extends StatefulWidget {
  final AppState state;
  const RequestFlowScreen({super.key, required this.state});

  @override
  State<RequestFlowScreen> createState() => _RequestFlowScreenState();
}

class _RequestFlowScreenState extends State<RequestFlowScreen> {
  static const _symptomOptions = [
    'Unconscious',
    'Chest pain',
    'Breathing',
    'Injury',
    'Other',
  ];

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _notes = TextEditingController();
  final _address = TextEditingController();
  final _mapController = MapController();

  final Set<String> _symptoms = {};
  bool _attachMedical = true;
  bool _sending = false;
  bool _editPin = false;
  bool _triedSubmit = false;
  late LatLng _pin = widget.state.userLocation;

  AppState get state => widget.state;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    _address.dispose();
    super.dispose();
  }

  bool get _needsManualAddress => !state.locationGranted;

  String? get _nameError =>
      _triedSubmit && !state.isAuthenticated && _name.text.trim().isEmpty
          ? "Enter a name so the crew knows who they're looking for."
          : null;

  String? get _phoneError {
    if (_triedSubmit && !state.isAuthenticated && _phone.text.trim().isEmpty) {
      return 'Enter a phone number so the crew can reach you.';
    }
    return null;
  }

  Future<void> _send() async {
    setState(() => _triedSubmit = true);
    if (_nameError != null || _phoneError != null) return;
    setState(() => _sending = true);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    state.triggerRequest(
      pickup: _pin,
      medicalAttached: state.isAuthenticated && _attachMedical,
      guestName: state.isAuthenticated ? null : _name.text.trim(),
      guestPhone: state.isAuthenticated ? null : _phone.text.trim(),
    );
    if (!mounted) return;
    setState(() => _sending = false);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
          builder: (_) => RequestQueuedScreen(state: state, pickup: _pin)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Request help'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: AbsorbPointer(
        absorbing: _sending, // inputs stay visible but disabled while sending
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (state.offline) ...[
              _offlineBanner(theme),
              gapH(12),
            ],
            _sectionTitle(theme, 'Where should we send help?'),
            gapH(8),
            _locationStep(theme),
            gapH(20),
            _sectionTitle(theme, 'Who needs help?'),
            gapH(8),
            if (state.isAuthenticated) _savedDetails(theme) else _guestFields(theme),
            gapH(20),
            _sectionTitle(theme, "What's happening?"),
            gapH(8),
            _symptomStep(theme),
            gapH(20),
            if (state.isAuthenticated) ...[
              _medicalStep(theme),
              gapH(20),
            ],
            _sendButton(),
            gapH(4),
            TextButton.icon(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Dispatch hotline'),
                  content: const Text(
                      '150 · Emergency medical hotline\nYour location is shared on this call.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
              icon: const Icon(Icons.phone_rounded, size: 18),
              label: const Text('Call dispatcher instead'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Step 1: location confirm (pin + address, spec §5.1) ───────────

  Widget _locationStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 180,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppColors.radiusMd),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _pin,
                  initialZoom: 15.5,
                  backgroundColor: theme.scaffoldBackgroundColor,
                  interactionOptions: InteractionOptions(
                    flags: _editPin
                        ? InteractiveFlag.none // finger drags the pin only
                        : InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate: kOsmTileUrl,
                    userAgentPackageName: 'com.ambulance.patient_app',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _pin,
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.place_rounded,
                            size: 40, color: AppColors.primary),
                      ),
                    ],
                  ),
                ],
              ),
              if (_editPin)
                Positioned.fill(
                  child: GestureDetector(
                    onPanUpdate: (d) => setState(() => _pin = _dragPinBy(
                        _pin, d.delta.dx, d.delta.dy, _mapController.camera.zoom)),
                    child: ColoredBox(
                      color: Colors.transparent,
                      child: Center(
                        child: Text(
                          'Drag to move your pin',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: AppColors.primary,
                            backgroundColor:
                                theme.colorScheme.surface.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        gapH(8),
        Row(
          children: [
            Expanded(
              child: Text(
                _needsManualAddress
                    ? 'Location is off — enter your address below.'
                    : _pin == state.userLocation
                        ? '12 Boulevard Moulay Youssef, Casablanca'
                        : '${_pin.latitude.toStringAsFixed(4)}, '
                            '${_pin.longitude.toStringAsFixed(4)} · address refreshed on send',
                style: theme.textTheme.bodySmall,
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () => setState(() => _editPin = !_editPin),
              child: Text(_editPin ? 'Done' : 'Edit pin'),
            ),
          ],
        ),
        if (_needsManualAddress) ...[
          TextField(
            controller: _address,
            decoration: const InputDecoration(
              labelText: 'Address or landmark',
              helperText: 'Tell the crew where to find you.',
            ),
          ),
        ],
      ],
    );
  }

  // ── Step 2: who needs help (spec §5.2) ─────────────────────────────

  Widget _guestFields(ThemeData theme) => Column(
        children: [
          TextField(
            controller: _name,
            keyboardType: TextInputType.name,
            decoration: InputDecoration(
              labelText: 'Name',
              errorText: _nameError,
            ),
          ),
          gapH(12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Phone',
              helperText: 'So the crew can reach you.',
              errorText: _phoneError,
            ),
          ),
        ],
      );

  Widget _savedDetails(ThemeData theme) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded,
                size: 18, color: theme.colorScheme.primary),
            gapW(10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Using your saved details',
                      style: theme.textTheme.labelLarge),
                  gapH(2),
                  Text(
                    '${AppState.userDemoName} · ${AppState.userDemoPhone}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  // ── Step 3: what's happening (optional, spec §5.3) ─────────────────

  Widget _symptomStep(ThemeData theme) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in _symptomOptions)
                FilterChip(
                  label: Text(s),
                  selected: _symptoms.contains(s),
                  onSelected: (_) => setState(() => _symptoms.contains(s)
                      ? _symptoms.remove(s)
                      : _symptoms.add(s)),
                ),
            ],
          ),
          gapH(12),
          TextField(
            controller: _notes,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Anything else the crew should know? (optional)',
            ),
          ),
        ],
      );

  // ── Step 4: medical attach (spec §5.4) ─────────────────────────────

  Widget _medicalStep(ThemeData theme) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Attach medical profile'),
            subtitle:
                const Text('This request will include your medical profile.'),
            value: _attachMedical,
            onChanged: (v) => setState(() => _attachMedical = v),
          ),
          if (_attachMedical) ...[
            MedicalCard(profile: state.medicalProfile),
            gapH(4),
          ],
        ],
      );

  // ── Step 5: send (spec §5.5) ───────────────────────────────────────

  Widget _sendButton() => SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.danger,
            minimumSize: const Size.fromHeight(AppColors.panicSize),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppColors.radiusLg)),
          ),
          onPressed: _sending ? null : _send,
          icon: _sending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.emergency_rounded),
          label: Text(
            _sending
                ? 'Sending…'
                : state.offline
                    ? 'Save request'
                    : 'Send request',
            style:
                const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
        ),
      );

  Widget _offlineBanner(ThemeData theme) {
    final amber = context.statusColor(MissionStatus.pending);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppColors.radiusMd),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 18, color: amber),
          gapW(10),
          Expanded(
            child: Text(
              "No connection — we'll send your request as soon as you're back online.",
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String title) =>
      Text(title, style: theme.textTheme.headlineMedium);
}

// ─────────────────────────────────────────────────────────────────────
// §6  Waiting for dispatch (status: pending)
// ─────────────────────────────────────────────────────────────────────

class RequestQueuedScreen extends StatefulWidget {
  final AppState state;
  final LatLng? pickup;
  const RequestQueuedScreen({super.key, required this.state, this.pickup});

  @override
  State<RequestQueuedScreen> createState() => _RequestQueuedScreenState();
}

class _RequestQueuedScreenState extends State<RequestQueuedScreen> {
  Timer? _elapsedTimer;
  Timer? _bootTimer;
  int _seconds = 0;
  bool _booting = true;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
    // Optimistic "Request sent" + skeletons for the first moments (§6 loading).
    _bootTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _booting = false);
    });
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _bootTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final inc = state.activeIncident;

        // Write rejected — full-width danger card (spec §6 error).
        if (state.sendFailed && inc == null) return _failedView(context);

        if (inc == null) {
          // Cancelled elsewhere — return to the fleet.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) Navigator.of(context).pop();
          });
          return const SizedBox.shrink();
        }
        // Dispatch reached → hand off to live mission.
        if (inc.status != MissionStatus.pending) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => MissionScreen(state: state)),
              );
            }
          });
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: AppBar(
            // Close minimizes to the app shell — it never cancels (spec §6).
            title: const Text('Request sent'),
            leading: IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _statusBand(theme),
              if (state.offline) ...[
                gapH(12),
                Text('Waiting for connection — your request will send automatically.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.primary)),
              ],
              gapH(20),
              Text('Position ${inc.queuePosition} of 5',
                  style: theme.textTheme.headlineLarge),
              gapH(4),
              Text('Elapsed', style: theme.textTheme.labelSmall),
              MonoEta(elapsed: Duration(seconds: _seconds), size: 32),
              gapH(16),
              if (_booting) ...[
                const SkeletonBlock(width: double.infinity, height: 180),
                gapH(12),
                const SkeletonBlock(width: double.infinity, height: 56),
              ] else ...[
                _queueMap(theme, inc.pickup),
                gapH(12),
                _dispatcherCard(theme),
                gapH(12),
                Center(
                  child: Text('Keep this screen open',
                      style: theme.textTheme.labelSmall),
                ),
              ],
              gapH(20),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Dispatch hotline'),
                    content: const Text(
                        '150 · Emergency medical hotline\nYour location is shared on this call.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
                icon: const Icon(Icons.phone_rounded, size: 18),
                label: const Text('Call dispatcher'),
              ),
              gapH(4),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                onPressed: () => _confirmCancel(context),
                child: const Text('Cancel request'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statusBand(ThemeData theme) {
    final amber = context.statusColor(MissionStatus.pending);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppColors.radiusMd),
      ),
      child: Row(
        children: [
          Icon(Icons.hourglass_top_rounded, size: 20, color: amber),
          gapW(10),
          Text('In the queue', style: theme.textTheme.bodyLarge),
          const Spacer(),
          const StatusChip(status: MissionStatus.pending),
        ],
      ),
    );
  }

  Widget _queueMap(ThemeData theme, LatLng pickup) => Container(
        height: 180,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: pickup,
            initialZoom: 15,
            backgroundColor: theme.scaffoldBackgroundColor,
            interactionOptions:
                const InteractionOptions(flags: InteractiveFlag.none),
          ),
          children: [
            TileLayer(
              urlTemplate: kOsmTileUrl,
              userAgentPackageName: 'com.ambulance.patient_app',
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: pickup,
                  width: 48,
                  height: 48,
                  child: const _PulsingPin(),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _dispatcherCard(ThemeData theme) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(Icons.support_agent_rounded,
                size: 22, color: theme.colorScheme.primary),
            gapW(12),
            Expanded(
              child: Text('A dispatcher is reviewing your request',
                  style: theme.textTheme.bodyMedium),
            ),
          ],
        ),
      );

  Widget _failedView(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Request failed')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.dangerSurface,
                border: Border.all(color: AppColors.dangerBorder),
                borderRadius: BorderRadius.circular(AppColors.radiusMd),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: AppColors.danger),
                      gapW(10),
                      Expanded(
                        child: Text('Request failed',
                            style: theme.textTheme.bodyLarge?.copyWith(
                                color: AppColors.danger,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  gapH(8),
                  Text(
                    'The dispatcher never received it. Check your connection '
                    'and try again, or call 150 directly.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            gapH(20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
                onPressed: () => state.triggerRequest(
                    pickup: widget.pickup,
                    medicalAttached: state.lastRequestMedical),
                child: const Text('Try again'),
              ),
            ),
            gapH(8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Dispatch hotline'),
                    content: const Text(
                        '150 · Emergency medical hotline\nYour location is shared on this call.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
                icon: const Icon(Icons.phone_rounded, size: 18),
                label: const Text('Call dispatcher'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmCancel(BuildContext context) => showDialog<void>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Cancel this request?'),
          content: const Text(
              "A crew has not been assigned yet. If you still need help, "
              "you'll have to send a new request."),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Keep request'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                state.cancelRequest();
              },
              child: const Text('Cancel request'),
            ),
          ],
        ),
  );
}

// ── Pin drag math ──────────────────────────────────────────────────────
// flutter_map 7 exposes no screen→LatLng API, so "Edit pin" applies the
// Web-Mercator screen-delta conversion directly (zoom is fixed while editing).

LatLng _dragPinBy(LatLng pin, double dx, double dy, double zoom) {
  final worldPx = 256.0 * math.pow(2.0, zoom);
  final dLng = dx * 360.0 / worldPx;
  final newLat = _mercYToLat(_latToMercY(pin.latitude, worldPx) + dy, worldPx);
  return LatLng(newLat, pin.longitude + dLng);
}

double _latToMercY(double lat, double worldPx) {
  final r = lat * math.pi / 180.0;
  return (0.5 - math.log(math.tan(r) + 1 / math.cos(r)) / (2 * math.pi)) *
      worldPx;
}

double _mercYToLat(double y, double worldPx) {
  final n = math.pi * (1.0 - 2.0 * y / worldPx);
  // dart:math has no sinh — expanded by hand.
  final sh = (math.exp(n) - math.exp(-n)) / 2;
  return math.atan(sh) * 180.0 / math.pi;
}

/// Your pin pulsing on the queue map — skipped under reduced motion (§6).
class _PulsingPin extends StatefulWidget {
  const _PulsingPin();

  @override
  State<_PulsingPin> createState() => _PulsingPinState();
}

class _PulsingPinState extends State<_PulsingPin>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Stack(
      alignment: Alignment.center,
      children: [
        if (!reduce)
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              final t = Curves.easeOut.transform(_pulse.value);
              return Container(
                width: 24 + t * 28,
                height: 24 + t * 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.22 - t * 0.22),
                ),
              );
            },
          ),
        Container(
          width: 18,
          height: 18,
          decoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}
