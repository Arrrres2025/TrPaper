#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PYTHON="${TRPAPER_PYTHON:-$SCRIPT_DIR/.venv/bin/python}"
VENDOR_DIR="$SCRIPT_DIR/vendor"
DIST_DIR="$SCRIPT_DIR/worker-dist"
WORK_DIR="$(/usr/bin/mktemp -d "${TMPDIR%/}/TrPaper-worker-build.XXXXXX")"
trap 'find "$WORK_DIR" -depth -delete 2>/dev/null || true' EXIT

if [[ -n "${TRPAPER_PYTHON:-}" && ! -x "$PYTHON" ]]; then
  print -u2 "TRPAPER_PYTHON 不可执行：$PYTHON"
  exit 1
fi

if [[ ! -x "$PYTHON" ]]; then
  SYSTEM_PYTHON="$(command -v python3 || true)"
  [[ -n "$SYSTEM_PYTHON" ]] || { print -u2 "缺少 Python 3.11。请先安装 Python 3.11。"; exit 1; }
  "$SYSTEM_PYTHON" -c 'import sys; raise SystemExit(0 if sys.version_info[:2] == (3, 11) else 1)' || {
    print -u2 "需要 Python 3.11，当前为：$($SYSTEM_PYTHON --version 2>&1)"
    exit 1
  }
  "$SYSTEM_PYTHON" -m venv "$SCRIPT_DIR/.venv"
fi

"$PYTHON" -c 'import sys; raise SystemExit(0 if sys.version_info[:2] == (3, 11) else 1)' || {
  print -u2 "需要 Python 3.11，当前为：$($PYTHON --version 2>&1)"
  exit 1
}

if ! "$PYTHON" -c 'import PyInstaller, babeldoc, deepl, ollama, onnxruntime, openai, pikepdf, pymupdf, requests, xinference_client; from azure.ai.translation.text import TextTranslationClient' >/dev/null 2>&1; then
  "$PYTHON" -m pip install --upgrade pip
  "$PYTHON" -m pip install -r "$SCRIPT_DIR/requirements-build.txt"
fi

[[ -f "$VENDOR_DIR/pdf2zh/high_level.py" ]] || { print -u2 "缺少 vendor/pdf2zh 源码。"; exit 1; }

# BabelDOC verifies hashes and downloads these build assets into its cache.
"$PYTHON" - <<'PY'
from babeldoc.assets.assets import get_doclayout_onnx_model_path, get_font_and_metadata

get_doclayout_onnx_model_path()
get_font_and_metadata("SourceHanSerifCN-Regular.ttf")
PY

MODEL="${TRPAPER_MODEL_PATH:-$HOME/.cache/babeldoc/models/doclayout_yolo_docstructbench_imgsz1024.onnx}"
FONT="${TRPAPER_FONT_PATH:-$HOME/.cache/babeldoc/fonts/SourceHanSerifCN-Regular.ttf}"
[[ -f "$MODEL" ]] || { print -u2 "版面模型下载失败：$MODEL"; exit 1; }
[[ -f "$FONT" ]] || { print -u2 "中文字体下载失败：$FONT"; exit 1; }

/bin/rm -rf "$DIST_DIR"
/bin/mkdir -p "$DIST_DIR/resources"

"$PYTHON" -m PyInstaller \
  --noconfirm \
  --onedir \
  --name TrPaperWorker \
  --distpath "$DIST_DIR" \
  --workpath "$WORK_DIR" \
  --specpath "$WORK_DIR" \
  --paths "$VENDOR_DIR" \
  --collect-all onnxruntime \
  --collect-all pymupdf \
  --collect-all babeldoc \
  --hidden-import pdf2zh.high_level \
  --hidden-import pdf2zh.doclayout \
  --hidden-import pdf2zh.translator \
  --hidden-import pdf2zh.markdown_export \
  --hidden-import translation_pdf_restore \
  --hidden-import peewee \
  "$SCRIPT_DIR/worker.py"

/bin/cp "$MODEL" "$DIST_DIR/resources/doclayout.onnx"
/bin/cp "$FONT" "$DIST_DIR/resources/SourceHanSerifCN-Regular.ttf"
/bin/cp "$SCRIPT_DIR/LICENSE" "$DIST_DIR/resources/LICENSE"
/bin/cp "$SCRIPT_DIR/THIRD_PARTY_NOTICES.md" "$DIST_DIR/resources/THIRD_PARTY_NOTICES.md"
/bin/cp "$VENDOR_DIR/PDFMathTranslate-LICENSE" "$DIST_DIR/resources/PDFMathTranslate-LICENSE"

print "已构建工作进程：$DIST_DIR/TrPaperWorker/TrPaperWorker"
