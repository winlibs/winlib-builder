# Winlibs SBOM metadata

The files under `sbom/` are used by `scripts/generate-sbom.ps1` to write
per-library compliance data into each dependency artifact:

- `share/sbom/<library>.cdx.json`
- `share/sbom/<library>.spdx.json`
- `share/sbom/<library>.openvex.json`, when fixed or not-affected CVEs are listed
- `share/licenses/<library>/...`

Shared document metadata lives in `sbom/document.json`. Each library has its
own file under `sbom/libraries/`; all files are validated against
`sbom/schema.json` before an SBOM is generated.
Generated components refer consumers to the accompanying license and notice
files for copyright information. Set `copyrightText` only to override that
default, such as `NONE` for a public-domain work.

The generated SPDX fragment records the public dependency ZIP name and URL and
the current SPDX license-list version resolved from the official SPDX list.
Binary artifacts are represented at package level; final ZIP checksums belong
in external sidecars created after packaging.

For a normal build, the generator uses the canonical upstream repository and
tag template. For example, brotli `v1.2.0` is identified as brotli `1.2.0`
from `google/brotli`. The generator separately records the checkout repository,
ref, and commit when a Git checkout is available, including builds made from a
`winlibs` fork.

The full Winlibs package version is retained as the artifact version. A trailing
Winlibs rebuild suffix such as `-1` is removed from the default upstream version.
Set `version.stripRebuildSuffix` to `false` when a trailing dash-number is part
of the upstream version itself, as it is for ImageMagick releases.
Tag templates can use `{version}`, `{versionDash}`, or `{versionUnderscore}` to
match an upstream project's tag convention.

Architecture, compiler, and target PHP version are recorded as properties. They
are not part of the component identity because all Windows variants built from
the same Winlibs tag use the same source.

Use `components` for source-built libraries embedded in an artifact. SBOMs
found below `deps/share/sbom` and vcpkg SPDX files found below
`deps-install/share` are merged automatically, so they do not need duplicate
metadata.

For packages covered by both standard and custom licenses, put the complete
SPDX expression in `license.expression` and define custom license text in
`license.extractedLicenses`.

When a Winlibs tag differs from the upstream release, add a `patchedBuilds`
entry. `fixedCves` is optional; use it only when the Winlibs fork backports a
security fix to an older release, or carries a fix for which upstream has not
yet published a release. Do not list CVEs already fixed by the upstream tag.

```json
{
  "tag": "libssh2-1.11.1-2",
  "upstream": {
    "repository": "libssh2/libssh2",
    "tag": "libssh2-1.11.1",
    "version": "1.11.1"
  },
  "fork": {
    "repository": "winlibs/libssh2",
    "tag": "libssh2-1.11.1-2"
  },
  "fixedCves": [
    {
      "id": "CVE-2026-7598",
      "source": "NVD",
      "url": "https://nvd.nist.gov/vuln/detail/CVE-2026-7598",
      "detail": "Fixed by backporting the upstream bounds check."
    }
  ]
}
```

This produces CycloneDX pedigree and `resolved_with_pedigree` analysis plus an
OpenVEX `fixed` statement scoped to the exact Winlibs artifact identity. The
product also carries its canonical purl as an alternate identifier so scanners
can match it to the SBOM component; it does not claim that unrelated builds of
the generic upstream package are fixed.

Use `notAffectedCves` only after correcting the component's upstream identity
and confirming that a current scanner still reports a CVE which does not apply.
Prefer a `patchedBuilds` entry when the assertion is specific to one Winlibs
tag. Library-level entries are appropriate when the reason applies to every
artifact, such as a module or platform-specific package that Winlibs never
ships. Include references supporting the assertion. The generator emits
CycloneDX `not_affected` analysis and an OpenVEX `not_affected` statement with
the supplied justification.
