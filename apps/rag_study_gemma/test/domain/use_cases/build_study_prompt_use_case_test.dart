import 'package:flutter_test/flutter_test.dart';
import 'package:rag_study_gemma/domain/models/document_chunk.dart';
import 'package:rag_study_gemma/domain/models/retrieved_chunk.dart';
import 'package:rag_study_gemma/domain/models/study_document.dart';
import 'package:rag_study_gemma/domain/use_cases/build_study_prompt_use_case.dart';

void main() {
  group('BuildStudyPromptUseCase', () {
    late BuildStudyPromptUseCase useCase;

    setUp(() {
      useCase = const BuildStudyPromptUseCase();
    });

    test('includes StudyGemma persona, bilingual rule, numbered sources, and citation rule', () {
      const chunks = [
        RetrievedChunk(
          chunk: DocumentChunk(
            id: 'doc1_p12_c0',
            docId: 'doc1',
            docTitle: 'Linear Algebra Done Right',
            pageNumber: 12,
            chunkIndex: 0,
            content: 'An eigenvalue of T is a scalar lambda such that Tv = lambda v.',
          ),
          similarityScore: 0.88,
        ),
        RetrievedChunk(
          chunk: DocumentChunk(
            id: 'doc1_p14_c1',
            docId: 'doc1',
            docTitle: 'Linear Algebra Done Right',
            pageNumber: 14,
            chunkIndex: 1,
            content: 'Every operator on a finite-dimensional complex vector space has an eigenvalue.',
          ),
          similarityScore: 0.79,
        ),
      ];

      final prompt = useCase(
        userQuestion: 'What is an eigenvalue?',
        retrievedChunks: chunks,
      );

      expect(
        prompt,
        contains('You are StudyGemma, an expert on-device AI study companion.'),
      );
      expect(
        prompt,
        contains(
          "Detect the language of the student's question and ALWAYS reply in that exact same language (Spanish if asked in Spanish, English if asked in English).",
        ),
      );
      expect(
        prompt,
        contains(
          '[Source 1 | Document: Linear Algebra Done Right | Page 12]\nAn eigenvalue of T is a scalar lambda such that Tv = lambda v.',
        ),
      );
      expect(
        prompt,
        contains(
          '[Source 2 | Document: Linear Algebra Done Right | Page 14]\nEvery operator on a finite-dimensional complex vector space has an eigenvalue.',
        ),
      );
      expect(prompt, contains('[Doc Title, p. X]'));
      expect(prompt, contains('What is an eigenvalue?'));
    });

    test('handles empty retrieved chunks and mentions available documents when present', () {
      final docs = [
        StudyDocument(
          id: 'doc1',
          title: 'Operating Systems',
          fileName: 'os.pdf',
          filePath: '/tmp/os.pdf',
          pageCount: 40,
          chunkCount: 120,
          indexedAt: DateTime.utc(2026, 10, 24),
        ),
      ];

      final prompt = useCase(
        userQuestion: '¿Qué es la paginación?',
        retrievedChunks: const [],
        availableDocuments: docs,
      );

      expect(
        prompt,
        contains('You are StudyGemma, an expert on-device AI study companion.'),
      );
      expect(prompt, contains('Operating Systems'));
      expect(prompt, contains('¿Qué es la paginación?'));
    });

    test('caps long chunk excerpts to maxExcerptChars so mobile GPU prefill stays compact', () {
      final longContent = 'A' * 1200;
      final chunks = [
        RetrievedChunk(
          chunk: DocumentChunk(
            id: 'doc1_p1_c0',
            docId: 'doc1',
            docTitle: 'Deep Learning',
            pageNumber: 1,
            chunkIndex: 0,
            content: longContent,
          ),
          similarityScore: 0.91,
        ),
      ];

      final prompt = useCase(
        userQuestion: 'Summarize page 1',
        retrievedChunks: chunks,
      );

      expect(prompt, isNot(contains(longContent)));
      expect(prompt, contains('${'A' * 520}...'));
    });

    test('sanitizes base64 cryptographic seals and long machine-encoded tokens', () {
      const seal =
          'kR9+xL2/mN8pQ4vW7zB1cF5hJ0sT3uY6aD9eG2iK5lO8rU1wX4z9A2bC5dE8fG1h==';
      const cadena =
          '||1.1|580684D5-7012-4A3B-9E8C-1234567890AB|2026-10-24T12:00:00|SAT970701NN3||';
      const chunks = [
        RetrievedChunk(
          chunk: DocumentChunk(
            id: 'cfdi_p1_c0',
            docId: 'cfdi',
            docTitle: 'Constancia Fiscal',
            pageNumber: 1,
            chunkIndex: 0,
            content:
                'Nombre: JUAN PEREZ Sello Digital: $seal Cadena Original: $cadena Activo',
          ),
          similarityScore: 0.85,
        ),
      ];

      final prompt = useCase(
        userQuestion: '¿Cuál es el nombre?',
        retrievedChunks: chunks,
      );

      expect(prompt, isNot(contains(seal)));
      expect(prompt, isNot(contains(cadena)));
      expect(
        prompt,
        contains('Nombre: JUAN PEREZ Sello Digital: Cadena Original: Activo'),
      );
    });

    test('includes synthesis anti-repetition rule and deduplicates near-identical multi-page chunks', () {
      const sharedHeader =
          'EMISOR: SERVICIOS TECNOLOGICOS SA DE CV RFC: STE010101AAA RECEPTOR: JUAN PEREZ GOMEZ CONCEPTO: CONSULTORIA EN INGENIERIA DE SOFTWARE';
      const chunks = [
        RetrievedChunk(
          chunk: DocumentChunk(
            id: 'cfdi_p1_c0',
            docId: 'cfdi',
            docTitle: 'Factura CFDI',
            pageNumber: 1,
            chunkIndex: 0,
            content: '$sharedHeader PAGINA 1 DE 2 SUBTOTAL 1000.00',
          ),
          similarityScore: 0.90,
        ),
        RetrievedChunk(
          chunk: DocumentChunk(
            id: 'cfdi_p2_c0',
            docId: 'cfdi',
            docTitle: 'Factura CFDI',
            pageNumber: 2,
            chunkIndex: 0,
            content: '$sharedHeader PAGINA 2 DE 2 TOTAL 1160.00',
          ),
          similarityScore: 0.89,
        ),
        RetrievedChunk(
          chunk: DocumentChunk(
            id: 'cfdi_p2_c1',
            docId: 'cfdi',
            docTitle: 'Factura CFDI',
            pageNumber: 2,
            chunkIndex: 1,
            content: 'Metodo de pago: PUE Pago en una sola exhibicion Moneda: MXN Impuestos trasladados IVA 16% Condiciones de pago: Contado',
          ),
          similarityScore: 0.82,
        ),
      ];

      final prompt = useCase(
        userQuestion: 'Resume esta factura',
        retrievedChunks: chunks,
      );

      expect(
        prompt,
        contains(
          'Synthesize the information into 3 to 5 complete, well-formed bullet points. Do NOT copy raw lines verbatim and NEVER leave a sentence or phrase incomplete',
        ),
      );
      expect(prompt, contains('[Source 1 | Document: Factura CFDI | Page 1]'));
      expect(prompt, isNot(contains('PAGINA 2 DE 2 TOTAL 1160.00')));
      expect(
        prompt,
        contains(
          '[Source 2 | Document: Factura CFDI | Page 2]\nMetodo de pago: PUE',
        ),
      );
    });

    test('selectBestChunks drops seal-only chunks and truncated Forma de overlap fragments while keeping Page 1 items and Page 2 totals', () {
      const seal =
          'VGhpcyBpcyBhIHZlcnkgbG9uZyBiYXNlNjQgY3J5cHRvZ3JhcGhpYyBzZWFsIHN0cmluZyB0aGF0IGV4Y2VlZHMgNDggY2hhcmFjdGVycw==';
      const sharedInvoiceHeader =
          'CFDI de Ingreso Emisor: DEMOSTRACION S.A. DE C.V. Receptor: HOSPITAL REGIONAL Tipo de Comprobante: I - Ingreso Lugar de Expedición: 64460 Régimen Fiscal: 601';
      const p1c0Content =
          '$sharedInvoiceHeader Fecha de emisión: 05 de Octubre de 2022 Folio: F-945 Conceptos: Sutura quirúrgica sintética absorbible Importe \$1,206.90 Sonda Foley 2 vías Importe \$1,205.57 Forma de';
      const p1c1Fragment =
          'Lugar de Expedición: 64460 Régimen Fiscal: 601 Fecha de emisión: 05 de Octubre de 2022 Forma de';
      const p2c0Content =
          '$sharedInvoiceHeader Forma de pago: 99 - Por definir Método de pago: PPD - Pago en parcialidades o diferido Moneda: MXN Subtotal \$2,412.47 IVA 16% \$386.00 Total \$2,798.47';

      const candidates = [
        RetrievedChunk(
          chunk: DocumentChunk(
            id: 'p1_c3',
            docId: 'cfdi',
            docTitle: 'Factura CFDI',
            pageNumber: 1,
            chunkIndex: 3,
            content:
                'Sello Digital del CFDI $seal Sello del SAT $seal ESTE DOCUMENTO ES UNA REPRESENTACIÓN IMPRESA DE UN CFDI',
          ),
          similarityScore: 0.25,
        ),
        RetrievedChunk(
          chunk: DocumentChunk(
            id: 'p1_c1',
            docId: 'cfdi',
            docTitle: 'Factura CFDI',
            pageNumber: 1,
            chunkIndex: 1,
            content: p1c1Fragment,
          ),
          similarityScore: 0.22,
        ),
        RetrievedChunk(
          chunk: DocumentChunk(
            id: 'p1_c0',
            docId: 'cfdi',
            docTitle: 'Factura CFDI',
            pageNumber: 1,
            chunkIndex: 0,
            content: p1c0Content,
          ),
          similarityScore: 0.16,
        ),
        RetrievedChunk(
          chunk: DocumentChunk(
            id: 'p2_c0',
            docId: 'cfdi',
            docTitle: 'Factura CFDI',
            pageNumber: 2,
            chunkIndex: 0,
            content: p2c0Content,
          ),
          similarityScore: 0.13,
        ),
      ];

      final selected = useCase.selectBestChunks(candidates, maxChunks: 3);

      expect(selected.map((c) => c.chunk.id).toList(), ['p1_c0', 'p2_c0']);
      expect(selected.first.chunk.content, isNot(endsWith('Forma de')));
      expect(selected.last.chunk.content, contains('Total \$2,798.47'));
      expect(
        selected.last.chunk.content,
        contains('Forma de pago: 99 - Por definir'),
      );
    });

    test('preserves newlines in sanitizeExcerpt and cuts long excerpts cleanly at the last newline or period', () {
      const lines = [
        'Emisor: GRUPO DIAGNOSTICO MEDICO PROA S.A. DE C.V. RFC: GDM990101AAA.',
        'Receptor: HOSPITAL REGIONAL DE ALTA ESPECIALIDAD RFC: HRA010101BBB.',
        'Concepto 1: Sutura quirúrgica sintética absorbible calibre 2-0 Importe \$1,206.90.',
        'Concepto 2: Sonda Foley de látex 2 vías calibre 16Fr Importe \$1,205.57.',
        'Forma de pago: 99 - Por definir. Método de pago: PPD - Pago en parcialidades o diferido.',
        'Subtotal: \$2,412.47. Impuestos Trasladados IVA 16%: \$386.00. Total: \$2,798.47.',
        'Observaciones adicionales: Entrega en almacén central de lunes a viernes en horario matutino.',
      ];
      final multiLineContent = lines.join('\n');

      final prompt = useCase(
        userQuestion: 'Resume la factura',
        retrievedChunks: [
          RetrievedChunk(
            chunk: DocumentChunk(
              id: 'cfdi_p1_c0',
              docId: 'cfdi',
              docTitle: 'Factura CFDI',
              pageNumber: 1,
              chunkIndex: 0,
              content: multiLineContent,
            ),
            similarityScore: 0.91,
          ),
        ],
        maxExcerptChars: 420,
      );

      expect(prompt, contains('RFC: GDM990101AAA.\nReceptor:'));
      expect(
        prompt,
        isNot(contains('Observaciones adicionales: Entrega en almacén')),
      );
      // Must end cleanly at the end of a full line/period before 420 chars, not mid-line.
      expect(
        prompt,
        contains(
          'Forma de pago: 99 - Por definir. Método de pago: PPD - Pago en parcialidades o diferido.\n\n=== STUDENT QUESTION ===',
        ),
      );
    });
  });
}
