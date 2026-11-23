# Third-party notices

## PDFMathTranslate / pdf2zh

TrPaper incorporates and modifies source code from
[PDFMathTranslate](https://github.com/PDFMathTranslate/PDFMathTranslate), also
known as `pdf2zh`, version 1.9.11. These TrPaper modifications were made in
2026.

Copyright belongs to the PDFMathTranslate authors and contributors. The
upstream project is licensed under the GNU Affero General Public License,
version 3. A verbatim copy of that license is available in
[`vendor/PDFMathTranslate-LICENSE`](vendor/PDFMathTranslate-LICENSE) and in the
repository root as [`LICENSE`](LICENSE).

TrPaper-specific changes include:

- a native AppKit application and self-contained macOS packaging;
- DeepSeek Flash as the translation service;
- restoration of pictures, tables, vector graphics, and formulas after
  translation;
- automatic preservation of the References section and subsequent pages;
- progress events and integration with the macOS Keychain.

Thank you to the PDFMathTranslate maintainers and every contributor for making
high-quality, layout-preserving PDF translation available as open source.

TrPaper is an independent project and is not endorsed by or affiliated with the
PDFMathTranslate maintainers.

## Build-time assets

The build process downloads the DocLayout-YOLO ONNX model and Source Han Serif
CN font through BabelDOC's verified asset downloader. These binary assets are
not stored in this source repository and remain subject to their respective
upstream licenses.
