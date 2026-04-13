param (
    [Parameter(Mandatory)] [String] $lib,
    [Parameter(Mandatory)] [String] $version,
    [Parameter(Mandatory)] [String] $vs,
    [Parameter(Mandatory)] [String] $arch,
    [Parameter(Mandatory)] [String] $stability,
    [String] $destination = "install"
)

$ErrorActionPreference = "Stop"

$deps = @{
    "curl" = "brotli", "libzstd"
}
$deps = $deps.$lib
if (-not $deps) {
    exit
}

function Resolve-Dependencies {
    param (
        [String[]] $Dependencies,
        [String] $PackagesUrl,
        [String] $BaseUrl
    )

    $resolved = @{}
    $response = Invoke-WebRequest -Uri $PackagesUrl -UseBasicParsing
    foreach ($line in $response.Content -split "\r?\n") {
        foreach ($dep in $Dependencies) {
            if ($resolved.ContainsKey($dep)) {
                continue
            }

            if ($line -match "^$dep-(.+)-$vs-$arch\.zip$") {
                $resolved[$dep] = @{
                    Version = $matches[1]
                    BaseUrl = $BaseUrl
                }
            }
        }
    }

    return $resolved
}

$resolved = Resolve-Dependencies `
    -Dependencies $deps `
    -PackagesUrl "https://downloads.php.net/~windows/php-sdk/deps/series/packages-$version-$vs-$arch-$stability.txt" `
    -BaseUrl "https://downloads.php.net/~windows/php-sdk/deps/$vs/$arch"

$missing = $deps | Where-Object { -not $resolved.ContainsKey($_) }
if ($missing.Count -gt 0) {
    $peclResolved = Resolve-Dependencies `
        -Dependencies $missing `
        -PackagesUrl "https://downloads.php.net/~windows/pecl/deps/packages.txt" `
        -BaseUrl "https://downloads.php.net/~windows/pecl/deps"

    foreach ($dep in $peclResolved.Keys) {
        $resolved[$dep] = $peclResolved[$dep]
    }
}

$missing = $deps | Where-Object { -not $resolved.ContainsKey($_) }
if ($missing.Count -gt 0) {
    throw "dependencies not found: $missing"
}

New-Item -Path $destination -ItemType Directory -Force | Out-Null

foreach ($dep in $deps) {
    $temp = New-TemporaryFile | Rename-Item -NewName { $_.Name + ".zip" } -PassThru
    $package = $resolved[$dep]
    $url = "$($package.BaseUrl)/$dep-$($package.Version)-$vs-$arch.zip"
    Write-Output "Fetching $url"
    Invoke-WebRequest -Uri $url -OutFile $temp
    Expand-Archive -Path $temp -DestinationPath $destination -Force
}
