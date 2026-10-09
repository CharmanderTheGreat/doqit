import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/note_color.dart';
import '../../core/notifications/notification_service.dart';
import '../../data/providers.dart';

class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({super.key, required this.noteId, this.isNew = false});

  final int noteId;
  final bool isNew;

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  final _title = TextEditingController();
  final _itemCtrl = TextEditingController();
  final _itemFocus = FocusNode();
  bool _loaded = false;

  @override
  void dispose() {
    _title.dispose();
    _itemCtrl.dispose();
    _itemFocus.dispose();
    super.dispose();
  }

  Future<void> _addItem() async {
    final text = _itemCtrl.text.trim();
    if (text.isEmpty) return;
    _itemCtrl.clear();
    await ref.read(databaseProvider).addItem(widget.noteId, text);
    if (mounted) _itemFocus.requestFocus();
  }

  Future<void> _editItem(ChecklistItem item) async {
    final ctrl = TextEditingController(text: item.content);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('edit item'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.done,
          minLines: 1,
          maxLines: 6,
          decoration: const InputDecoration(hintText: 'item'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    final text = result?.trim() ?? '';
    if (text.isEmpty || text == item.content) return;
    await ref.read(databaseProvider).editItem(item.id, text);
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('delete note?'),
        content: const Text('this cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('delete'),
          ),
        ],
      ),
    );
        if (ok != true || !mounted) return;
    await NotificationService.instance.cancel(widget.noteId);
    await ref.read(databaseProvider).deleteNote(widget.noteId);
    if (mounted) Navigator.pop(context);
  }

    void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _fmt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _pickReminder(Note note) async {
    final now = DateTime.now();
    final existing = note.reminderAt;
    final initial = existing != null && existing.isAfter(now)
        ? existing
        : now.add(const Duration(hours: 1));

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;

    final when =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (!when.isAfter(DateTime.now())) {
      _toast('pick a time in the future');
      return;
    }

    final service = NotificationService.instance;
    if (!await service.requestPermission()) {
      _toast('notifications are blocked, enable them in system settings');
      return;
    }
    final ok = await service.schedule(
      noteId: note.id,
      title: note.title,
      when: when,
    );
    if (!ok) {
      _toast('could not schedule the reminder');
      return;
    }
    await ref.read(databaseProvider).setReminder(note.id, when);
  }

  Future<void> _clearReminder(Note note) async {
    await NotificationService.instance.cancel(note.id);
    await ref.read(databaseProvider).setReminder(note.id, null);
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.read(databaseProvider);
    final data = ref.watch(noteProvider(widget.noteId)).value;
    if (data == null) return const Scaffold();

    if (!_loaded) {
      _title.text = data.note.title;
      _loaded = true;
    }
    final note = data.note;

    return PopScope(
            onPopInvokedWithResult: (didPop, _) {
        if (!didPop) return;
        db.deleteIfEmpty(widget.noteId).then((deleted) {
          if (deleted) {
            NotificationService.instance.cancel(widget.noteId);
            return;
          }
          // Refresh the notification so it shows the latest title.
          final r = note.reminderAt;
          if (r != null &&
              r.isAfter(DateTime.now()) &&
              note.title.trim().isNotEmpty) {
            NotificationService.instance.schedule(
              noteId: note.id,
              title: note.title,
              when: r,
            );
          }
        });
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('~/edit \$'),
          actions: [
            IconButton(
              tooltip: note.isPinned ? 'unpin' : 'pin',
              icon: Icon(
                note.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              ),
              onPressed: () => db.setPinned(note.id, !note.isPinned),
            ),
            IconButton(
              tooltip: note.isArchived ? 'unarchive' : 'archive',
              icon: Icon(
                note.isArchived
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined,
              ),
                            onPressed: () async {
                if (!note.isArchived) {
                  // Archived notes should not ring.
                  await NotificationService.instance.cancel(note.id);
                  await db.setReminder(note.id, null);
                }
                await db.setArchived(note.id, !note.isArchived);
                if (context.mounted) Navigator.pop(context);
              },
            ),
            IconButton(
              tooltip: 'delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDelete,
            ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _title,
                autofocus: widget.isNew,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.next,
                minLines: 1,
                maxLines: 3,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                  hintText: 'title',
                  border: InputBorder.none,
                ),
                onChanged: (v) => db.setTitle(note.id, v),
                onSubmitted: (_) => _itemFocus.requestFocus(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final c in NoteColor.values)
                    GestureDetector(
                      onTap: () => db.setColor(note.id, c),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: note.colorTag == c
                              ? c.color
                              : Colors.transparent,
                          border: Border.all(color: c.color),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          c.label,
                          style: TextStyle(
                            fontSize: 12,
                            color: note.colorTag == c ? Palette.bg : c.color,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
                        Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => _pickReminder(note),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        note.reminderAt == null
                            ? '+ add reminder'
                            : '@ ${_fmt(note.reminderAt!)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: note.reminderAt == null ||
                                  !note.reminderAt!.isAfter(DateTime.now())
                              ? Palette.dim
                              : Palette.green,
                        ),
                      ),
                    ),
                  ),
                  if (note.reminderAt != null)
                    InkWell(
                      onTap: () => _clearReminder(note),
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.close, size: 14, color: Palette.dim),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            const Divider(height: 1),
            Expanded(
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                itemCount: data.items.length,
                proxyDecorator: (child, index, animation) =>
                    Material(color: Palette.surface, child: child),
                onReorder: (oldIndex, newIndex) {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final list = [...data.items];
                  final moved = list.removeAt(oldIndex);
                  list.insert(newIndex, moved);
                  db.reorderItems(note.id, list);
                },
                itemBuilder: (context, i) {
                  final item = data.items[i];
                  return Dismissible(
                    key: ValueKey(item.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: Palette.danger,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 16),
                      child: const Icon(Icons.delete_outline),
                    ),
                    onDismissed: (_) => db.deleteItem(item.id),
                    child: Row(
                      children: [
                        InkWell(
                          onTap: () => db.toggleItem(item),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                            child: Text(
                              item.isDone ? '[x]' : '[ ]',
                              style: TextStyle(
                                color: item.isDone
                                    ? note.colorTag.color
                                    : Palette.dim,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () => _editItem(item),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                item.content,
                                style: TextStyle(
                                  color: item.isDone
                                      ? Palette.dim
                                      : Palette.text,
                                  decoration: item.isDone
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: const Padding(
                            padding: EdgeInsets.all(12),
                            child: Icon(
                              Icons.drag_handle,
                              size: 18,
                              color: Palette.dim,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 24, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 14),
                      child: Text('> ', style: TextStyle(color: Palette.green)),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _itemCtrl,
                        focusNode: _itemFocus,
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.done,
                        minLines: 1,
                        maxLines: 5,
                        scrollPadding: const EdgeInsets.only(bottom: 80),
                        decoration: const InputDecoration(
                          hintText: 'add item...',
                          border: InputBorder.none,
                        ),
                        onEditingComplete: _addItem,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}