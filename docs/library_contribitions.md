# Adding a library to the PHP Windows SDK

This document describes how to add or update a library in `winlibs` and
`winlib-builder`, and how to make it available to PHP's Windows builds. The
goal is a reproducible package whose source, dependencies, build options, and
validation are visible to everybody.

## Overview

Adding a library normally involves four separate pieces:

1. A source mirror under the `winlibs` GitHub organization.
2. A build workflow in `winlibs/winlib-builder`.
3. Publication in a PHP Windows SDK dependency series.
4. Detection and linkage in `php-src`, if PHP uses the library directly.

Do not combine these into an opaque prebuilt archive. A contributor should be
able to identify the exact upstream commit and reproduce the package from the
workflow.

## Naming conventions

Use the following names consistently:

- Source repository: `winlibs/<library>`.
- Upstream tag: preserve it unchanged when practical, for example `v1.4.0`.
- Winlibs package tag: `<library>-<version>`, for example
  `libultrahdr-1.4.0` or `libtiff-4.7.2rc2`.
- Workflow artifact: `<library>-<version>-<toolset>-<architecture>`, for
  example `libjxl-0.11.2-vs18-x64`.
- Static library built specifically for winlibs: use the `_a.lib` suffix, for
  example `jxl_a.lib`.
- Import library for a DLL: use the ordinary name, for example `jxl.lib` for
  `jxl.dll`.

Some established PHP dependencies use different upstream names. For example,
PHP's Brotli package contains static archives named `brotlicommon.lib`,
`brotlidec.lib`, and `brotlienc.lib`. Do not rename files owned by another
package merely to impose the `_a` convention. Detect and consume the package's
real names.

Never move a published tag. If packaging source must change after publication,
create a package-revision tag such as `<library>-<version>-1`. Workflow-only
changes do not require a new source tag.

## 1. Create the source mirror

Create an empty repository in the `winlibs` organization, then push the exact
upstream release commit. Do not import a generated source archive when the
project uses Git submodules or other Git metadata needed by its build.

Typical setup:

```bash
git clone https://example.org/upstream/library.git
cd library
git remote rename origin upstream
git remote add origin git@github.com:winlibs/library.git
git tag -a library-1.2.3 'v1.2.3^{}' -m 'library 1.2.3'
git push origin v1.2.3:refs/heads/main
git push origin refs/tags/v1.2.3
git push origin refs/tags/library-1.2.3
```

Verify both tags resolve to the intended commit:

```bash
git rev-parse 'v1.2.3^{}'
git rev-parse 'library-1.2.3^{}'
```

### Projects with submodules

Preserve the upstream Git tree and `.gitmodules`. Gitlink entries must retain
mode `160000`:

```bash
git ls-files -s third_party
git submodule status
```

Use recursive checkout in the workflow:

```yaml
- uses: actions/checkout@v5
  with:
    repository: winlibs/library
    ref: ${{ inputs.version }}
    path: library
    submodules: recursive
```

Do not mirror every third-party submodule into winlibs unless there is a
specific operational reason to do so.

## 2. Add the winlib-builder workflow

Create `.github/workflows/<library>.yml`. Prefer a manually dispatched workflow
while introducing a new package.

Recommended inputs:

```yaml
on:
  workflow_dispatch:
    inputs:
      version:
        description: library tag to build
        required: true
        default: library-1.2.3
      php:
        description: PHP version to build for
        required: true
        default: '8.6'
      stability:
        description: the series stability
        required: false
        default: staging
      workflow_run_ids:
        description: Comma-separated dependency workflow run IDs
        required: false
```

Build at least `x64` and `x86` unless upstream cannot support one safely. If an
architecture is deliberately omitted, document why in the workflow or pull
request.

Use `scripts/compute-virtuals.ps1` rather than hard-coding the Visual Studio
generator, toolset, SDK, or architecture:

```yaml
- name: Compute virtual inputs
  id: virtuals
  run: powershell winlib-builder/scripts/compute-virtuals -version ${{ inputs.php }} -arch ${{ matrix.arch }}

- name: Setup MSVC environment
  uses: ilammy/msvc-dev-cmd@v1
  with:
    arch: ${{ matrix.arch }}
    toolset: ${{ steps.virtuals.outputs.toolset }}
```

Initializing MSVC is required even if CMake can locate Visual Studio itself;
later smoke tests invoking `cl` also need the environment.

Use Ninja when it avoids generator compatibility problems. Otherwise pass the
values produced by `compute-virtuals.ps1` to CMake's Visual Studio generator.
Do not assume the runner's default CMake supports the newest Visual Studio
generator.

## 3. Reuse PHP dependencies

Do not build and redistribute private copies of dependencies already packaged
by PHP. Duplicate libraries are easily overwritten when dependency archives
are combined and can produce extremely difficult ABI and version bugs.

Add the dependency relationship to the `$deps` map in
`scripts/fetch-deps.ps1`:

```powershell
"library" = "brotli", "zlib";
```

Then fetch dependencies in the workflow:

```yaml
- name: Fetch dependencies
  run: powershell winlib-builder/scripts/fetch-deps -lib library -version ${{ inputs.php }} -vs ${{ steps.virtuals.outputs.vs }} -arch ${{ matrix.arch }} -stability ${{ inputs.stability }} -workflow_run_ids:'${{ inputs.workflow_run_ids }}'
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

The script first checks explicitly supplied workflow runs, then the selected
PHP SDK dependency series, then PECL dependencies. `workflow_run_ids` is useful
when one new package depends on another package that has not yet been published
to staging.

Force the upstream build to use these dependencies. For example, libjxl uses
`JPEGXL_FORCE_SYSTEM_BROTLI=ON` and explicit Brotli include/library paths. Also
verify that dependency-owned headers and libraries did not leak into the final
artifact.

Windows paths passed through generated CMake source or `try_compile()` should
use forward slashes. A raw path such as `D:\a\...` can be parsed as CMake escape
sequences.

## 4. Build shared and static variants

When upstream supports both, package:

- The DLL and its import library: `library.dll` and `library.lib`.
- A static archive: `library_a.lib`.
- Any separately required public companion archives.

Use separate build directories when `BUILD_SHARED_LIBS` controls the library
type. Do not overwrite one variant with the other during installation.

Static libraries are not always self-contained. Inspect the target's link
interface and package or reuse every required transitive archive. For example,
static libjxl also requires its CMS and Highway archives and the separately
packaged static Brotli libraries.

Prefer PHP's dynamic MSVC runtime (`/MD`) unless the package has an established
reason to use another runtime. A static library is still compatible with `/MD`;
“static library” describes the library linkage, not the C runtime choice.

For codec libraries, explicitly decide which backends are enabled and whether
they are compiled into the main library. libheif, for example, can build codec
plugins directly into the library by enabling a codec and setting its
`WITH_<CODEC>_PLUGIN` option to `OFF`.

## 5. Install a complete artifact

The uploaded directory should normally contain:

```text
bin/       DLLs and runtime files
include/   public headers
lib/       import and static libraries, CMake/pkg-config metadata
share/licenses/<library>/  upstream license and notice files
share/sbom/                generated CycloneDX, SPDX, and optional OpenVEX files
```

Include PDB files when the build produces them. Do not include tests, examples,
developer tools, or dependency-owned files unless they are intentional parts
of the PHP SDK package.

Add the library's canonical upstream identity and license expression under
`sbom/libraries/`, then run `scripts/generate-sbom.ps1` after staging licenses
and before uploading the artifact. See [Winlibs SBOM metadata](sbom.md).

Upload the installation directory, not the source or build tree:

```yaml
- uses: actions/upload-artifact@v4
  with:
    name: ${{ inputs.version }}-${{ steps.virtuals.outputs.vs }}-${{ matrix.arch }}
    path: install
```

## 6. Verify the package as a consumer

Do not treat a successful compilation as sufficient. Before uploading:

1. Assert that required headers, DLLs, import libraries, and static archives
   exist.
2. Compile a small C or C++ program against the installed headers and shared
   import library.
3. Run it with `install\bin` on `PATH`.
4. Compile and run it again against the static archive and its full dependency
   closure.
5. Exercise the features PHP requires, not merely a version function.

Place a reusable smoke-test source in `.github/ci/check-<library>.c` when the
test is more than a trivial one-liner. The libheif check, for example, verifies
that every required codec is actually available; the libjxl check creates both
decoder and encoder objects and accesses its CMS API.

Artifact assertions are important. They caught cases where upstream's default
target built WebP and demux but omitted `libwebpmux_a.lib`; explicitly building
the `all` target fixed the package.

## 7. Integrate with php-src

If PHP consumes the library directly, update the extension's `config.w32`:

1. Add or update its configure option.
2. Check every required library and public header.
3. Prefer the intended static library, then optionally support a DLL import
   library.
4. Add compile definitions required by static or shared headers.
5. Add transitive static dependencies to the link flags.
6. Define the extension feature macros only after all checks succeed.
7. Add new source files to `ADD_SOURCES` where necessary.

`CHECK_LIB()` accepts a semicolon-separated, ordered list of alternative file
names:

```js
CHECK_LIB("library_a.lib;library.lib", "extension", PHP_EXTENSION)
```

It returns the selected path, which can be used to choose static/shared compile
definitions. Explicit `CHECK_LIB(...) || CHECK_LIB(...)` calls are also valid
but produce separate checks.

Do not infer linkage type solely from a filename convention. PHP's Brotli
archives are static but currently use plain `.lib` names. Confirm how the
package was built and inspect its contents when uncertain.

Run the relevant extension tests for both architectures. Optional support must
also degrade cleanly when the dependency is absent.

## 8. Publish through staging

New packages should first be added to the appropriate PHP Windows SDK staging
series. Do not silently add them to a stable series solely because a future PHP
branch is under development.

After publication, verify the manifest and archive URL. Their general forms
are:

```text
https://downloads.php.net/~windows/php-sdk/deps/series/packages-<php>-<vs>-<arch>-staging.txt
https://downloads.php.net/~windows/php-sdk/deps/<vs>/<arch>/<artifact>.zip
```

Finally, run php-src Windows CI and inspect configure output. A green build does
not prove an optional feature was enabled: configure may have warned and built
without it. Confirm that every intended library and header was found, then run
the feature's tests.

## Release update checklist

For a later upstream release:

1. Review upstream build-system and dependency changes.
2. Mirror the exact release commit and preserve its upstream tag.
3. Create a new `<library>-<version>` winlibs tag.
4. Update the workflow's default tag.
5. Confirm dependency versions and filenames in the target PHP SDK series.
6. Build and verify every supported architecture and linkage variant.
7. Inspect the generated license directory and validate both SBOM formats.
8. Publish to staging and test php-src with the feature visibly enabled.
9. Never move the previous release tags or replace their source history.
