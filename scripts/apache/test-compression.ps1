param([Parameter(Mandatory)] [string] $Arch)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$sharedRoot = "C:/vcpkg/installed/$Arch-windows"
$staticRoot = "C:/vcpkg/installed/$Arch-windows-static-md"
$source = Join-Path $PSScriptRoot 'compression-smoke.c'
$originalPath = $env:PATH
try {
    $env:PATH = "$sharedRoot/bin;$originalPath"
    foreach ($linkage in 'shared', 'static') {
        $zlibRoot = if ($linkage -eq 'static') { $staticRoot } else { $sharedRoot }
        $zlibLibrary = if ($linkage -eq 'static') { 'zs.lib' } else { 'z.lib' }
        $exe = Join-Path $env:RUNNER_TEMP "apache-compression-$linkage.exe"
        $object = Join-Path $env:RUNNER_TEMP "apache-compression-$linkage.obj"
        & cl.exe /nologo /W4 /MD "/I$zlibRoot/include" "/I$sharedRoot/include" $source "/Fo$object" "/Fe$exe" /link `
            "$zlibRoot/lib/$zlibLibrary" "$sharedRoot/lib/brotlidec.lib" "$sharedRoot/lib/brotlienc.lib" "$sharedRoot/lib/brotlicommon.lib"
        & $exe
    }
} finally {
    $env:PATH = $originalPath
}
