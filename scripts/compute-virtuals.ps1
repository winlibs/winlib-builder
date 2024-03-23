param(
    [Parameter(Mandatory)] [String] $version,
    [Parameter(Mandatory)] [String] $arch
)

$ErrorActionPreference = "Stop"

$versions = @{
    "7.3" = "vc15"
    "7.4" = "vc15"
    "8.0" = "vs16"
    "8.1" = "vs16"
    "8.2" = "vs16"
    "master" = "vs16"
}
$vs = $versions.$version
if (-not $vs) {
    throw "unsupported PHP version"
}
$vsnum = $vs.substring(2)

$years = @{
    "vc15" = "2017"
    "vs16" = "2019"
}
$vsyear = $years.$vs

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

$mstoolsets = @{
    "vc15" = "v141"
    "vs16" = "v142"
}
$msts = $mstoolsets.$vs
if (-not $msts) {
    throw "no suitable MS toolset available"
}

$winsdks = @{
    "vc15" = "10.0.17763.0"
    "vs16" = "10.0.18362.0"
}
$winsdk = $winsdks.$vs
if (-not $winsdk) {
    throw "no suitable Windows SDK available"
}

$msarchs = @{
    "x64" = "x64"
    "x86" = "Win32"
}
$msarch = $msarchs.$arch
if (-not $msarch) {
    throw "no suitable MS arch available"
}

& {
  Write-Output "vs=$vs"
  Write-Output "vsnum=$vsnum"
  Write-Output "vsyear=$vsyear"
  Write-Output "toolset=$toolset"
  Write-Output "msts=$msts"
  Write-Output "msarch=$msarch"
  Write-Output "winsdk=$winsdk"
} | Out-File -Append -FilePath $env:GITHUB_OUTPUT
