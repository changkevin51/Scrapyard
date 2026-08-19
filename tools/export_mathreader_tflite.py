"""Load MathReader's Keras 2 .h5 CNN and write python/mathreader_app/symbol_cnn.tflite.

Run on a dev machine with TensorFlow (Keras 3 is fine). The Flutter app ships
the TFLite file and never loads TensorFlow.
"""

from __future__ import annotations

import argparse
import copy
import json
import os
import sys
import tempfile
import urllib.request
import zipfile

H5_NAME = "model_11-07-2020_23-54-57.h5"
WHEEL_URL = (
    "https://files.pythonhosted.org/packages/"
    "57/8e/e06df09d154f4f2811fd48f863075b5cef068f4563c3fbc3aeb09996d74f/"
    "mathreader-0.163-py3-none-any.whl"
)


def _repo_root() -> str:
    return os.path.abspath(os.path.join(os.path.dirname(__file__), os.pardir))


def _default_out() -> str:
    return os.path.join(_repo_root(), "python", "mathreader_app", "symbol_cnn.tflite")


def _find_h5() -> str | None:
    try:
        from mathreader.config import Configuration

        path = os.path.join(
            Configuration().package_path, "ann_models", "model", H5_NAME
        )
        if os.path.isfile(path):
            return path
    except Exception:
        pass
    return None


def _download_h5(dest_dir: str) -> str:
    wheel = os.path.join(dest_dir, "mathreader.whl")
    print(f"Downloading MathReader wheel to extract {H5_NAME}...")
    urllib.request.urlretrieve(WHEEL_URL, wheel)
    with zipfile.ZipFile(wheel) as zf:
        member = f"mathreader/ann_models/model/{H5_NAME}"
        zf.extract(member, dest_dir)
    return os.path.join(dest_dir, member)


def _load_legacy_cnn(path: str):
    """Rebuild Sequential with Input((28,28,1)) so Keras 3 does not add a extra batch dim."""
    import h5py
    from keras import Input, Sequential
    from keras.src.legacy.saving import saving_utils
    from keras.src.legacy.saving.legacy_h5_format import (
        load_weights_from_hdf5_group_by_name,
        safe_get_h5_group,
    )

    with h5py.File(path, "r") as f:
        raw = f.attrs["model_config"]
        if hasattr(raw, "decode"):
            raw = raw.decode("utf-8")
        cfg = json.loads(raw)
        model = Sequential(name=cfg["config"].get("name", "sequential"))
        model.add(Input(shape=(28, 28, 1)))
        for layer_config in cfg["config"]["layers"]:
            layer_config = copy.deepcopy(layer_config)
            layer_config.get("config", {}).pop("batch_input_shape", None)
            layer_config.get("config", {}).pop("input_shape", None)
            model.add(saving_utils.model_from_config(layer_config))
        load_weights_from_hdf5_group_by_name(
            safe_get_h5_group(f, "model_weights"), model, skip_mismatch=True
        )
    return model


def _convert(model, out_path: str) -> None:
    import numpy as np
    import tensorflow as tf

    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS]
    converter.optimizations = []
    tflite_model = converter.convert()
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "wb") as f:
        f.write(tflite_model)

    interpreter = tf.lite.Interpreter(model_content=tflite_model)
    interpreter.allocate_tensors()
    inp = interpreter.get_input_details()[0]
    out = interpreter.get_output_details()[0]
    sample = np.zeros((1, 28, 28, 1), dtype=inp["dtype"])
    interpreter.set_tensor(inp["index"], sample)
    interpreter.invoke()
    pred = interpreter.get_tensor(out["index"])
    print(f"Wrote {out_path} ({len(tflite_model)} bytes)")
    print(f"input={inp['shape']} {inp['dtype']} output={pred.shape} {pred.dtype}")
    # dense_2 is softmax over 30 classes (labels_parser 0-29). "=" is listed as 30
    # in config_all.json but is not a CNN output.
    if pred.shape[-1] != 30:
        raise SystemExit(
            f"Expected 30 softmax classes (labels_parser 0-29), got {pred.shape}"
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--h5", default="", help="Path to MathReader .h5")
    parser.add_argument("--out", default=_default_out())
    args = parser.parse_args()

    h5 = args.h5 or _find_h5()
    tmp = None
    if not h5:
        tmp = tempfile.TemporaryDirectory()
        h5 = _download_h5(tmp.name)

    print(f"Loading {h5}")
    try:
        import tensorflow as tf

        model = tf.keras.models.load_model(h5)
    except Exception as exc:
        print(f"load_model failed ({exc!r}); rebuilding with Keras 3 Input() shim")
        model = _load_legacy_cnn(h5)

    _convert(model, args.out)
    if tmp is not None:
        tmp.cleanup()
    return 0


if __name__ == "__main__":
    sys.exit(main())
