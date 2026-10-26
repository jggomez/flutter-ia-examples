# 0001. Dual-Model On-Device Runtime: `flutter_edge_ai` with LiteRT-LM, EmbeddingGemma 2 & Gemma 4 E2B IT (CPU `mmap`)

- **Status**: accepted (updated with Gemma 4 E2B IT and CPU `mmap` architecture)
- **Date**: 2026-10-24 (Updated: 2026-10-25)
- **Deciders**: flutter-architect

## Context

**StudyGemma** (`apps/rag_study_gemma`) is an offline, on-device PDF Vector RAG Study Companion (App 4 in the `flutter-ai` monorepo). Unlike `apps/event_gemma` (App 2), which relied on lexical keyword/synonym matching over a small static JSON agenda, StudyGemma ingests arbitrary user-supplied PDF textbooks, research papers, legal agreements, and lecture notes. Answering grounded study questions across multi-page academic PDFs requires:

1. **Dense Semantic Vector Embeddings**: High-dimensional semantic representations capable of matching conceptual queries (e.g., *"How does backpropagation update weights?"* or *"qué redes neuronales se usan para la clasificación?"*) to relevant textbook passages even when exact surface tokens differ, across both English and Spanish study materials.
2. **Instruction-Tuned Generative LLM with Cross-Lingual Synthesis**: An on-device language model capable of structured bulleted synthesis without falling into repetition loops, supporting cross-lingual reasoning (answering in Spanish from an English research paper) while strictly attributing facts with `[Doc Title, p. N]` citations.
3. **Unified Native Runtime Lifecycle with Strict Mobile Memory Constraints**: Both the embedding model and the generative model must execute 100% offline on mobile silicon without conflicting native symbol tables, duplicated runtime initialization, or out-of-memory (OOM) crashes on mid-range Android devices (e.g., Mali GPU architectures).

---

## Decision

Adopt the **`flutter_edge_ai` ecosystem** (`flutter_edge_ai: ^2.5.1`, `flutter_edge_ai_litertlm: ^1.17.0`, and `flutter_edge_ai_embeddings: ^2.3.2`) to run a **dual-model LiteRT-LM pipeline** encapsulated strictly behind `EdgeAiRagService` (`lib/data/services/edge_ai_rag_service.dart`):

### 1. Embedding Model — EmbeddingGemma 2 (`Embeddings 2.0`)
- **Upstream Repository**: `litert-community/embeddinggemma-2-text-270m-litert-lm` (revision `9be6e8b90982095dc05c2bd162e4b954ee4dbac7`)
- **Model Artifact**: `embeddinggemma-2-text-270m.litertlm` (~157.0 MB, ungated)
- **Embedding Profile ID**: `'embeddinggemma2-litertlm-text-4410a540ce75-prefix-v1'`
- **Output Vector Dimension**: `768` (`float32` normalized embeddings)
- **Maximum Context Window**: `1024` tokens (throws `EmbeddingInputTooLongException` if exceeded; safeguarded by the deterministic chunker in ADR 0002)
- **Embedded Tokenizer**: The SentencePiece tokenizer is embedded directly inside the `.litertlm` container; no external `.model` tokenizer file download is required (`tokenizerModelPath` is omitted).
- **Execution Backend**: Runs on `PreferredBackend.cpu` via the LiteRT-LM runtime.

### 2. Generative Model — `Gemma 4 E2B IT` (Upgrade from Gemma 3 1B IT)
- **Primary Upstream Repository**: `litert-community/gemma-4-E2B-it-litert-lm` (`gemma-4-E2B-it.litertlm`, ~2.58 GB, Model Type: `ModelType.gemma4`)
- **Why We Upgraded from Gemma 3 1B IT**:
  - `Gemma 3 1B IT` (~529 MB) struggled with dense multi-page PDF synthesis (academic papers, contracts, invoices) and frequently entered repetitive looping behavior when synthesizing complex excerpts.
  - `Gemma 4 E2B IT` delivers exceptional, structured bulleted synthesis, robust cross-lingual reasoning (e.g., querying in Spanish against an English PDF paper), and strict citation compliance with `enableThinking: false`.
- **Session Contract**: Per-turn fresh native conversation (`model.createChat(...)`) with explicit sampling (`temperature: 0.3`, `topK: 40`, `topP: 0.9`, `maxOutputTokens: 420`, `enableThinking: false`) and a real-time `hasRepetitionLoop` token stream guard.

### 3. Critical Mobile Memory Engineering on Mali GPUs: Why CPU `mmap` Beats OpenCL/GPU
A pivotal finding from empirical hardware testing on the physical Android device:
- `gemma-4-E2B-it.litertlm` employs Google's Gemma 4 mixed 2/4/8-bit CPU quantization scheme. Under CPU execution, the **1.12 GB embedding table is memory-mapped (`mmap`) directly from flash storage**, requiring only ~**0.8 GB of active physical RAM** for model execution.
- When initialized with `PreferredBackend.gpu` on Mali GPUs (`PowerVR, Broadcom, Mali GPUs`), OpenCL disables on-GPU weight preparation and attempts to allocate **3.4 GB of un-pageable contiguous GPU memory buffers**, instantly triggering an Android low-memory killer (LMK) abort.
- **Resolution**: Initialize the generative model with `PreferredBackend.cpu`:
  ```dart
  await FlutterEdgeAi.installModel(
    modelType: ModelType.gemma4,
    fileType: ModelFileType.litertlm,
  ).fromFile(llmModelPath).install();

  _llmModel = await FlutterEdgeAi.getActiveModel(
    maxTokens: 2048,
    preferredBackend: PreferredBackend.cpu,
  );
  ```
  LiteRT-LM compiles an XNNPACK weight cache once and runs smoothly on CPU SIMD with ~0.8 GB active RAM, delivering **~7.8 – 9.0 tokens/sec** decode throughput and zero stability issues.

### 4. Single Unified `FlutterEdgeAi.initialize()` Call
`EdgeAiRagService` executes an idempotent `FlutterEdgeAi.initialize()` call that registers all runtime subsystems before installing either model:

```dart
await FlutterEdgeAi.initialize(
  inferenceEngines: [LiteRtLmEngine(backendFallback: backendFallback)],
  embeddingBackends: const [LiteRtEmbeddingBackend()],
  embeddingTokenizers: const [GemmaEmbeddingTokenizers()],
);
```

### 5. Strict Service Encapsulation Boundary
`lib/data/services/edge_ai_rag_service.dart` is the **ONLY** file in `apps/rag_study_gemma` permitted to import `package:flutter_edge_ai*`. All higher layers (`RagIndexRepositoryImpl`, `ChatEngineRepositoryImpl`, domain use cases, and Riverpod view models) interact exclusively through pure-Dart interfaces and domain models.

---

## Consequences

- **Superior Synthesis & Cross-Lingual Reasoning**: Gemma 4 E2B IT answers complex study prompts concisely and accurately, translating concepts into Spanish or English based on the student's question language.
- **Zero OOM Aborts**: Leveraging CPU `mmap` avoids GPU memory allocation failures on mid-range Android devices, keeping active memory under 1 GB during live inference.
- **100% Deterministic Testing**: Unit, widget, and regression tests inject fake services/repositories (`test/support/fakes.dart`) and run without native LiteRT binaries or model weight downloads.
