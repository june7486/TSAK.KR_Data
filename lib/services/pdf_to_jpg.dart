/// PDF 바이트 → **JPG 이미지** 변환 공용 헬퍼 (규칙: 모든 출력 메뉴에 JPG 제공).
///
/// ## 왜 필요한가 (요구: "출력시 jpg추가 (모든 출력메뉴에 적용-앱 규칙임)")
/// 그동안 JPG 출력은 "브라우저 인쇄창에서 대상=이미지로 저장"하는 방식에만
/// 의존해, PC·스마트폰 환경에 따라 **실제 .jpg 파일이 만들어지지 않았다.**
/// 이 헬퍼는 이미 만들어져 있는 **PDF 바이트를 실제 래스터화(rasterize)** 하여
/// 진짜 .jpg 바이트로 변환한다. (인쇄창 불필요 — 어떤 브라우저든 동작)
///
/// `printing` 패키지의 라스터라이저(내부적으로 pdfium 사용)와 `image` 패키지의
/// JPEG 인코더를 사용한다. 명단출력(roster_screen)에서 검증된 방식과 동일하다.
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:printing/printing.dart';

/// PDF [pdf] 의 **첫 페이지**를 JPG 바이트로 변환한다.
///
/// - [dpi]   : 해상도(기본 150 — A4 한 장이 대략 1240×1754px).
/// - [quality] : JPEG 품질(기본 88).
///
/// 여러 페이지일 때는 [pdfToJpgPages] 를 사용한다.
Future<Uint8List> pdfToJpg(
  Uint8List pdf, {
  double dpi = 150,
  int quality = 88,
}) async {
  final raster = await Printing.raster(pdf, dpi: dpi).first;
  final im = img.Image.fromBytes(
    width: raster.width,
    height: raster.height,
    bytes: raster.pixels.buffer,
    numChannels: 4,
  );
  return img.encodeJpg(im, quality: quality);
}

/// PDF [pdf] 의 **모든 페이지**를 JPG 바이트 목록으로 변환한다.
Future<List<Uint8List>> pdfToJpgPages(
  Uint8List pdf, {
  double dpi = 150,
  int quality = 88,
}) async {
  final out = <Uint8List>[];
  await for (final raster in Printing.raster(pdf, dpi: dpi)) {
    final im = img.Image.fromBytes(
      width: raster.width,
      height: raster.height,
      bytes: raster.pixels.buffer,
      numChannels: 4,
    );
    out.add(img.encodeJpg(im, quality: quality));
  }
  return out;
}
