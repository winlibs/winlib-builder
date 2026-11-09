Apache compression overlays
===========================

These ports retain the Windows packaging recipes from microsoft/vcpkg commit
`07f4812200df3d3c931c0c8a6081d3b21fe2bf9f`. The accompanying license applies
to the imported port files.

* zlib 1.4 uses `libz.lib` for shared linking and `libzs.lib` for static
  linking on MSVC. The shared runtime is `libz.dll`.
* Brotli uses upstream `v1.2.1`.

Both downloads are pinned by SHA-512.
