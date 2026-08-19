"""Patch MathReader's Keras CNN with a vendored TFLite interpreter.

Import this module before `mathreader.api`. TensorFlow is stubbed when
missing so the original `classification.py` can import on mobile.

`tflite_runtime.interpreter` inspects `__file__` and, inside a zipimport
path (Android sitepackages.zip), takes the TensorFlow branch. Seed that
branch with the real native wrapper so Interpreter still loads.
"""

from __future__ import annotations

import os
import sys
import traceback
import types


def _log(msg: str) -> None:
    line = "[mathreader] " + msg
    try:
        sys.stderr.write(line + "\n")
        sys.stderr.flush()
    except Exception:
        pass


def _mod(name: str) -> types.ModuleType:
    existing = sys.modules.get(name)
    if existing is not None:
        return existing
    mod = types.ModuleType(name)
    sys.modules[name] = mod
    return mod


def _install_import_stubs() -> None:
    tf = _mod("tensorflow")
    keras = _mod("tensorflow.keras")
    models = _mod("tensorflow.keras.models")

    def _load_model(*_a, **_k):
        raise RuntimeError("MathReader CNN is served by TFLite, not Keras")

    models.load_model = _load_model
    keras.models = models
    tf.keras = keras
    if not hasattr(tf, "__version__"):
        tf.__version__ = "tflite-shim"

    if "matplotlib" not in sys.modules:
        mpl = _mod("matplotlib")
        pyplot = _mod("matplotlib.pyplot")
        mpl.pyplot = pyplot
        pyplot.imshow = lambda *a, **k: None
        pyplot.show = lambda *a, **k: None
        pyplot.close = lambda *a, **k: None

    if "h5py" not in sys.modules:
        _mod("h5py")

    if "idx2numpy" not in sys.modules:
        idx = _mod("idx2numpy")
        idx.convert_from_file = lambda *_a, **_k: None


def _seed_tensorflow_lite_branch(wrapper, metrics_mod, metrics_iface) -> None:
    """Satisfy interpreter.py / metrics_portable when __file__ is a zip path."""

    def _tf_export(*_x, **_k):
        return lambda fn: fn

    lite = _mod("tensorflow.lite")
    py = _mod("tensorflow.lite.python")
    iw = _mod("tensorflow.lite.python.interpreter_wrapper")
    if wrapper is not None:
        iw._pywrap_tensorflow_interpreter_wrapper = wrapper
    met = _mod("tensorflow.lite.python.metrics")
    met.metrics = metrics_mod
    met.metrics_interface = metrics_iface
    _mod("tensorflow.python")
    _mod("tensorflow.python.util")
    tf_export_mod = _mod("tensorflow.python.util.tf_export")
    tf_export_mod.tf_export = _tf_export

    tf = sys.modules["tensorflow"]
    tf.lite = lite
    lite.python = py
    py.interpreter_wrapper = iw
    py.metrics = met


def _interpreter_class():
    errors = []

    try:
        from tflite_runtime import (
            _pywrap_tensorflow_interpreter_wrapper as wrapper,
        )
        _log("loaded tflite_runtime native wrapper")
    except Exception:
        errors.append(
            "tflite_runtime._pywrap_tensorflow_interpreter_wrapper:\n"
            + traceback.format_exc()
        )
        wrapper = None

    try:
        from tflite_runtime import metrics_interface
    except Exception:
        errors.append("tflite_runtime.metrics_interface:\n" + traceback.format_exc())
        metrics_interface = types.ModuleType("metrics_interface")

    dummy_metrics = types.ModuleType("metrics_portable")
    dummy_metrics.TFLiteMetrics = lambda *a, **k: types.SimpleNamespace(
        increase_counter_interpreter_creation=lambda: None
    )
    # Seed before metrics_portable / interpreter — those files take a TensorFlow
    # import branch when zipimport __file__ doesn't end with tflite_runtime/...
    _seed_tensorflow_lite_branch(wrapper, dummy_metrics, metrics_interface)

    try:
        from tflite_runtime import metrics_portable as metrics
        _seed_tensorflow_lite_branch(wrapper, metrics, metrics_interface)
    except Exception:
        errors.append("tflite_runtime.metrics_portable:\n" + traceback.format_exc())

    try:
        from tflite_runtime.interpreter import Interpreter

        _log("using tflite_runtime.interpreter.Interpreter")
        return Interpreter
    except Exception:
        errors.append(
            "tflite_runtime.interpreter:\n" + traceback.format_exc()
        )

    try:
        from ai_edge_litert.interpreter import Interpreter

        _log("using ai_edge_litert.interpreter.Interpreter")
        return Interpreter
    except Exception:
        errors.append("ai_edge_litert.interpreter:\n" + traceback.format_exc())

    try:
        import tensorflow as tf

        if hasattr(tf, "lite") and hasattr(tf.lite, "Interpreter"):
            _log("using tensorflow.lite.Interpreter")
            return tf.lite.Interpreter
    except Exception:
        errors.append("tensorflow.lite.Interpreter:\n" + traceback.format_exc())

    raise RuntimeError(
        "No TFLite interpreter available:\n" + "\n".join(errors)
    )


_install_import_stubs()

import numpy as np
from mathreader import helpers
from mathreader.classification import classification as classification

_Interpreter = None
_INTERPRETER = None
_INPUT_INDEX = None
_OUTPUT_INDEX = None
_INPUT_DTYPE = np.float32


def _tflite_path() -> str:
    env = os.environ.get("MATHREADER_TFLITE", "").strip()
    here = os.path.dirname(os.path.abspath(__file__))
    candidates = [
        env,
        os.path.join(here, "symbol_cnn.tflite"),
        os.path.join(os.getcwd(), "symbol_cnn.tflite"),
    ]
    for path in candidates:
        if path and os.path.isfile(path):
            return path
    raise FileNotFoundError(
        "symbol_cnn.tflite not found; run tools/export_mathreader_tflite.py"
    )


def _get_interpreter():
    global _Interpreter, _INTERPRETER, _INPUT_INDEX, _OUTPUT_INDEX, _INPUT_DTYPE
    if _Interpreter is None:
        _Interpreter = _interpreter_class()
    if _INTERPRETER is None:
        interpreter = _Interpreter(model_path=_tflite_path())
        interpreter.allocate_tensors()
        inp = interpreter.get_input_details()[0]
        out = interpreter.get_output_details()[0]
        _INTERPRETER = interpreter
        _INPUT_INDEX = inp["index"]
        _OUTPUT_INDEX = out["index"]
        _INPUT_DTYPE = inp.get("dtype", np.float32)
    return _INTERPRETER


def fit(image):
    labels = helpers.get_labels()
    arr = np.asarray(image, dtype=np.float32)
    arr = np.squeeze(arr)
    if arr.ndim == 2:
        arr = arr[..., np.newaxis]
    arr = np.reshape(arr, (1, 28, 28, 1)).astype(_INPUT_DTYPE, copy=False)

    interpreter = _get_interpreter()
    interpreter.set_tensor(_INPUT_INDEX, arr)
    interpreter.invoke()
    prediction = np.array(
        interpreter.get_tensor(_OUTPUT_INDEX), copy=True, dtype=np.float32
    )
    index = int(np.argmax(prediction))
    label_rec = labels["labels_parser"][str(index)]
    return {
        "label": labels["labels_recognition"][label_rec],
        "prediction": prediction,
        "type": "not-number",
    }


def patch() -> None:
    classification.fit = fit
    helpers.show_image = lambda *_a, **_k: None
    helpers.debug = lambda *_a, **_k: None


patch()
