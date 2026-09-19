$ErrorActionPreference = 'Stop'

Invoke-WebRequest https://github.com/gcc-mirror/gcc/archive/refs/tags/releases/gcc-9.3.0.zip -OutFile gcc.zip
Invoke-WebRequest https://github.com/mingw-w64/mingw-w64/archive/refs/tags/v7.0.0.zip -OutFile mingw-w64.zip
7z x gcc.zip -olicense-sources/gcc -y '*/COPYING3' '*/COPYING.LIB' '*/COPYING.RUNTIME' '*/libbacktrace/backtrace.h' | Out-Null
if ($LASTEXITCODE) { throw 'GCC source extraction failed' }
7z x mingw-w64.zip -olicense-sources/mingw-w64 -y '*/COPYING.MinGW-w64-runtime/COPYING.MinGW-w64-runtime.txt' '*/mingw-w64-libraries/winpthreads/COPYING' | Out-Null
if ($LASTEXITCODE) { throw 'MinGW source extraction failed' }
New-Item -ItemType Directory -Force -Path install/share/licenses/OpenBLAS, install/share/licenses/gcc-libs, install/share/licenses/mingw-w64, install/share/licenses/winpthreads | Out-Null
Copy-Item openblas/LICENSE install/share/licenses/OpenBLAS/LICENSE.OpenBLAS
Copy-Item openblas/lapack-netlib/LICENSE install/share/licenses/OpenBLAS/LICENSE.OpenBLAS-LAPACK
foreach ($file in @('COPYING3', 'COPYING.LIB', 'COPYING.RUNTIME')) {
    Copy-Item "license-sources/gcc/*/$file" "install/share/licenses/gcc-libs/LICENSE.OpenBLAS-GCC-$file"
}
Copy-Item license-sources/gcc/*/libbacktrace/backtrace.h install/share/licenses/gcc-libs/LICENSE.OpenBLAS-libbacktrace
Copy-Item license-sources/mingw-w64/*/COPYING.MinGW-w64-runtime/COPYING.MinGW-w64-runtime.txt install/share/licenses/mingw-w64/LICENSE.OpenBLAS-MinGW-runtime
Copy-Item license-sources/mingw-w64/*/mingw-w64-libraries/winpthreads/COPYING install/share/licenses/winpthreads/LICENSE.OpenBLAS-winpthreads
