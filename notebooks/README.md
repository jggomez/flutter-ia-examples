# Notebooks

## `Deep_Learning_tensorflow_lite_01.ipynb`

Trains the Rock/Paper/Scissors classifier used by the `rps_live` Flutter
app.

- **Dataset**: `drgfreeman/rockpaperscissors` on Kaggle, loaded via
  `kagglehub`.
- **Preprocessing**: images resized to 96x96, converted to grayscale, and
  normalized to `[0, 1]`, with a stratified 80/20 train/validation split.
- **Model**: a compact CNN (three Conv2D + MaxPooling blocks, a 16-unit
  dense layer, dropout) with 29,235 parameters, trained with early
  stopping. Validation accuracy is above 90%.

### Two export paths

The notebook produces two different `.tflite` builds from the same trained
model, for two different targets:

1. **ESP32 (microcontroller)** — full INT8 quantization on both weights
   and input/output tensors, calibrated against a representative dataset,
   then exported as a C byte array (`model_data.cc`) via `xxd` for
   firmware integration. Produces `model.tflite`, about 35 KB.
2. **Mobile (Flutter / LiteRT)** — the "Export for Mobile" section near
   the end of the notebook. Reuses the same trained model but applies only
   dynamic-range quantization, keeping the input and output tensors as
   `float32`. This avoids the microcontroller-only need to manually apply
   a quantization scale and zero-point to every camera frame in Dart.
   Produces `rps_model.tflite`.

LiteRT is the current name for the TensorFlow Lite runtime and file
format — no conversion step is needed between "TFLite" and "LiteRT"; the
`.tflite` file from either export path is already LiteRT-compatible. The
mobile export exists because the ESP32 export's INT8 I/O strategy is
unnecessary complexity on a phone, not because of any format difference.

### Using the output

Copy the mobile export's output file into
`../apps/rps_live/assets/models/rps_model.tflite`. Input contract: shape
`[1, 96, 96, 1]`, `float32`, grayscale normalized to `[0, 1]`. Output
contract: shape `[1, 3]`, `float32` softmax, class order
`["paper", "rock", "scissors"]`.

Running the notebook requires TensorFlow and Kaggle API credentials
(`~/.kaggle/kaggle.json` or an equivalent `kagglehub` login), neither of
which is set up in this repository's local environment — it was run in
Google Colab.
