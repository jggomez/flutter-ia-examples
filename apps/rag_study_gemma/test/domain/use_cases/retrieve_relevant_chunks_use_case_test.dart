import 'package:flutter_test/flutter_test.dart';
import 'package:rag_study_gemma/domain/models/document_chunk.dart';
import 'package:rag_study_gemma/domain/models/retrieved_chunk.dart';
import 'package:rag_study_gemma/domain/use_cases/retrieve_relevant_chunks_use_case.dart';

import '../../support/fakes.dart';

void main() {
  group('RetrieveRelevantChunksUseCase', () {
    late FakeRagIndexRepository fakeRagRepo;
    late RetrieveRelevantChunksUseCase useCase;

    setUp(() {
      fakeRagRepo = FakeRagIndexRepository();
      useCase = const RetrieveRelevantChunksUseCase();
    });

    test('returns empty list when query is blank or whitespace-only', () async {
      fakeRagRepo.searchResults = const [
        RetrievedChunk(
          chunk: DocumentChunk(
            id: 'c1',
            docId: 'd1',
            docTitle: 'Physics',
            pageNumber: 1,
            chunkIndex: 0,
            content: 'Newton laws of motion',
          ),
          similarityScore: 0.9,
        ),
      ];

      final results = await useCase(
        query: '   \n\t  ',
        ragIndexRepository: fakeRagRepo,
      );

      expect(results, isEmpty);
      expect(fakeRagRepo.lastSearchQuery, isNull);
    });

    test('trims query, delegates to repository, filters by minSimilarity, and sorts descending', () async {
      fakeRagRepo.searchResults = const [
        RetrievedChunk(
          chunk: DocumentChunk(
            id: 'c1',
            docId: 'd1',
            docTitle: 'Physics',
            pageNumber: 2,
            chunkIndex: 0,
            content: 'Second law of thermodynamics',
          ),
          similarityScore: 0.62,
        ),
        RetrievedChunk(
          chunk: DocumentChunk(
            id: 'c2',
            docId: 'd1',
            docTitle: 'Physics',
            pageNumber: 5,
            chunkIndex: 1,
            content: 'First law of thermodynamics and conservation of energy',
          ),
          similarityScore: 0.91,
        ),
        RetrievedChunk(
          chunk: DocumentChunk(
            id: 'c3',
            docId: 'd2',
            docTitle: 'History',
            pageNumber: 1,
            chunkIndex: 0,
            content: 'Unrelated footnote',
          ),
          similarityScore: 0.15,
        ),
      ];

      final results = await useCase(
        query: '  thermodynamics laws  ',
        ragIndexRepository: fakeRagRepo,
        topK: 4,
        minSimilarity: 0.25,
        filterDocId: 'd1',
      );

      expect(fakeRagRepo.lastSearchQuery, equals('thermodynamics laws'));
      expect(fakeRagRepo.lastFilterDocId, equals('d1'));
      expect(results, hasLength(2));
      expect(results[0].chunk.id, equals('c2'));
      expect(results[0].similarityScore, equals(0.91));
      expect(results[1].chunk.id, equals('c1'));
      expect(results[1].similarityScore, equals(0.62));
    });
  });
}
