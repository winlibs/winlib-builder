$ErrorActionPreference = 'Stop'

$path = Join-Path $PSScriptRoot '../../sbom/libraries/openblas.json'
$metadata = Get-Content $path -Raw | ConvertFrom-Json
$lapack = Get-Content openblas/lapack-netlib/CMakeLists.txt -Raw
$versions = @{
    lapack = (@('MAJOR', 'MINOR', 'PATCH') | ForEach-Object {
        [regex]::Match($lapack, "set\(LAPACK_$($_)_VERSION\s+(\d+)\)").Groups[1].Value
    }) -join '.'
    'gcc-runtime' = (Get-Content openblas/gcc-version.txt).Trim()
    'mingw-w64-runtime' = '7.0.0'
    winpthreads = '7.0.0'
}
foreach ($component in $metadata.components) { $component.version.value = $versions[$component.component] }
$metadata | ConvertTo-Json -Depth 20 | Set-Content $path
