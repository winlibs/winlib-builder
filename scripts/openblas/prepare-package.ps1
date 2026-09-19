param (
    [Parameter(Mandatory)] [ValidateSet('x64', 'x86')] [string] $Arch
)

$ErrorActionPreference = 'Stop'

$version = [regex]::Match((Get-Content openblas/Makefile.rule -Raw), '(?m)^VERSION\s*=\s*(\S+)').Groups[1].Value
"version=$version" >> $env:GITHUB_OUTPUT
lib.exe /nologo /machine:$Arch /def:install/lib/libopenblas.def /out:install/lib/libopenblas.lib
if ($LASTEXITCODE) { throw 'Import library generation failed' }
# Adapt only the installed header to MSVC's complex structs.
$header = 'install/include/lapack.h'
$types = "#ifdef _MSC_VER`n#include <complex.h>`n#define lapack_complex_float _Fcomplex`n#define lapack_complex_double _Dcomplex`n#endif"
(Get-Content $header -Raw).Replace('#include <stdlib.h>', "#include <stdlib.h>`n$types") | Set-Content $header
Remove-Item install/lib/cmake, install/lib/pkgconfig -Recurse
