Offline chat renderer

Vendored browser distributions (no runtime CDN or network requests):
- markdown-it 14.1.0: https://registry.npmjs.org/markdown-it/-/markdown-it-14.1.0.tgz
  dist/markdown-it.min.js, LICENSE (MIT)
- KaTeX 0.16.22: https://registry.npmjs.org/katex/-/katex-0.16.22.tgz
  dist/katex.min.js, dist/katex.min.css, dist/fonts/*.woff2, LICENSE (MIT)

The corresponding license texts are included in this folder.
renderer.js adds math delimiters before Markdown escape handling, so code
spans/fences stay literal and TeX backslashes reach KaTeX intact.
Supported delimiters: \(...\), \[...\], $...$, $$...$$.
Raw HTML is displayed as text. Remote images are represented by their alt text.
Links open in the system handler only following an explicit click.
