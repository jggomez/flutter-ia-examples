import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:rag_study_gemma/data/services/pdf_extractor_service.dart';
import 'package:rag_study_gemma/domain/repositories/document_ingestion_repository.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  group('PdfExtractorServiceImpl', () {
    late Directory tempDir;
    late PdfExtractorServiceImpl service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pdf_extractor_test_');
      service = const PdfExtractorServiceImpl();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('throws InvalidPdfException when extension is not .pdf', () async {
      final txtFile = File('${tempDir.path}/notes.txt');
      await txtFile.writeAsString('%PDF-1.7 fake content');

      await expectLater(
        () => service.extractPages(txtFile.path),
        throwsA(isA<InvalidPdfException>()),
      );
    });

    test('throws InvalidPdfException when file does not exist', () async {
      await expectLater(
        () => service.extractPages('${tempDir.path}/missing.pdf'),
        throwsA(isA<InvalidPdfException>()),
      );
    });

    test(
      'throws InvalidPdfException when %PDF- magic header is missing',
      () async {
        final invalidPdf = File('${tempDir.path}/corrupt.pdf');
        await invalidPdf.writeAsBytes([0x00, 0x01, 0x02, 0x03, 0x04, 0x05]);

        await expectLater(
          () => service.extractPages(invalidPdf.path),
          throwsA(isA<InvalidPdfException>()),
        );
      },
    );

    test(
      'throws EmptyPdfTextException when PDF has pages with no text',
      () async {
        final document = PdfDocument();
        document.pages.add();
        final bytes = await document.save();
        document.dispose();

        final blankPdf = File('${tempDir.path}/blank_scan.pdf');
        await blankPdf.writeAsBytes(bytes);

        await expectLater(
          () => service.extractPages(blankPdf.path),
          throwsA(isA<EmptyPdfTextException>()),
        );
      },
    );

    test('extracts 1-based pages from a real synthetic multi-page PDF via Isolate.run', () async {
      final document = PdfDocument();
      final font = PdfStandardFont(PdfFontFamily.helvetica, 12);

      final page1 = document.pages.add();
      page1.graphics.drawString(
        'Page One: Neural networks learn representations.',
        font,
        bounds: const Rect.fromLTWH(0, 0, 500, 200),
      );

      final page2 = document.pages.add();
      page2.graphics.drawString(
        'Page Two: Gradient descent minimizes the loss function.',
        font,
        bounds: const Rect.fromLTWH(0, 0, 500, 200),
      );

      final bytes = await document.save();
      document.dispose();

      final pdfFile = File('${tempDir.path}/Machine_Learning.PDF');
      await pdfFile.writeAsBytes(bytes);

      final extractedPages = await service.extractPages(pdfFile.path);
      expect(extractedPages, hasLength(2));
      expect(extractedPages[0].pageNumber, equals(1));
      expect(
        extractedPages[0].text,
        contains('Neural networks learn representations'),
      );
      expect(extractedPages[1].pageNumber, equals(2));
      expect(
        extractedPages[1].text,
        contains('Gradient descent minimizes the loss function'),
      );
    });
  });
}
