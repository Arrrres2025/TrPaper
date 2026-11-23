#!/usr/bin/env python3
"""Self-contained pdf2zh worker used by the native TrPaper application."""

from __future__ import annotations

import argparse
import json
import multiprocessing
import os
import re
import shutil
import sys
import tempfile
import traceback
from pathlib import Path


REFERENCE_HEADINGS = {
    "reference",
    "references",
    "reference list",
    "bibliography",
    "works cited",
    "literature cited",
    "cited literature",
    "notes and references",
    "references and notes",
    "参考文献",
}


def emit(kind: str, **payload: object) -> None:
    print(
        "TRPAPER_EVENT " + json.dumps({"kind": kind, **payload}, ensure_ascii=False),
        flush=True,
    )


def valid_pdf(path: Path) -> bool:
    try:
        return path.stat().st_size > 5 and path.read_bytes()[:5] == b"%PDF-"
    except OSError:
        return False


def writable_model_path(bundled_model: Path) -> Path:
    """Copy the bundled model to a writable cache before ORT optimizes it."""
    cache_dir = Path.home() / "Library" / "Caches" / "TrPaper"
    cache_dir.mkdir(parents=True, exist_ok=True)
    cached_model = cache_dir / "doclayout.onnx"
    if not cached_model.is_file() or cached_model.stat().st_size != bundled_model.stat().st_size:
        temporary = cache_dir / "doclayout.onnx.tmp"
        shutil.copy2(bundled_model, temporary)
        temporary.replace(cached_model)
        (cache_dir / "doclayout.onnx.optimized").unlink(missing_ok=True)
    return cached_model


def normalize_section_heading(text: str) -> str:
    first_line = next((line.strip() for line in text.splitlines() if line.strip()), "")
    value = first_line.casefold().replace("\u00a0", " ")
    value = re.sub(
        r"^(?:section\s+)?(?:\d+(?:\.\d+)*|[ivxlcdm]+|[a-z])"
        r"(?:\s*[.：:\-–—]\s*|\s+)",
        "",
        value,
        flags=re.IGNORECASE,
    )
    value = re.sub(r"\s+", " ", value).strip(" .:：-–—")
    return value


def find_reference_boundary(blocks: list[object]) -> object | None:
    candidates = []
    for block in blocks:
        text = str(getattr(block, "text", "") or "")
        heading = normalize_section_heading(text)
        if heading not in REFERENCE_HEADINGS:
            continue
        block_type = str(getattr(block, "type", "") or "")
        first_line = next((line.strip() for line in text.splitlines() if line.strip()), "")
        if block_type != "title" and len(first_line) > 80:
            continue
        candidates.append(block)
    if not candidates:
        return None
    candidates.sort(key=lambda block: (int(block.page), float(block.bbox[1])))
    page_count = max(int(getattr(block, "page", 0)) for block in blocks) + 1
    # A table of contents can contain a standalone "References" entry. Prefer
    # the first candidate in the latter 65% of the paper; this still accepts
    # short two- and three-page papers while ignoring normal front matter.
    plausible_start_page = int(page_count * 0.35)
    return next(
        (
            block
            for block in candidates
            if int(block.page) >= plausible_start_page
        ),
        candidates[-1],
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--input")
    parser.add_argument("--output")
    parser.add_argument("--model", required=True)
    parser.add_argument("--font", required=True)
    parser.add_argument("--threads", type=int, default=3)
    args = parser.parse_args()

    model_path = Path(args.model).expanduser().resolve()
    font_path = Path(args.font).expanduser().resolve()
    if args.self_test:
        if not model_path.is_file() or not font_path.is_file():
            emit("error", message="版面模型或中文字体缺失。")
            return 2
        emit("stage", message="正在检查版面翻译引擎…", progress=20)
        from pdf2zh import TRPAPER_VENDOR_BUILD
        from pdf2zh.doclayout import OnnxModel, set_backend
        from pdf2zh.high_level import translate  # noqa: F401
        from pdf2zh.markdown_export import build_document_blocks  # noqa: F401
        from translation_pdf_restore import restore_translated_pdf_media  # noqa: F401

        if not TRPAPER_VENDOR_BUILD:
            emit("error", message="未加载 TrPaper 内置的 pdf2zh 翻译管线。")
            return 2
        set_backend("cpu")
        OnnxModel(str(writable_model_path(model_path)))
        emit("done", message="版面翻译引擎可用", progress=100)
        return 0
    if not args.input or not args.output:
        parser.error("--input and --output are required unless --self-test is used")

    source = Path(args.input).expanduser().resolve()
    destination = Path(args.output).expanduser().resolve()
    api_key = os.environ.get("DEEPSEEK_API_KEY", "").strip()

    if not api_key:
        emit("error", message="未找到 DeepSeek API 密钥。")
        return 2
    for path, label in ((source, "输入 PDF"), (model_path, "版面模型"), (font_path, "中文字体")):
        if not path.is_file():
            emit("error", message=f"{label}不存在：{path}")
            return 2
    if not valid_pdf(source):
        emit("error", message="输入文件不是有效的 PDF。")
        return 2

    os.environ["NOTO_FONT_PATH"] = str(font_path)
    os.environ["DEEPSEEK_MODEL"] = "deepseek-flash"
    os.environ.setdefault("OMP_NUM_THREADS", "1")

    work_dir = Path(tempfile.mkdtemp(prefix="trpaper-pdf2zh-"))
    try:
        emit("stage", message="正在加载论文版面识别模型…", progress=4)
        from pdf2zh.doclayout import OnnxModel, set_backend
        from pdf2zh.high_level import translate
        from pdf2zh.markdown_export import build_document_blocks, write_media_manifest
        from translation_pdf_restore import restore_translated_pdf_media
        import pymupdf

        set_backend("cpu")
        model = OnnxModel(str(writable_model_path(model_path)))

        emit("stage", message="正在识别图片、表格、公式和文字区域…", progress=7)
        assets_dir = work_dir / "assets"
        assets_dir.mkdir(parents=True, exist_ok=True)
        blocks = build_document_blocks(source, assets_dir, model)
        manifest_path = write_media_manifest(blocks, work_dir)

        with pymupdf.open(source) as source_document:
            page_count = source_document.page_count
            page_heights = [page.rect.height for page in source_document]
        boundary = find_reference_boundary(blocks)
        translate_pages = list(range(page_count))
        reference_env: dict[str, str] = {}
        if boundary is not None:
            reference_page = int(boundary.page)
            reference_y_top = float(boundary.bbox[1])
            page_height = page_heights[reference_page]
            starts_near_top = reference_y_top <= page_height * 0.20
            translate_pages = list(
                range(reference_page if starts_near_top else reference_page + 1)
            )
            reference_env = {
                "TRPAPER_REFERENCE_PAGE": str(reference_page),
                "TRPAPER_REFERENCE_Y_TOP": str(reference_y_top),
            }
            emit(
                "stage",
                message=f"已定位参考文献：第 {reference_page + 1} 页；该标题及后续内容保留原文。",
                progress=27,
            )

            payload = json.loads(manifest_path.read_text(encoding="utf-8"))
            translated_page_set = set(translate_pages)
            payload["media"] = [
                item
                for item in payload.get("media", [])
                if int(item.get("page_index", -1)) in translated_page_set
            ]
            manifest_path.write_text(
                json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
            )

        if not translate_pages:
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
            emit(
                "done",
                message="参考文献位于首页，已保留原文 PDF",
                output=str(destination),
                progress=100,
            )
            return 0

        def progress_callback(progress: object) -> None:
            current = int(getattr(progress, "n", 0) or 0)
            total = max(1, int(getattr(progress, "total", 1) or 1))
            percent = 30 + int((current / total) * 60)
            emit(
                "progress",
                message=f"正在识别版面并翻译：第 {current}/{total} 页",
                current=current,
                total=total,
                progress=min(90, percent),
            )

        emit("stage", message="正在分段调用 DeepSeek Flash 翻译…", progress=30)
        results = translate(
            files=[str(source)],
            output=str(work_dir),
            pages=translate_pages,
            lang_in="en",
            lang_out="zh",
            service="deepseek:deepseek-flash",
            thread=max(1, min(args.threads, 4)),
            callback=progress_callback,
            model=model,
            envs={
                "DEEPSEEK_API_KEY": api_key,
                "DEEPSEEK_MODEL": "deepseek-flash",
                **reference_env,
            },
            skip_subset_fonts=False,
        )
        if not results:
            raise RuntimeError("pdf2zh 没有生成译文。")
        mono_path = Path(results[0][0])
        if not valid_pdf(mono_path):
            raise RuntimeError("pdf2zh 生成的文件不是有效 PDF。")

        emit("stage", message="正在恢复原论文的图片、表格和公式…", progress=93)
        restore_result = restore_translated_pdf_media(
            source_pdf=source,
            translated_pdf=mono_path,
            manifest_path=manifest_path,
            force=True,
        )
        emit(
            "stage",
            message=f"已恢复 {int(restore_result.get('count', 0))} 个媒体区域，正在保存…",
            progress=97,
        )
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(mono_path, destination)
        if not valid_pdf(destination):
            raise RuntimeError("译文 PDF 保存失败。")
        emit("done", message="翻译完成", output=str(destination), progress=100)
        return 0
    except Exception as exc:  # noqa: BLE001 - boundary process must report all failures
        traceback.print_exc(file=sys.stderr)
        emit("error", message=str(exc) or exc.__class__.__name__)
        return 1
    finally:
        shutil.rmtree(work_dir, ignore_errors=True)


if __name__ == "__main__":
    multiprocessing.freeze_support()
    raise SystemExit(main())
