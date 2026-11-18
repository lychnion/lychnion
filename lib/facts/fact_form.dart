import 'package:flutter/material.dart';

import '../app/lang.dart';
import '../l10n/app_localizations.dart';
import 'fact.dart';

/// Who enters facts on this device, e.g. the shelter computer's name.
/// Facts entered here carry it as their source name.
class FactEditor {
  const FactEditor({required this.sourceName});
  final String sourceName;
}

/// A choice in the form: the stored value and its label.
typedef FactChoice = ({String value, String label});

List<FactChoice> shelterChoices(AppLocalizations l) => [
  for (final s in ShelterStatus.values)
    (value: s.key, label: l.shelterStatus(s.key)),
];

/// How long a fact stays valid before it must be confirmed again.
const _lifetimes = [1, 3, 6, 24];

/// Opens the form and returns the new fact, or null when cancelled.
///
/// With [choices] the value is picked from them; without, it is typed
/// (warnings). [current] is the fact now shown for this topic: the form then
/// offers to clear it (for kinds other than shelter status).
Future<Fact?> showFactForm(
  BuildContext context, {
  required FactEditor editor,
  required FactKind kind,
  required String subject,
  required String title,
  List<FactChoice>? choices,
  Fact? current,
}) => showModalBottomSheet<Fact>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _FactForm(
    editor: editor,
    kind: kind,
    subject: subject,
    title: title,
    choices: choices,
    current: current,
  ),
);

class _FactForm extends StatefulWidget {
  const _FactForm({
    required this.editor,
    required this.kind,
    required this.subject,
    required this.title,
    this.choices,
    this.current,
  });

  final FactEditor editor;
  final FactKind kind;
  final String subject;
  final String title;
  final List<FactChoice>? choices;
  final Fact? current;

  @override
  State<_FactForm> createState() => _FactFormState();
}

class _FactFormState extends State<_FactForm> {
  late String? _value = widget.choices == null
      ? null
      : (widget.current?.value ?? widget.choices!.first.value);
  final _text = TextEditingController();
  final _note = TextEditingController();
  int _hours = 3;
  SourceType _source = SourceType.official;

  @override
  void dispose() {
    _text.dispose();
    _note.dispose();
    super.dispose();
  }

  Fact _make(String value) {
    final now = DateTime.now();
    return Fact(
      kind: widget.kind,
      subject: widget.subject,
      // The radio format uses | and ; as separators.
      value: value.replaceAll(RegExp('[|;]'), ' ').trim(),
      observedAt: now,
      expiresAt: now.add(Duration(hours: _hours)),
      sourceType: _source,
      sourceName: widget.editor.sourceName,
      note: _note.text.replaceAll(RegExp('[|;]'), ' ').trim(),
    );
  }

  String? get _chosen => widget.choices == null ? _text.text.trim() : _value;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final cur = widget.current;
    final canClear = cur != null && widget.kind != FactKind.shelterStatus;
    final chosen = _chosen;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          if (widget.choices case final choices?)
            Wrap(
              spacing: 6,
              children: [
                for (final c in choices)
                  ChoiceChip(
                    label: Text(c.label),
                    selected: _value == c.value,
                    onSelected: (_) => setState(() => _value = c.value),
                  ),
              ],
            )
          else
            TextField(
              controller: _text,
              autofocus: true,
              decoration: InputDecoration(labelText: l.factFormWarning),
              onChanged: (_) => setState(() {}),
            ),
          TextField(
            controller: _note,
            maxLength: 40,
            decoration: InputDecoration(labelText: l.factFormNote),
          ),
          Text(l.factFormValidFor, style: theme.textTheme.labelMedium),
          Wrap(
            spacing: 6,
            children: [
              for (final h in _lifetimes)
                ChoiceChip(
                  label: Text(l.factFormHours('$h')),
                  selected: _hours == h,
                  onSelected: (_) => setState(() => _hours = h),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SegmentedButton<SourceType>(
            segments: [
              ButtonSegment(
                value: SourceType.official,
                label: Text(l.factFormOfficial),
              ),
              ButtonSegment(
                value: SourceType.citizen,
                label: Text(l.factFormResident),
              ),
            ],
            selected: {_source},
            onSelectionChanged: (s) => setState(() => _source = s.first),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (canClear)
                TextButton(
                  onPressed: () => Navigator.pop(context, _make(Fact.cleared)),
                  child: Text(l.factFormClear),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l.cancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: chosen == null || chosen.isEmpty
                    ? null
                    : () => Navigator.pop(context, _make(chosen)),
                child: Text(l.save),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
