import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/database.dart';

class BackupService {
  BackupService(this._db);

  final AppDatabase _db;

  /// Gumagawa ng .json file at binubuksan ang share sheet
  /// (pwedeng i-save sa Drive, Files, o i-send sa sarili sa Messenger/Telegram).
  Future<void> exportBackup() async {
    final data = await _db.exportData();
    final json = const JsonEncoder.withIndent('  ').convert(data);
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final file = File('${dir.path}/doqit-backup-$stamp.json');
    await file.writeAsString(json);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: 'Doqit backup',
      ),
    );
  }

  /// null = na-cancel ang picker. FormatException = hindi valid na backup.
  Future<({int imported, int skipped})?> importBackup() async {
    final picked = await FilePicker.pickFile();
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    final data = jsonDecode(utf8.decode(bytes));
    if (data is! Map<String, dynamic>) {
      throw const FormatException('not a Doqit backup');
    }
    return _db.importData(data);
  }
}