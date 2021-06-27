param(
    [Parameter(Mandatory)] [String] $version
)

$ErrorActionPreference = "Stop"

$versions = @{
    "7.3" = "vc15"
    "7.4" = "vc15"
    "8.0" = "vs16"
    "8.1" = "vs16"
    "master" = "vs16"
}
$vs = $versions.$version
if (-not $vs) {
    throw "unsupported PHP version"
}

$toolsets = @{
    "vc14" = "14.0"
}
$dir = vswhere -latest -find "VC\Tools\MSVC"
foreach ($ts in (Get-ChildItem $dir)) {
    $tsv = "$ts".split(".")
    if ((14 -eq $tsv[0]) -and (9 -ge $tsv[1])) {
        $toolsets."vc14" = $ts
    } elseif ((14 -eq $tsv[0]) -and (19 -ge $tsv[1])) {
        $toolsets."vc15" = $ts
    } elseif (14 -eq $tsv[0]) {
        $toolsets."vs16" = $ts
    }
}
$toolset = $toolsets.$vs
if (-not $toolset) {
    throw "no suitable toolset available"
}

Write-Output "::set-output name=vs::$vs"
Write-Output "::set-output name=toolset:$toolset"
