import logging

log = logging.getLogger(__name__)

__version__ = "1.9.11"
# This vendored copy contains TrPaper modifications made in 2026. The marker
# lets the frozen worker reject an accidentally imported upstream wheel.
TRPAPER_VENDOR_BUILD = True
__author__ = "Byaidu"
__all__ = ["translate", "translate_stream"]


def __getattr__(name):
    if name in {"translate", "translate_stream"}:
        from pdf2zh.high_level import translate, translate_stream

        return {"translate": translate, "translate_stream": translate_stream}[name]
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
