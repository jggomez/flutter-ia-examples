import 'package:flutter_test/flutter_test.dart';
import 'package:rag_study_gemma/domain/models/extracted_pdf_page.dart';
import 'package:rag_study_gemma/domain/use_cases/chunk_document_use_case.dart';

void main() {
  group('ChunkDocumentUseCase', () {
    late ChunkDocumentUseCase useCase;

    setUp(() {
      useCase = const ChunkDocumentUseCase();
    });

    test('skips empty and whitespace-only pages', () {
      final chunks = useCase(
        docId: 'doc-1',
        docTitle: 'Deep Learning',
        pages: const [
          ExtractedPdfPage(pageNumber: 1, text: ''),
          ExtractedPdfPage(pageNumber: 2, text: '   \n\t  '),
          ExtractedPdfPage(
            pageNumber: 3,
            text: 'Gradient descent updates weights.',
          ),
        ],
      );

      expect(chunks, hasLength(1));
      expect(chunks.first.id, equals('doc-1_p3_c0'));
      expect(chunks.first.pageNumber, equals(3));
      expect(chunks.first.chunkIndex, equals(0));
      expect(chunks.first.content, equals('Gradient descent updates weights.'));
    });

    test('normalizes broken hyphenation across newlines, collapses horizontal whitespace, and preserves line breaks', () {
      final chunks = useCase(
        docId: 'doc-2',
        docTitle: 'Neural Nets',
        pages: const [
          ExtractedPdfPage(
            pageNumber: 1,
            text: 'Backprop-\nagation   computes   the   gra-\r\ndient\n\nfor   weights.',
          ),
        ],
      );

      expect(chunks, hasLength(1));
      expect(
        chunks.first.content,
        equals('Backpropagation computes the gradient\nfor weights.'),
      );
    });

    test('splits page text into sliding-window chunks with overlap and deterministic IDs', () {
      final words = List.generate(50, (i) => 'word$i').join(' ');
      final chunks = useCase(
        docId: 'doc-3',
        docTitle: 'Calculus',
        pages: [ExtractedPdfPage(pageNumber: 2, text: words)],
        targetWords: 20,
        overlapWords: 5,
      );

      // Window 0: words 0..19 (20 words)
      // Step = 20 - 5 = 15
      // Window 1: words 15..34 (20 words)
      // Window 2: words 30..49 (20 words)
      expect(chunks, hasLength(3));
      expect(chunks[0].id, equals('doc-3_p2_c0'));
      expect(chunks[0].chunkIndex, equals(0));
      expect(chunks[0].content.split(' ').first, equals('word0'));
      expect(chunks[0].content.split(' ').last, equals('word19'));

      expect(chunks[1].id, equals('doc-3_p2_c1'));
      expect(chunks[1].chunkIndex, equals(1));
      expect(chunks[1].content.split(' ').first, equals('word15'));
      expect(chunks[1].content.split(' ').last, equals('word34'));

      expect(chunks[2].id, equals('doc-3_p2_c2'));
      expect(chunks[2].chunkIndex, equals(2));
      expect(chunks[2].content.split(' ').first, equals('word30'));
      expect(chunks[2].content.split(' ').last, equals('word49'));
    });

    test('enforces hard maxChars ceiling on unbroken long strings', () {
      final unbroken = 'A' * 3200;
      final chunks = useCase(
        docId: 'doc-4',
        docTitle: 'Genome Sequence',
        pages: [ExtractedPdfPage(pageNumber: 1, text: unbroken)],
        maxChars: 1400,
      );

      expect(chunks.length, equals(3));
      for (final chunk in chunks) {
        expect(chunk.content.length, lessThanOrEqualTo(1400));
      }
      expect(chunks[0].id, equals('doc-4_p1_c0'));
      expect(chunks[0].content.length, equals(1400));
      expect(chunks[1].id, equals('doc-4_p1_c1'));
      expect(chunks[1].content.length, equals(1400));
      expect(chunks[2].id, equals('doc-4_p1_c2'));
      expect(chunks[2].content.length, equals(400));
    });

    test(
      'enforces hard maxChars ceiling when word window exceeds maxChars',
      () {
        // 30 words each of 60 characters -> >1800 chars in a single 30-word window
        final longWords = List.generate(
          30,
          (i) => 'w${i}_${'x' * 55}',
        ).join(' ');
        final chunks = useCase(
          docId: 'doc-5',
          docTitle: 'Chemistry',
          pages: [ExtractedPdfPage(pageNumber: 4, text: longWords)],
          targetWords: 30,
          overlapWords: 5,
          maxChars: 1400,
        );

        expect(chunks.length, greaterThan(1));
        for (final chunk in chunks) {
          expect(chunk.content.length, lessThanOrEqualTo(1400));
          expect(chunk.pageNumber, equals(4));
        }
      },
    );

    test('strips base64 cryptographic seals and SAT chains before chunking', () {
      const seal =
          'h8Lm7c469mO6sE8xP2qR5tV9wY1zA3bC6dF8gH0jK2lM4nP7qS9uV1xZ3aB5cD7eF9==';
      const cadena =
          '||1.1|580684D5-7012-4A3B-96E7-7E315E14B8F0|2026-01-09T07:05:00|SAT970701NN3||';
      final chunks = useCase(
        docId: 'doc-cfdi',
        docTitle: 'Factura',
        pages: const [
          ExtractedPdfPage(
            pageNumber: 1,
            text:
                'Subtotal 2412.47 Total 2798.47 Sello: $seal Cadena: $cadena Forma de Pago Tarjeta',
          ),
        ],
      );

      expect(chunks, hasLength(1));
      expect(chunks.first.content, isNot(contains(seal)));
      expect(chunks.first.content, isNot(contains(cadena)));
      expect(
        chunks.first.content,
        equals(
          'Subtotal 2412.47 Total 2798.47 Sello: Cadena: Forma de Pago Tarjeta',
        ),
      );
    });

    test('chunks multi-line structured PDF pages strictly on newline boundaries and never cuts a line in half', () {
      const lines = [
        'Emisor: GRUPO DIAGNOSTICO MEDICO PROA S.A. DE C.V.',
        'RFC Emisor: GDM990101AAA',
        'Receptor: JUAN CARLOS PEREZ LOPEZ',
        'Régimen Fiscal Receptor: 605 - Sueldos y Salarios e Ingresos Asimilados a Salarios',
        'Concepto 1: Biometría Hemática Completa Importe \$450.00',
        'Concepto 2: Química Sanguínea de 6 Elementos Importe \$780.00',
        'Forma de Pago: 04 - Tarjeta de crédito',
        'Método de Pago: PUE - Pago en una sola exhibición',
        'Subtotal: \$1,230.00 IVA 16%: \$196.80 Total: \$1,426.80',
      ];
      final pageText = lines.join('\n');

      final chunks = useCase(
        docId: 'cfdi',
        docTitle: 'Factura',
        pages: [ExtractedPdfPage(pageNumber: 1, text: pageText)],
        targetWords: 25,
        overlapWords: 10,
        maxChars: 300,
      );

      expect(chunks.length, greaterThan(1));
      for (final chunk in chunks) {
        expect(chunk.content, contains('\n'));
        final chunkLines = chunk.content.split('\n');
        for (final line in chunkLines) {
          expect(
            lines,
            contains(line),
            reason: 'Every line in chunk must be a complete original line',
          );
        }
      }
    });

    test('chunks long single-line prose strictly at sentence-ending periods and never mid-sentence', () {
      const s1 =
          'Transformers rely on self-attention mechanisms to model dependencies across tokens.';
      const s2 =
          'Unlike recurrent networks, attention layers process the entire sequence in parallel!';
      const s3 =
          'How does positional encoding preserve token order in the absence of recurrence?';
      const s4 =
          'Sinusoidal or learned embeddings are added directly to the input representations.';
      const prose = '$s1 $s2 $s3 $s4';

      final chunks = useCase(
        docId: 'paper',
        docTitle: 'Attention',
        pages: const [ExtractedPdfPage(pageNumber: 1, text: prose)],
        targetWords: 24,
        overlapWords: 12,
        maxChars: 220,
      );

      expect(chunks.length, greaterThan(1));
      for (final chunk in chunks) {
        expect(
          RegExp(r'[.!?]$').hasMatch(chunk.content.trim()),
          isTrue,
          reason:
              'Chunk "${chunk.content}" must end at sentence punctuation (.!?)',
        );
      }
    });

    test('merges soft PDF margin wraps in prose documents (TECNOFEST) so chunks never end at carácter gratu or start at so remoto', () {
      const tecnofestText = '''
AUTORIZACIÓN DE CESIÓN DE DERECHOS DE IMAGEN
Nombre
Imagen
Frases, declaraciones y/o manifestaciones
Interpretaciones y/o ejecuciones
Para los exclusivos efectos de emitir, difundir y promocionar mi participación a través de acce
so remoto, para efectos de realizar material audiovisual y/o fotográfico en el evento
TECNOFEST 2020.
Tal utilización podrá realizarse a través de cualquier medio o formato conocido o por
conocerse, a nivel nacional e internacional, a través de los canales oficiales de la institución y
los que la agencia
organizadora estime convenientes.
Manifiesto que esta autorización la otorgo con carácter gratu
ito, por lo que entiendo que no recibiré ningún tipo de compensación, remuneración o regalía
por el uso de mi imagen y demás elementos antes señalados, renunciando a cualquier reclamo posterior de cualquier
naturaleza.
Reconozco además que no existe ninguna expectativa de privacidad respecto de las
grabaciones, fotografías o capturas de pantalla que se realicen durante mi participación en el evento, autorizando las modificaciones o ediciones que resulten
convenientes.
La vigencia de la presente autorización será por tiempo indefinido y sin límite territorial alguno
para el material que se llegue a emitir.
Firma del participante''';

      final chunks = useCase(
        docId: 'tecnofest',
        docTitle: 'AUTORIZACION DE CESION DE DERECHOS TECNOFEST',
        pages: const [ExtractedPdfPage(pageNumber: 1, text: tecnofestText)],
        targetWords: 95,
        overlapWords: 35,
        maxChars: 900,
      );

      expect(chunks.length, greaterThan(1));
      for (var i = 0; i < chunks.length; i++) {
        final content = chunks[i].content.trim();
        expect(content, isNot(endsWith('carácter gratu')));
        expect(content, isNot(startsWith('so remoto')));
        expect(content, isNot(startsWith('ito,')));
        if (i < chunks.length - 1) {
          expect(
            content.endsWith('.'),
            isTrue,
            reason: 'Prose chunk $i must end at a period (.): "$content"',
          );
        } else {
          expect(
            content.endsWith('.') || content.endsWith('Firma del participante'),
            isTrue,
            reason:
                'Final chunk must end at a period or signature line: "$content"',
          );
        }
      }
    });
  });
}
