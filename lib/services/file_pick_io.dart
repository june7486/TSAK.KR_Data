// 네이티브(io) 구현 — file_picker 플러그인 사용 (Android/iOS/데스크톱).
import 'package:file_picker/file_picker.dart';

import 'file_pick.dart';

Future<List<PickedFileData>> platformPickDataFiles({
  List<String> allowedExtensions = const [],
  bool allowMultiple = false,
  String? dialogTitle,
}) async {
  final res = await FilePicker.platform.pickFiles(
    dialogTitle: dialogTitle,
    type: allowedExtensions.isEmpty ? FileType.any : FileType.custom,
    allowedExtensions: allowedExtensions.isEmpty ? null : allowedExtensions,
    allowMultiple: allowMultiple,
    withData: true,
  );
  if (res == null || res.files.isEmpty) return const [];
  final out = <PickedFileData>[];
  for (final f in res.files) {
    final bytes = f.bytes;
    if (bytes == null) continue;
    out.add(PickedFileData(name: f.name, bytes: bytes, path: f.path));
  }
  return out;
}
