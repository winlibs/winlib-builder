param (
    [Parameter(Mandatory)] [String] $lib,
    [Parameter(Mandatory)] [String] $version,
    [Parameter(Mandatory)] [String] $vs,
    [Parameter(Mandatory)] [String] $arch
)

$ErrorActionPreference = "Stop"

$deps = @{
    "curl" = "libssh2", "nghttp2", "openssl", "zlib";
    "libssh2" = "openssl", "zlib";
    "libxml2" = "libiconv"
}
$deps = $deps.$lib
if (-not $deps) {
    exit
}

$needs = @{}
$response = Invoke-WebRequest "https://windows.php.net/downloads/php-sdk/deps/series/packages-$version-$vs-$arch-staging.txt"
foreach ($line in $response.Content) {
    foreach ($dep in $deps) {
        if ($line -match "$dep-(.+)-$vs-$arch.zip") {
            $needs.$dep = $matches[1]
        }
    }
}

New-Item "deps" -ItemType "directory"

$baseurl = "https://windows.php.net/downloads/php-sdk/deps/$vs/$arch"
foreach ($dep in $needs.GetEnumerator()) {
    Write-Output "Fetching $($dep.Name)-$($dep.Value)"
    $temp = New-TemporaryFile | Rename-Item -NewName {$_.Name + ".zip"} -PassThru
    $url = "$baseurl/$($dep.Name)-$($dep.Value)-$vs-$arch.zip"
    Invoke-WebRequest $url -OutFile $temp
    Expand-Archive $temp -DestinationPath "deps"
}
