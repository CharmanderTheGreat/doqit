import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/note_color.dart';
import '../../data/providers.dart';
import 'note_card.dart';
import 'note_editor_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _archived = false;
  NoteColor? _filter;

  Future<void> _newNote() async {
    final id = await ref.read(databaseProvider).createNote();
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(noteId: id, isNew: true),
      ),
    );
  }

  void _open(int id) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notes =
        ref.watch(_archived ? archivedNotesProvider : activeNotesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_archived ? '~/archive \$' : '~/notes \$'),
        actions: [
          IconButton(
            tooltip: _archived ? 'notes' : 'archive',
            icon: Icon(
              _archived ? Icons.notes : Icons.inventory_2_outlined,
            ),
            onPressed: () => setState(() => _archived = !_archived),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _FilterChip(
                  label: 'all',
                  color: Palette.green,
                  selected: _filter == null,
                  onTap: () => setState(() => _filter = null),
                ),
                for (final c in NoteColor.values)
                  _FilterChip(
                    label: c.label,
                    color: c.color,
                    selected: _filter == c,
                    onTap: () =>
                        setState(() => _filter = _filter == c ? null : c),
                  ),
              ],
            ),
          ),
          Expanded(
            child: notes.when(
              data: (list) {
                final shown = list
                    .where((n) => _filter == null || n.note.colorTag == _filter)
                    .toList();
                if (shown.isEmpty) {
                  final msg = _filter != null
                      ? 'no #${_filter!.label} notes'
                      : (_archived ? 'archive is empty' : 'empty. tap + to add');
                  return Center(child: Text(msg));
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: shown.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => NoteCard(
                    data: shown[i],
                    onTap: () => _open(shown[i].note.id),
                  ),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (e, _) => Center(child: Text('error: $e')),
            ),
          ),
        ],
      ),
      floatingActionButton: _archived
          ? null
          : FloatingActionButton(
              onPressed: _newNote,
              child: const Icon(Icons.add),
            ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: selected ? color : Colors.transparent,
              border: Border.all(color: color),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: selected ? Palette.bg : color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}