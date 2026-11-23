# TrPaper

[![macOS](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)](https://www.apple.com/macos/)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-555)](#系统要求)
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](LICENSE)

TrPaper 是一款轻量、专注的 macOS 论文翻译应用：拖入英文论文 PDF，使用
DeepSeek Flash 分段翻译，然后下载保留原始页数、图片、公式和整体版式的中文
PDF。它没有论文库、聊天或播客功能，只完成 PDF 翻译这一件事。

> TrPaper 基于开源项目
> [PDFMathTranslate / pdf2zh](https://github.com/PDFMathTranslate/PDFMathTranslate)
> 构建。衷心感谢 PDFMathTranslate 的维护者和所有贡献者，让保留版式的 PDF
> 翻译能力可以被社区使用和继续改进。

## 功能

- 原生 AppKit 窗口，支持点击选择或拖入 PDF
- 通过本地 ONNX 模型识别正文、标题、图片、表格和公式区域
- 使用 `deepseek-flash` 并行翻译正文段落
- 将译文写回原始 PDF 坐标，并恢复高清图片、矢量图和公式
- 自动识别 `References`、`Reference List`、`Bibliography`、`Works Cited`
  和“参考文献”；该标题及后续内容保持原文且不消耗翻译 Token
- 输出文件保存在“下载”文件夹，重名时自动追加序号
- DeepSeek API 密钥写入 macOS 钥匙串，不会写进 App、源码或 Git

## 系统要求

- Apple Silicon Mac（M1 或更新）
- macOS 13 Ventura 或更新版本
- Python 3.11
- Xcode Command Line Tools
- 有可用额度的 [DeepSeek API 密钥](https://platform.deepseek.com/api_keys)
- 首次构建需要联网下载 Python 依赖、约 72 MB 的版面模型和中文字体

当前仓库发布的是完整源码。由于尚未提供 Apple Developer ID 公证的二进制
安装包，请从源码构建；构建完成后，日常使用只需从“应用程序”中打开
TrPaper，不需要再次启动 Python 或配置环境。

## 安装

### 1. 克隆独立仓库

```bash
git clone https://github.com/Arrrres2025/TrPaper.git
cd TrPaper
```

### 2. 安装基础工具

如果尚未安装 Xcode Command Line Tools：

```bash
xcode-select --install
```

确认 Python 版本：

```bash
python3 --version
```

建议使用 Python 3.11。构建脚本会在仓库内自动创建 `.venv`，不会使用或修改
EssayPod 的环境。

### 3. 配置 DeepSeek API 密钥

```bash
cp .env.example .env
```

打开 `.env`，把占位内容替换为自己的密钥：

```dotenv
DEEPSEEK_API_KEY=your_deepseek_api_key_here
```

`.env` 已被 `.gitignore` 排除，请勿把真实密钥提交到 Git。

### 4. 构建并安装

```bash
chmod +x build-worker.sh build-macos-app.sh
./build-worker.sh
./build-macos-app.sh --install
```

首次构建需要下载和封装依赖，耗时会比后续构建长。完成后应用位于：

```text
/Applications/TrPaper.app
```

## 使用方法

1. 在 macOS“应用程序”文件夹中打开 **TrPaper**。
2. 将英文论文 PDF 拖入窗口，或点击“选择 PDF”。
3. 点击“开始翻译”，等待版面识别和翻译完成。
4. 点击“在 Finder 中显示”打开译文。

默认输出位置为 `~/Downloads`，文件名类似：

```text
paper-deepseek-layout-zh.pdf
```

## 工作流程

1. 每页渲染为图像，并由 DocLayout-YOLO ONNX 模型识别版面区域。
2. 从 PDF 文本层提取段落，保留公式、图片和表格区域。
3. 定位参考文献边界，仅把边界之前的段落发送给 DeepSeek Flash。
4. 根据原坐标、栏宽和字号将中文写回 PDF 内容流。
5. 根据媒体清单恢复原论文中的图片、矢量图、表格和独立公式。
6. 将完整译文 PDF 保存到“下载”文件夹。

## 项目结构

- `main.m`：原生 AppKit 界面、拖放、钥匙串和工作进程管理
- `worker.py`：版面检测、参考文献边界和翻译任务编排
- `translation_pdf_restore.py`：恢复 PDF 图片、表格、矢量图和公式
- `vendor/pdf2zh`：基于 pdf2zh 1.9.11 修改的版式翻译管线
- `vendor_sources`：版面模型加载器和上游许可证副本
- `build-worker.sh`：生成包含 Python 运行时的独立工作进程
- `build-macos-app.sh`：组装、签名并安装 macOS App

## 开发与重新构建

修改代码后重新执行：

```bash
./build-worker.sh
./build-macos-app.sh --install
```

如果 Python 位于自定义路径，可以指定：

```bash
TRPAPER_PYTHON=/path/to/python ./build-worker.sh
```

可再生成的目录 `.venv/`、`worker-dist/` 和所有 `.app`、`.dmg`、`.zip`
均不会提交到仓库。

## 已知限制

- 当前构建仅面向 Apple Silicon，尚未提供 Intel Mac 版本。
- 普通论文通过 PDF 文本层提取内容；没有文字层的纯扫描 PDF 尚未提供 OCR
  回退。
- 非常复杂的多栏页面或异常字体编码可能产生少量文字位置偏差。
- 参考文献边界依赖独立章节标题；使用非常规标题时可能无法自动识别。
- DeepSeek API 的费用、速率限制和服务可用性由 DeepSeek 决定。

## 上游项目与致谢

TrPaper 包含并修改了
[PDFMathTranslate / pdf2zh 1.9.11](https://github.com/PDFMathTranslate/PDFMathTranslate)
的源代码。上游项目采用 AGPL-3.0 许可证，TrPaper 因此同样以 AGPL-3.0
发布。上游许可证副本位于
[`vendor/PDFMathTranslate-LICENSE`](vendor/PDFMathTranslate-LICENSE)，详细修改和
第三方说明见 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。

再次感谢 PDFMathTranslate 的维护者及所有贡献者。TrPaper 是独立项目，与上游
维护者不存在官方隶属或背书关系。

## 许可证

本项目采用 [GNU Affero General Public License v3.0](LICENSE) 发布。
