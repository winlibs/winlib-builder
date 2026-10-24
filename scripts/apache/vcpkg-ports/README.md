Apache compression overlays
===========================

These ports retain the Windows packaging recipes from microsoft/vcpkg commit
`07f4812200df3d3c931c0c8a6081d3b21fe2bf9f`. The accompanying license applies
to the imported port files.

* zlib uses Winlibs commit `838fe0e338adb28f5662e5ac332b0f0eb96ba93a`
  (`zlib-1.3.2-1`) with the CVE-2026-85091 backport. The distinct vcpkg
  version `1.3.2-winlibs.1` separates it from an unpatched 1.3.2 port.
* Brotli uses upstream `v1.2.1`.

Both downloads are pinned by SHA-512. The Apache SBOM metadata identifies the
zlib overlay and its fixed CVE; update it together with the port.
