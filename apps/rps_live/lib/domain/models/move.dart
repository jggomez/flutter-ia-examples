/// A hand shape recognized by the classifier or chosen by the AI opponent.
///
/// The declaration order MUST stay `paper, rock, scissors` — it mirrors the
/// output tensor class order of `assets/models/rps_model.tflite`
/// (index 0 = paper, 1 = rock, 2 = scissors), so `Move.values[classIndex]`
/// is a valid, tested mapping. Do not reorder without updating
/// `ClassificationResult` and the ADR that documents the model contract.
enum Move { paper, rock, scissors }
