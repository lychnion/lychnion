import 'package:flutter/material.dart';

import 'fact.dart';

/// Who enters facts on this device, e.g. the shelter computer's name.
/// Facts entered here carry it as their source name.
class FactEditor {
  const FactEditor({required this.sourceName});
  final String sourceName;
}

/// A choice in the form: the stored value and its labels.
typedef FactChoice = ({String value, String ja, String en});

const shelterChoices = <FactChoice>[
  (value: 'open', ja: '開設', en: 'open'),
  (value: 'crowded', ja: '混雑', en: 'crowded'),
  (value: 'full', ja: '満員', en: 'full'),
  (value: 'closed', ja: '閉鎖', en: 'closed'),
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
  required bool en,
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
    en: en,
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
    required this.en,
    this.choices,
    this.current,
  });

  final FactEditor editor;
  final FactKind kind;
  final String subject;
  final String title;
  final bool en;
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

  bool get en => widget.en;

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
                    label: Text(en ? c.en : c.ja),
                    selected: _value == c.value,
                    onSelected: (_) => setState(() => _value = c.value),
                  ),
              ],
            )
          else
            TextField(
              controller: _text,
              autofocus: true,
              decoration: InputDecoration(
                labelText: en ? 'Warning (e.g. 津波警報)' : '警報・注意報（例：津波警報）',
              ),
              onChanged: (_) => setState(() {}),
            ),
          TextField(
            controller: _note,
            maxLength: 40,
            decoration: InputDecoration(
              labelText: en ? 'Note (optional)' : '補足（任意）',
            ),
          ),
          Text(en ? 'Valid for' : '有効時間', style: theme.textTheme.labelMedium),
          Wrap(
            spacing: 6,
            children: [
              for (final h in _lifetimes)
                ChoiceChip(
                  label: Text(en ? '$h h' : '$h時間'),
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
                label: Text(en ? 'Official (staff, city)' : '公式（運営者・市）'),
              ),
              ButtonSegment(
                value: SourceType.citizen,
                label: Text(en ? 'Resident report' : '住民の報告'),
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
                  child: Text(en ? 'No longer true' : '解除する'),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(en ? 'Cancel' : 'キャンセル'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: chosen == null || chosen.isEmpty
                    ? null
                    : () => Navigator.pop(context, _make(chosen)),
                child: Text(en ? 'Save' : '保存'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
