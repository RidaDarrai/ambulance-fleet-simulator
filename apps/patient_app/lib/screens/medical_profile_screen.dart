import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/mission_status.dart';
import '../core/tokens.dart';
import '../theme/app_theme.dart';
import '../widgets/atoms.dart';

/// Medical profile (screen spec §11): summary card with 4 tappable rows,
/// each opening a section editor.
///
/// States: loading (skeleton rows) · empty (first-use "Add your medical
/// info") · error (save failed, form kept) · offline (rows show "Pending
/// sync"). Privacy line: "Shared only when you send a request".
class MedicalProfileScreen extends StatelessWidget {
  final AppState state;
  const MedicalProfileScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Medical profile')),
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final p = state.medicalProfile;
          if (state.medicalLoading) return _loading(theme);
          if (p.isEmpty) return _empty(context, theme);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (p.incomplete) ...[
                // Incompleteness nudge (spec §11).
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.medicalSurface,
                    border: Border.all(color: AppColors.medicalBorder),
                    borderRadius: BorderRadius.circular(AppColors.radiusMd),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.bloodtype_rounded,
                          size: 20, color: AppColors.primary),
                      gapW(10),
                      Expanded(
                        child: Text(
                          'Add your blood type — crews use it first.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => BloodTypeEditor(state: state)),
                        ),
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                ),
                gapH(12),
              ],
              // Summary card (medical.surface / medical.border).
              Container(
                decoration: BoxDecoration(
                  color: AppColors.medicalSurface,
                  border: Border.all(color: AppColors.medicalBorder),
                  borderRadius: BorderRadius.circular(AppColors.radiusMd),
                ),
                child: Column(
                  children: [
                    _SummaryRow(
                      state: state,
                      label: 'Blood type',
                      value: p.bloodType ?? 'Not added',
                      onTap: () => _push(BloodTypeEditor(state: state), context),
                    ),
                    _SummaryRow(
                      state: state,
                      label: 'Allergies',
                      value: p.allergies.isEmpty
                          ? 'Not added'
                          : p.allergies.join(', '),
                      onTap: () => _push(
                          ListEditor(
                              state: state,
                              title: 'Allergies',
                              items: p.allergies,
                              suggestions: const [
                                'Penicillin',
                                'Peanuts',
                                'Latex',
                                'Iodine',
                                'Aspirin',
                              ]),
                          context),
                    ),
                    _SummaryRow(
                      state: state,
                      label: 'Chronic conditions',
                      value: p.conditions.isEmpty
                          ? 'Not added'
                          : p.conditions.join(', '),
                      onTap: () => _push(
                          ListEditor(
                              state: state,
                              title: 'Chronic conditions',
                              items: p.conditions,
                              suggestions: const [
                                'Asthma',
                                'Diabetes',
                                'Hypertension',
                                'Heart condition',
                                'Epilepsy',
                              ]),
                          context),
                    ),
                    _SummaryRow(
                      state: state,
                      label: 'Emergency contacts',
                      value: p.contacts.isEmpty
                          ? 'Not added'
                          : '${p.contacts.length} saved',
                      showChevron: true,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => ContactsScreen(state: state)),
                      ),
                    ),
                  ],
                ),
              ),
              gapH(12),
              Row(
                children: [
                  Icon(Icons.lock_outline_rounded,
                      size: 14, color: theme.colorScheme.outline),
                  gapW(6),
                  Expanded(
                    child: Text('Shared only when you send a request',
                        style: theme.textTheme.labelSmall),
                  ),
                  Text(_ago(p.lastUpdated), style: etaDisplayStyle(size: 12)),
                ],
              ),
              gapH(24),
              TextButton(
                onPressed: () => state.resetMedicalProfile(),
                child: const Text('Reset profile (demo)'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _push(Widget screen, BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  Widget _loading(ThemeData theme) => ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          SkeletonBlock(width: double.infinity, height: 56),
          SizedBox(height: 8),
          SkeletonBlock(width: double.infinity, height: 56),
          SizedBox(height: 8),
          SkeletonBlock(width: double.infinity, height: 56),
          SizedBox(height: 8),
          SkeletonBlock(width: double.infinity, height: 56),
        ],
      );

  Widget _empty(BuildContext context, ThemeData theme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.medical_information_outlined,
                  size: 56,
                  color: theme.colorScheme.primary.withValues(alpha: 0.7)),
              gapH(16),
              Text('Add your medical info',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center),
              gapH(8),
              Text('Crews see this the moment you request help.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center),
              gapH(20),
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => BloodTypeEditor(state: state)),
                ),
                child: const Text('Add blood type'),
              ),
            ],
          ),
        ),
      );

  static String agoLabel(DateTime t) => _ago(t);

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inDays >= 1) {
      return '${d.inDays} d ago';
    }
    if (d.inHours >= 1) return '${d.inHours} h ago';
    return 'just now';
  }
}

class _SummaryRow extends StatelessWidget {
  final AppState state;
  final String label;
  final String value;
  final VoidCallback onTap;
  final bool showChevron;

  const _SummaryRow({
    required this.state,
    required this.label,
    required this.value,
    required this.onTap,
    this.showChevron = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = state.medicalProfile.pendingSync;
    final notAdded = value == 'Not added';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            SizedBox(
              width: 130,
              child: Text(label, style: theme.textTheme.labelLarge),
            ),
            Expanded(
              child: Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: notAdded ? theme.colorScheme.outline : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (pending) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: context.statusColor(MissionStatus.pending)
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppColors.radiusFull),
                ),
                child: Text('Pending sync',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: context.statusColor(MissionStatus.pending))),
              ),
              gapW(8),
            ],
            if (showChevron)
              Icon(Icons.chevron_right_rounded,
                  size: 20, color: theme.colorScheme.outline),
          ],
        ),
      ),
    );
  }
}

// ── Blood type editor — single select, no pre-tick (spec §11) ─────────

class BloodTypeEditor extends StatefulWidget {
  final AppState state;
  const BloodTypeEditor({super.key, required this.state});

  @override
  State<BloodTypeEditor> createState() => _BloodTypeEditorState();
}

class _BloodTypeEditorState extends State<BloodTypeEditor> {
  static const _types = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

  String? _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.state.medicalProfile.bloodType;
  }

  Future<void> _save() async {
    if (_selected == null) return; // validation handled in build
    setState(() => _saving = true);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final ok = widget.state.setBloodType(_selected);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved ✓')));
      Navigator.of(context).pop();
    } else {
      // §11 error — form kept, inline retry.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("We couldn't save your changes. Tap Save again.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final picked = _selected != null;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Blood type')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Pick the blood type from the list.',
                    style: theme.textTheme.bodySmall),
                gapH(8),
                RadioGroup<String>(
                  groupValue: _selected,
                  onChanged: (v) => setState(() => _selected = v),
                  child: Column(
                    children: [
                      for (final t in _types)
                        RadioListTile<String>(
                          value: t,
                          title: Text(t, style: theme.textTheme.bodyLarge),
                          contentPadding: EdgeInsets.zero,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                  onPressed: picked && !_saving ? _save : null,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Allergies / conditions editor — chips + suggestions (spec §11) ────

class ListEditor extends StatefulWidget {
  final AppState state;
  final String title;
  final List<String> items;
  final List<String> suggestions;
  const ListEditor({
    super.key,
    required this.state,
    required this.title,
    required this.items,
    required this.suggestions,
  });

  @override
  State<ListEditor> createState() => _ListEditorState();
}

class _ListEditorState extends State<ListEditor> {
  late final List<String> _items = [...widget.items];
  final _controller = TextEditingController();
  bool _saving = false;
  bool _dirty = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add(String raw) {
    final v = raw.trim();
    if (v.isEmpty || _items.contains(v)) return;
    setState(() {
      _items.add(v);
      _dirty = true;
      _controller.clear();
    });
  }

  void _remove(String v) => setState(() {
        _items.remove(v);
        _dirty = true;
      });

  Future<void> _save() async {
    setState(() => _saving = true);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final ok = widget.title == 'Allergies'
        ? widget.state.setAllergies(_items)
        : widget.state.setConditions(_items);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved ✓')));
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("We couldn't save your changes. Tap Save again.")));
    }
  }

  /// Back with unsaved input → "Discard changes?" (spec §11 gestures).
  Future<void> _confirmBack() async {
    if (!_dirty) return Navigator.of(context).pop();
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: Text('Your edits to ${widget.title.toLowerCase()} '
            "haven't been saved."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final available = widget.suggestions.where((s) => !_items.contains(s));
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmBack();
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(widget.title),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _confirmBack,
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Current entries as removable chips.
            if (_items.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in _items)
                    Chip(
                      label: Text(item),
                      deleteIcon: const Icon(Icons.close_rounded, size: 16),
                      onDeleted: () => _remove(item),
                      side: BorderSide(
                          color: theme.colorScheme.outlineVariant),
                    ),
                ],
              ),
              gapH(16),
            ],
            TextField(
              controller: _controller,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Add ${widget.title.toLowerCase()}',
                hintText: 'Type and tap +',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add_circle_rounded),
                  onPressed: () => _add(_controller.text),
                ),
              ),
              onSubmitted: _add,
            ),
            if (available.isNotEmpty) ...[
              gapH(16),
              Text('Suggestions', style: theme.textTheme.labelLarge),
              gapH(8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in available)
                    ActionChip(
                      label: Text(s),
                      onPressed: () => _add(s),
                    ),
                ],
              ),
            ],
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Contacts (screen spec §12) ─────────────────────────────────────────

class ContactsScreen extends StatelessWidget {
  final AppState state;
  const ContactsScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Emergency contacts')),
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final contacts = state.medicalProfile.contacts;
          final full = contacts.length >= 5;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (contacts.isEmpty)
                EmptyStateBox(
                  icon: Icons.people_outline_rounded,
                  title: 'No emergency contacts yet',
                  message:
                      "Add someone we should call if you can't answer.",
                )
              else ...[
                for (final c in contacts) ...[
                  _ContactTile(state: state, contact: c),
                  gapH(8),
                ],
              ],
              if (full) ...[
                gapH(4),
                Text('You can add up to 5 contacts.',
                    style: theme.textTheme.labelSmall),
              ],
              gapH(12),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
                onPressed: full
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => ContactForm(
                                  state: state, contact: null)),
                        ),
                icon: const Icon(Icons.person_add_rounded, size: 18),
                label: const Text('Add contact'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  final AppState state;
  final EmergencyContact contact;
  const _ContactTile({required this.state, required this.contact});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initials = contact.name
        .split(' ')
        .map((w) => w.isEmpty ? '' : w[0])
        .take(2)
        .join()
        .toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppColors.radiusMd),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Text(initials,
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.primary)),
          ),
          gapW(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(contact.name, style: theme.textTheme.bodyLarge),
                Text('${contact.relationship} · ${contact.phone}',
                    style: theme.textTheme.labelSmall),
              ],
            ),
          ),
          // Tap phone → dial immediately (spec §12).
          IconButton(
            tooltip: 'Call ${contact.name}',
            icon: Icon(Icons.phone_rounded,
                size: 20, color: theme.colorScheme.primary),
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Dialing ${contact.phone}…')),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, size: 20),
            onSelected: (v) {
              if (v == 'edit') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) =>
                          ContactForm(state: state, contact: contact)),
                );
              } else {
                _confirmRemove(context);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'remove', child: Text('Remove')),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmRemove(BuildContext context) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Remove ${contact.name.split(' ').first}?'),
          content: Text(
              '${contact.name.split(' ').first} will no longer be called '
              'during an emergency.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              onPressed: () {
                Navigator.of(ctx).pop();
                state.removeContact(contact);
              },
              child: const Text('Remove'),
            ),
          ],
        ),
  );
}

/// Add / edit a contact — ≤3 fields, save fixed bottom (spec §12).
class ContactForm extends StatefulWidget {
  final AppState state;
  final EmergencyContact? contact; // null = add
  const ContactForm({super.key, required this.state, required this.contact});

  @override
  State<ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends State<ContactForm> {
  late final _name = TextEditingController(text: widget.contact?.name);
  late final _relationship =
      TextEditingController(text: widget.contact?.relationship);
  late final _phone = TextEditingController(text: widget.contact?.phone);
  bool _triedSubmit = false;
  bool _saving = false;

  bool get _isEdit => widget.contact != null;

  @override
  void dispose() {
    _name.dispose();
    _relationship.dispose();
    _phone.dispose();
    super.dispose();
  }

  String? get _nameError =>
      _triedSubmit && _name.text.trim().isEmpty ? 'Enter a full name.' : null;

  String? get _phoneError {
    if (!_triedSubmit) return null;
    final v = _phone.text.trim();
    if (v.isEmpty) return 'Enter a phone number.';
    if (v.replaceAll(RegExp(r'[^0-9]'), '').length < 9) {
      return 'That phone number looks too short.';
    }
    return null;
  }

  Future<void> _save() async {
    setState(() => _triedSubmit = true);
    if (_nameError != null || _phoneError != null) return;
    setState(() => _saving = true);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final ok = _isEdit
        ? widget.state.updateContact(widget.contact!)
        : widget.state.addContact(EmergencyContact(
            id: 'c${DateTime.now().millisecondsSinceEpoch}',
            name: _name.text.trim(),
            relationship: _relationship.text.trim().isEmpty
                ? 'Contact'
                : _relationship.text.trim(),
            phone: _phone.text.trim(),
          ));
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved ✓')));
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("We couldn't save your contact. Tap Save again.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: Text(_isEdit ? 'Edit contact' : 'Add contact')),
      body: AbsorbPointer(
        absorbing: _saving,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _name,
              keyboardType: TextInputType.name,
              decoration: InputDecoration(
                labelText: 'Full name',
                errorText: _nameError,
              ),
            ),
            gapH(12),
            TextField(
              controller: _relationship,
              decoration: const InputDecoration(
                labelText: 'Relationship',
                helperText: 'e.g. Sister, Doctor, Neighbor',
              ),
            ),
            gapH(12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Phone number',
                errorText: _phoneError,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Save'),
            ),
          ),
        ),
      ),
    );
  }
}
