// 조건부 임포트의 기본(스텁) 구현.
// 실제로는 web/js_interop 또는 io 구현이 선택된다.
import 'file_pick.dart';

Future<List<PickedFileData>> platformPickDataFiles({
  List<String> allowedExtensions = const [],
  bool allowMultiple = false,
  String? dialogTitle,
}) async {
  throw UnsupportedError('파일 선택이 이 플랫폼에서 지원되지 않습니다.');
}
