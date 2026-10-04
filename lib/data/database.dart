import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'note_color.dart';

part 'database.g.dart';

class Notes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withDefault(const Constant(''))();
  IntColumn get colorTag =>
      intEnum<NoteColor>().withDefault(const Constant(0))();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get reminderAt => dateTime().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
}

class ChecklistItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get noteId =>
      integer().references(Notes, #id, onDelete: KeyAction.cascade)();
  TextColumn get content => text()();
  BoolColumn get isDone => boolean().withDefault(const Constant(false))();
  IntColumn get position => integer().withDefault(const Constant(0))();
}

class NoteWithItems {
  NoteWithItems(this.note, this.items);

  final Note note;
  final List<ChecklistItem> items;

  int get doneCount => items.where((i) => i.isDone).length;
}

@DriftDatabase(tables: [Notes, ChecklistItems])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'doqit'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        beforeOpen: (details) async {
          // Kailangan ito para gumana ang cascade delete ng checklist items.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  // ---------- Queries ----------

  List<NoteWithItems> _group(List<TypedResult> rows) {
    final map = <int, NoteWithItems>{};
    for (final row in rows) {
      final note = row.readTable(notes);
      final item = row.readTableOrNull(checklistItems);
      final entry = map.putIfAbsent(note.id, () => NoteWithItems(note, []));
      if (item != null) entry.items.add(item);
    }
    return map.values.toList();
  }

  Stream<List<NoteWithItems>> watchNotes({required bool archived}) {
    final query = select(notes).join([
      leftOuterJoin(checklistItems, checklistItems.noteId.equalsExp(notes.id)),
    ])
      ..where(notes.isArchived.equals(archived))
      ..orderBy([
        OrderingTerm.desc(notes.isPinned),
        OrderingTerm.desc(notes.updatedAt),
        OrderingTerm.desc(notes.id),
        OrderingTerm.asc(checklistItems.position),
        OrderingTerm.asc(checklistItems.id),
      ]);
    return query.watch().map(_group);
  }

  Stream<NoteWithItems?> watchNote(int id) {
    final query = select(notes).join([
      leftOuterJoin(checklistItems, checklistItems.noteId.equalsExp(notes.id)),
    ])
      ..where(notes.id.equals(id))
      ..orderBy([
        OrderingTerm.asc(checklistItems.position),
        OrderingTerm.asc(checklistItems.id),
      ]);
    return query.watch().map((rows) {
      final list = _group(rows);
      return list.isEmpty ? null : list.first;
    });
  }

  // ---------- Notes ----------

  Future<int> createNote() => into(notes).insert(NotesCompanion.insert());

  Future<void> _updateNote(int id, NotesCompanion c) {
    return (update(notes)..where((t) => t.id.equals(id)))
        .write(c.copyWith(updatedAt: Value(DateTime.now())));
  }

  Future<void> setTitle(int id, String title) =>
      _updateNote(id, NotesCompanion(title: Value(title)));

  Future<void> setColor(int id, NoteColor color) =>
      _updateNote(id, NotesCompanion(colorTag: Value(color)));

  Future<void> setPinned(int id, bool value) =>
      _updateNote(id, NotesCompanion(isPinned: Value(value)));

  Future<void> setArchived(int id, bool value) =>
      _updateNote(id, NotesCompanion(isArchived: Value(value)));

  Future<void> deleteNote(int id) =>
      (delete(notes)..where((t) => t.id.equals(id))).go();

  /// Tinatanggal ang note kapag walang title at walang items.
  Future<void> deleteIfEmpty(int id) async {
    final note =
        await (select(notes)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (note == null || note.title.trim().isNotEmpty) return;
    final items = await (select(checklistItems)
          ..where((t) => t.noteId.equals(id)))
        .get();
    if (items.isEmpty) await deleteNote(id);
  }

  // ---------- Checklist items ----------

  Future<void> addItem(int noteId, String content) async {
    final maxPos = checklistItems.position.max();
    final row = await (selectOnly(checklistItems)
          ..addColumns([maxPos])
          ..where(checklistItems.noteId.equals(noteId)))
        .getSingle();
    final next = (row.read(maxPos) ?? -1) + 1;

    await into(checklistItems).insert(
      ChecklistItemsCompanion.insert(
        noteId: noteId,
        content: content,
        position: Value(next),
      ),
    );
    await _updateNote(noteId, const NotesCompanion());
  }

  Future<void> toggleItem(ChecklistItem item) {
    return (update(checklistItems)..where((t) => t.id.equals(item.id)))
        .write(ChecklistItemsCompanion(isDone: Value(!item.isDone)));
  }

    Future<void> deleteItem(int id) =>
      (delete(checklistItems)..where((t) => t.id.equals(id))).go();

  Future<void> editItem(int id, String content) =>
      (update(checklistItems)..where((t) => t.id.equals(id)))
          .write(ChecklistItemsCompanion(content: Value(content)));

  /// Isinusulat ulit ang position ng lahat ng items ayon sa bagong ayos.
  Future<void> reorderItems(int noteId, List<ChecklistItem> ordered) async {
    await transaction(() async {
      for (var i = 0; i < ordered.length; i++) {
        await (update(checklistItems)
              ..where((t) => t.id.equals(ordered[i].id)))
            .write(ChecklistItemsCompanion(position: Value(i)));
      }
    });
    await _updateNote(noteId, const NotesCompanion());
  }
}