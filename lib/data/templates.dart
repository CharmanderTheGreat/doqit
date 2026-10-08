import 'note_color.dart';

class NoteTemplate {
  const NoteTemplate({
    required this.name,
    required this.title,
    required this.color,
    required this.items,
  });

  final String name;
  final String title;
  final NoteColor color;
  final List<String> items;
}

const noteTemplates = [
  NoteTemplate(
    name: 'birthday',
    title: 'Birthday plan',
    color: NoteColor.event,
    items: [
      'guest list',
      'venue',
      'food / cake',
      'gift',
      'invitations',
      'decorations',
      'photos',
    ],
  ),
  NoteTemplate(
    name: 'trip',
    title: 'Gala checklist',
    color: NoteColor.trip,
    items: [
      'pamasahe',
      'baon',
      'tubig',
      'powerbank',
      'charger',
      'ID / wallet',
      'extra damit',
      'payong',
    ],
  ),
  NoteTemplate(
    name: 'school',
    title: 'School tasks',
    color: NoteColor.work,
    items: [
      'review notes',
      'finish activity',
      'submit requirements',
      'charge laptop',
    ],
  ),
];