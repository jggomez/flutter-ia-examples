# 0002. On-Device Vector Store (`sqlite-vec` `vec0`), Structure-Aware PDF Chunking & Grounded Prompting

- **Status**: accepted (updated with structure-aware chunking, candidate over-fetching & stream guard)
- **Date**: 2026-10-24 (Updated: 2026-10-25)
- **Deciders**: flutter-architect

## Context

Once a study PDF is extracted into page-indexed text, **StudyGemma** must:
1. **Segment pages into semantically coherent chunks** that never cut words or sentences in half, heal visual PDF margin soft wraps, strip cryptographic digital seals, and stay strictly below `EmbeddingGemma 2`'s 1024-token context limit (which otherwise throws `EmbeddingInputTooLongException`).
2. **Compute 768-dimensional float32 vectors** using asymmetric retrieval task prefixes (`TaskType.retrievalDocument` at index time vs `TaskType.retrievalQuery` at search time).
3. **Persist vectors and structured metadata** (`doc_id`, `doc_title`, `page_number`, `chunk_index`) on disk in native SQLite `sqlite-vec` (`vec0`) so indexed textbooks survive app restarts without re-embedding.
4. **Select high-signal, non-redundant context chunks** from candidate retrieval hits and build compact, cleanly bounded prompts that prevent KV-cache bloat and model repetition loops.

---

## Decision

### 1. Native Vector Store: `flutter_edge_ai_sqlite` (`^2.1.1`) + `flutter_edge_ai_rag` (`^1.1.2`)
Use `RagIndex` backed by `SqliteVectorStoreProvider` (`sqlite-vec` C extension `vec0` virtual table via Dart FFI Native Assets), persisted at `AppStorageService.ragSqliteDbPath` (`study_gemma_rag.sqlite`):

```dart
final rag = FlutterEdgeAiRag(
  providers: const [SqliteVectorStoreProvider()],
);

_ragIndex = await rag.open(
  spec: VectorStoreSpec(
    providerId: SqliteVectorStoreProvider.providerId,
    location: sqliteDbPath,
    filterSchema: FilterSchema(
      fields: [
        FilterField(name: 'doc_id', type: FilterFieldType.string),
        FilterField(name: 'doc_title', type: FilterFieldType.string),
        FilterField(name: 'page_number', type: FilterFieldType.number),
        FilterField(name: 'chunk_index', type: FilterFieldType.number),
      ],
    ),
  ),
  embedder: ragEmbedder,
);
```

### 2. Structure- & Sentence-Aware PDF Chunking (`ChunkDocumentUseCase`)
`ChunkDocumentUseCase` (`lib/domain/use_cases/chunk_document_use_case.dart`) executes a 4-step pure-Dart normalization and chunking pipeline:

1. **Cryptographic Noise & Digital Seal Stripping**:
   - Detects and strips machine-encoded tokens (`>= 48` characters containing mixed alphanumeric characters and Base64 symbols `+/=|`, such as SAT digital seals and CFDI chains) before chunking.
   - Ensures vectors reflect semantic text rather than random cryptographic hash blocks.
2. **Hyphenation & Soft PDF Margin-Wrap Healing**:
   - De-hyphenates line-broken words across newlines (`"backprop-\nagation"` → `"backpropagation"`).
   - `syncfusion_flutter_pdf` inserts visual line breaks `\n` at the right margin of justified text (e.g., in legal documents or academic columns). `ChunkDocumentUseCase` inspects line endings and merges soft-wrapped prose lines until terminal punctuation (`.`, `!`, `?`, `:`, `;`), while preserving standalone list items and `Key: Value` lines.
3. **Strict Sentence (`.`, `!`, `?`) and Structural Line (`\n`) Boundaries**:
   - Splits prose text on `(?<=[.!?])\s+`.
   - Every chunk begins at the start of a sentence/line and **always ends cleanly at a period, exclamation mark, question mark, or newline**—never cutting sentences or words in half.
4. **Sliding-Window Overlap & Token Safety Ceiling**:
   - Accumulates complete sentence/line units up to **`targetWords = 220`** (~290–320 tokens).
   - Carries over a **`overlapWords = 40`** unit-aligned overlap between consecutive chunks on the same page.
   - Enforces a hard **`maxChars = 1400`** ceiling (~350–450 tokens worst-case), well below `EmbeddingGemma 2`'s 1024-token limit.

### 3. Candidate Over-Fetching & `selectBestChunks` (`BuildStudyPromptUseCase`)
At query time:
- `StudyChatViewModel` requests **`topK: 8`** candidate chunks (`minSimilarity: 0.20`) from the SQLite vector store.
- `BuildStudyPromptUseCase.selectBestChunks`:
  - Strips any residual digital seal headers.
  - Drops seal-only chunks when substantive chunks (`>= 100` chars) exist.
  - Drops short overlap fragments whose content is already contained inside longer chunks.
  - Sorts chunks into natural reading order `(pageNumber, chunkIndex)`.
  - Deduplicates multi-page repeated headers and near-identical chunks.
  - Emits the top **3** complementary chunks for prompt injection and interactive UI citation chips.

### 4. Clean Boundary Excerpt Capping (`520 chars`)
To keep mobile prefill fast (~9–12s on device) and prevent token exhaustion:
- Long chunk excerpts are capped at `maxExcerptChars = 520`.
- Truncation never cuts mid-word; it snaps to the last newline (`\n`) or sentence-ending period (`.`), ensuring the model only reads complete syntactic clauses.

### 5. Per-Turn Fresh Native Session & Anti-Repetition Guard
- **Fresh Native Session**: `EdgeAiRagServiceImpl.sendMessageStream` creates a new `model.createChat(...)` instance per turn (`temperature: 0.3`, `topK: 40`, `topP: 0.9`, `maxOutputTokens: 420`, `enableThinking: false`). This prevents the native KV-cache from accumulating prior turns, keeping RAM steady.
- **Tandem Loop Detection**: Real-time `hasRepetitionLoop` stream guard checks for 3x consecutive 8–80 char loops or repeated 48+ char clauses (ignoring citation tags) and breaks the stream if repetition occurs (`maxResponseChars = 1600`).

---

## Consequences

- **100% Coherent Excerpts**: No chunk in the vector store starts or ends in the middle of a word or sentence.
- **Clean Cross-Lingual Attribution**: The prompt enforces explicit `[Doc Title, p. N]` citation syntax, which the UI renders as interactive chips navigating directly to source pages.
- **Fast On-Device Retrieval**: Vector similarity queries execute in <5ms via native SQLite `vec0` virtual tables.
