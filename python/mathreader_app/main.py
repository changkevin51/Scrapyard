"""Stdlib HTTP sidecar that runs MathReader inside Serious Python.

The server binds immediately so Dart can health-check before OpenCV/TFLite
finish loading. Recognition imports happen on first POST (and in a warmup
thread).
"""

from __future__ import annotations

import json
import os
import sys
import threading
import traceback
from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import TCPServer, ThreadingMixIn

MODEL_NAME = "mathreader"
# Bump when the HTTP handler changes so Dart can tell a stale extract/cache.
SIDECAR_REV = "4"
DEFAULT_PORT = 17831

recognize_lock = threading.Lock()
_recognizer = None
_load_error = None
_android_log_write = None
_last_lex = ""


def _init_android_log() -> None:
    """Write to logcat; sys.stderr is often invisible under Serious Python."""
    global _android_log_write
    if _android_log_write is not None:
        return
    try:
        import ctypes

        liblog = ctypes.CDLL("liblog.so")
        liblog.__android_log_write.argtypes = [
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_char_p,
        ]
        liblog.__android_log_write.restype = ctypes.c_int
        _android_log_write = liblog.__android_log_write
    except Exception:
        _android_log_write = False


def _log(msg: str) -> None:
    line = "[mathreader] " + msg
    try:
        sys.stderr.write(line + "\n")
        sys.stderr.flush()
    except Exception:
        pass
    try:
        _init_android_log()
        if _android_log_write:
            _android_log_write(4, b"mathreader", line.encode("utf-8", "replace"))
    except Exception:
        pass
    try:
        path = os.environ.get(
            "MATHREADER_LOG_PATH",
            os.path.join(os.getcwd(), "mathreader.log"),
        )
        parent = os.path.dirname(path)
        if parent:
            os.makedirs(parent, exist_ok=True)
        with open(path, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass


def _get_recognizer():
    global _recognizer, _load_error
    if _recognizer is not None:
        return _recognizer
    if _load_error is not None:
        raise RuntimeError(_load_error)
    try:
        _log("loading MathReader / TFLite…")
        import mathreader_tflite  # noqa: F401
        from mathreader.api import HME_Recognizer

        _install_lex_capture()
        _install_grammar_fallback()
        _install_recognizer_fallback()
        _install_looser_baseline()
        _recognizer = HME_Recognizer()
        _log("MathReader ready sidecar=%s" % SIDECAR_REV)
        return _recognizer
    except Exception as exc:
        _load_error = traceback.format_exc()
        _log("MathReader load failed:\n" + _load_error)
        raise RuntimeError(_load_error) from exc


def _warmup() -> None:
    try:
        _get_recognizer()
    except Exception:
        pass


def _decode_image_field(raw: str) -> str:
    text = (raw or "").strip()
    if "," in text and text.lower().startswith("data:"):
        return text.split(",", 1)[1]
    return text


def _join_labels(val) -> str:
    if isinstance(val, str) and val.strip():
        return val.strip()
    if not isinstance(val, list) or not val:
        return ""
    parts = []
    for item in val:
        if isinstance(item, str) and item and item != "contains":
            parts.append(item)
        elif isinstance(item, dict):
            label = item.get("label")
            if isinstance(label, str) and label and label != "contains":
                parts.append(label)
    return "".join(parts)


def _as_latex_string(val) -> str:
    if isinstance(val, str) and val.strip():
        return val.strip()
    if isinstance(val, dict):
        for key in (
            "latex_string_original",
            "latex_string",
            "lstring",
            "string",
        ):
            s = val.get(key)
            if isinstance(s, str) and s.strip():
                return s.strip()
        joined = _join_labels(val.get("latex_list")) or _join_labels(val.get("latex"))
        if joined:
            return joined
    return _join_labels(val)


def _remember_lex(raw) -> None:
    """Keep the first (pre-yacc-fix) lex string; later retries are worse."""
    global _last_lex
    text = _as_latex_string(raw)
    if text and not _last_lex:
        _last_lex = text


def _guess_from_error(exc) -> str:
    """GrammarError stores the lex string on .data, not on the recognizer."""
    return _as_latex_string(getattr(exc, "data", None))


def _guess_latex(hme) -> str:
    """Best-effort string the model produced before a grammar/parse failure."""
    if hme is None:
        return ""
    for attr in (
        "latex_string_original",
        "expression_after_grammar",
        "expression_after_parser",
        "parsed_expression",
    ):
        extracted = _as_latex_string(getattr(hme, attr, None))
        if extracted:
            return extracted
    return _last_lex


def _install_lex_capture() -> None:
    """Stash the lex string as soon as MathReader prints/tokenizes it.

    GrammarError is raised *after* that, and often never copies the string
    onto the recognizer — so HTTP 500 was returning latex="".
    """
    try:
        import mathreader.hme_parser.grammar.lex as lex_mod

        orig_lexer = lex_mod.LatexLexer

        def wrapped_lexer(tstring):
            _remember_lex(tstring)
            return orig_lexer(tstring)

        lex_mod.LatexLexer = wrapped_lexer
        _log("lex capture installed")
    except Exception as exc:
        _log("lex capture not installed: %s" % exc)

    try:
        from mathreader.hme_parser.parser import Parser

        orig_organize = Parser.organize_latex_data

        def organize(self, tstring):
            data = orig_organize(self, tstring)
            if isinstance(data, dict):
                _remember_lex(data.get("latex_string"))
            return data

        Parser.organize_latex_data = organize

        orig_parse = Parser.to_parse

        def to_parse(self):
            try:
                return orig_parse(self)
            except Exception as exc:
                guess = _guess_from_error(exc) or _last_lex
                _log("parser fallback latex=%s err=%s" % (guess, exc))
                if not guess:
                    raise
                return {
                    "latex": guess,
                    "latex_list": None,
                    "latex_string": guess,
                    "latex_string_original": guess,
                    "yacc_errors_history": None,
                    "yacc_pure_errors": None,
                    "lex_errors_history": None,
                    "lex_pure_errors": None,
                    "latex_before_cg": [],
                    "tree": None,
                    "tlist": None,
                }

        Parser.to_parse = to_parse
        _log("parser capture installed")
    except Exception as exc:
        _log("parser capture not installed: %s" % exc)


def _install_grammar_fallback() -> None:
    """MathReader's yacc rejects times-as-`x` and similar; we still want the lex string."""
    try:
        from mathreader.hme_parser.check_grammar import CheckGrammar
    except Exception as exc:
        _log("grammar fallback not installed: %s" % exc)
        return

    orig = CheckGrammar.check

    def check(self, latex_data):
        if isinstance(latex_data, dict):
            _remember_lex(latex_data)
        try:
            return orig(self, latex_data)
        except Exception as exc:
            data = getattr(exc, "data", None)
            latex_string = _as_latex_string(data) or _last_lex
            if not latex_string and isinstance(latex_data, dict):
                latex_string = _as_latex_string(latex_data)
            _log("grammar fallback latex=%s err=%s" % (latex_string, exc))
            return {
                "latex": latex_string,
                "latex_list": (latex_data or {}).get("latex_list"),
                "latex_string": latex_string,
                "latex_string_original": latex_string,
                "yacc_errors_history": None,
                "yacc_pure_errors": None,
                "lex_errors_history": None,
                "lex_pure_errors": None,
            }

    CheckGrammar.check = check
    _log("grammar fallback installed")


def _install_recognizer_fallback() -> None:
    """If grammar still throws, return the lex string instead of HTTP 500."""
    try:
        from mathreader.api import HME_Recognizer
    except Exception as exc:
        _log("recognizer fallback not installed: %s" % exc)
        return

    orig = HME_Recognizer.recognize

    def recognize(self):
        try:
            return orig(self)
        except Exception as exc:
            guess = _guess_from_error(exc) or _guess_latex(self) or _last_lex
            _log("recognize fallback latex=%s err=%s" % (guess, exc))
            if not guess:
                raise
            self.parsed_expression = guess
            return guess, getattr(self, "processed_image", None)

    HME_Recognizer.recognize = recognize
    _log("recognizer fallback installed")


def _install_looser_baseline() -> None:
    """MathReader treats any centroid above ~15% of the previous glyph as a
    superscript. Handwritten + / × / next digits often sit a bit high, so they
    become exponents. Keep true scripts (smaller + clearly above midline).
    """
    try:
        from mathreader.hme_parser.structural_analysis import StructuralAnalysis
    except Exception as exc:
        _log("baseline patch not installed: %s" % exc)
        return

    orig_start = StructuralAnalysis._StructuralAnalysis__start
    orig_overlap = StructuralAnalysis._StructuralAnalysis__overlap

    # CNN labels: - + x * = ( )
    _ops = {10, 17, 24, 29, 30, 11, 12}

    def _true_script(base, cand) -> bool:
        if int(cand["label"]) in _ops:
            return False
        bh = max(float(base["h"]), 1.0)
        if float(cand["h"]) >= bh * 0.72:
            return False
        return cand["centroid"][1] < base["centroid"][1] - 0.22 * bh

    def hor(self, listin, index):
        label = int(listin[index]["label"])
        right = listin[index]["wall"]["right"]
        left = listin[index]["xmin"]
        h = max(float(listin[index]["h"]), 1.0)
        ymin = listin[index]["ymin"]
        ymax = listin[index]["ymax"]
        top = ymin - 0.55 * h
        bottom = ymax + 0.55 * h

        if label == 10 or label in (27, 28, 29, 30):
            top = listin[index]["wall"]["top"]
            bottom = listin[index]["wall"]["bottom"]
        if label == 23:
            left = listin[index]["xmax"]

        a = -1
        if label in range(10, 17):
            region = [[listin[index]["xmax"], top], [right, bottom]]
            a = orig_start(self, listin, region)
        else:
            for s in range(0, len(listin)):
                if listin[s]["checked"]:
                    continue
                symbol = listin[s]
                cx, cy = symbol["centroid"][0], symbol["centroid"][1]
                if not (left <= cx <= right and top <= cy <= bottom):
                    continue
                if _true_script(listin[index], symbol):
                    continue
                a = s
                break

        if a != -1:
            return orig_overlap(
                self,
                a,
                listin[a]["wall"]["top"],
                listin[a]["wall"]["bottom"],
                listin,
            )
        return -1

    StructuralAnalysis._StructuralAnalysis__hor = hor
    _log("looser baseline installed")


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:
        _log(fmt % args)

    def address_string(self) -> str:
        # Default uses getfqdn() which reverse-DNS hangs on Android.
        return self.client_address[0]

    def _send_json(self, code: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        if self.path.split("?", 1)[0] in ("/health", "/model", "/"):
            self._send_json(
                200,
                {
                    "ok": True,
                    "model": MODEL_NAME,
                    "sidecar": SIDECAR_REV,
                    "loaded": _recognizer is not None,
                    "error": _load_error,
                },
            )
            return
        self._send_json(404, {"error": "not found"})

    def do_POST(self) -> None:  # noqa: N802
        if self.path.split("?", 1)[0] != "/recognize":
            self._send_json(404, {"error": "not found"})
            return
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length else b"{}"
        global _last_lex
        _last_lex = ""
        hme = None
        try:
            payload = json.loads(raw.decode("utf-8"))
            encoded = _decode_image_field(payload.get("image", ""))
            if not encoded:
                raise ValueError("missing image")
            with recognize_lock:
                hme = _get_recognizer()
                hme.reset()
                hme.load_image(encoded, data_type="base64")
                expression, _processed = hme.recognize()
        except Exception as exc:
            guess = _guess_from_error(exc) or _guess_latex(hme) or _last_lex
            _log(
                "recognize failed guess=%s err=%s\n%s"
                % (guess, exc, traceback.format_exc())
            )
            self._send_json(
                500 if not guess else 200,
                {
                    "latex": guess,
                    "model": MODEL_NAME,
                    "sidecar": SIDECAR_REV,
                    "error": str(exc),
                },
            )
            return
        _log("recognized %s sidecar=%s" % (expression, SIDECAR_REV))
        self._send_json(
            200,
            {
                "latex": expression or "",
                "model": MODEL_NAME,
                "sidecar": SIDECAR_REV,
            },
        )


class _ThreadingHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def server_bind(self) -> None:
        # HTTPServer.server_bind() calls socket.getfqdn(), which can hang
        # for a long time on Android reverse DNS.
        TCPServer.server_bind(self)
        host, port = self.socket.getsockname()[:2]
        self.server_name = str(host)
        self.server_port = port


def _write_ready(path: str, host: str, port: int) -> None:
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump({"host": host, "port": port}, f)
    os.replace(tmp, path)


def main() -> None:
    host = os.environ.get("MATHREADER_HOST", "127.0.0.1")
    start_port = int(os.environ.get("MATHREADER_PORT", str(DEFAULT_PORT)))
    ready_path = os.environ.get(
        "MATHREADER_READY_PATH",
        os.path.join(os.getcwd(), "mathreader_ready.json"),
    )
    _log(
        "starting sidecar rev=%s host=%s port=%s cwd=%s"
        % (SIDECAR_REV, host, start_port, os.getcwd())
    )

    httpd = None
    last_err = None
    for port in range(start_port, start_port + 16):
        try:
            httpd = _ThreadingHTTPServer((host, port), Handler)
            break
        except OSError as exc:
            last_err = exc
            continue
    if httpd is None:
        _log("could not bind: %s" % last_err)
        raise SystemExit(f"Could not bind MathReader HTTP server: {last_err}")

    port = httpd.server_address[1]
    _write_ready(ready_path, host, port)
    _log("listening on http://%s:%s" % (host, port))
    threading.Thread(target=_warmup, name="mathreader-warmup", daemon=True).start()
    try:
        httpd.serve_forever()
    finally:
        try:
            os.remove(ready_path)
        except OSError:
            pass


# dart_bridge executes this file; always start the server.
main()
