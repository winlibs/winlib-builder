param (
    [Parameter(Mandatory)] [String] $lib,
    [Parameter(Mandatory)] [String] $version,
    [Parameter(Mandatory)] [String] $vs,
    [Parameter(Mandatory)] [String] $arch,
    [Parameter(Mandatory)] [String] $stability
)

$ErrorActionPreference = "Stop"

$deps = @{
    "curl" = "libssh2", "nghttp2", "openssl", "zlib";
    "cyrus-sasl" = "liblmdb", "openssl", "sqlite3";
    "enchant" = "glib";
    "glib" = "libffi", "libintl", "zlib";
    "librdkafka" = "libzstd", "openssl", "zlib";
    "libssh2" = "openssl", "zlib";
    "libxml2" = "libiconv";
    "libxslt" = "libiconv", "libxml2";
    "libzip" = "libbzip2", "zlib";
    "net-snmp" = "openssl";
    "openldap" = "openssl", "libsasl"
}
if ($version -ge "8.0") {
    $deps."libzip" += "liblzma"
}
$deps = $deps.$lib
if (-not $deps) {
    exit
}

$needs = @{}
$response = Invoke-WebRequest "https://windows.php.net/downloads/php-sdk/deps/series/packages-$version-$vs-$arch-$stability.txt"
foreach ($line in $response.Content -split "`r`n") {
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

$deps = $deps | Where-Object {$needs.Keys -NotContains $_}
if ($deps.Count -gt 0) {
    $needs = @{}
    $response = Invoke-WebRequest "https://windows.php.net/downloads/pecl/deps/packages.txt"
    foreach ($line in $response.Content -split "`r`n") {
        foreach ($dep in $deps) {
            if ($line -match "$dep-(.+)-$vs-$arch.zip") {
                $needs.$dep = $matches[1]
            }
        }
    }

    $baseurl = "https://windows.php.net/downloads/pecl/deps"
    foreach ($dep in $needs.GetEnumerator()) {
        Write-Output "Fetching $($dep.Name)-$($dep.Value)"
        $temp = New-TemporaryFile | Rename-Item -NewName {$_.Name + ".zip"} -PassThru
        $url = "$baseurl/$($dep.Name)-$($dep.Value)-$vs-$arch.zip"
        Invoke-WebRequest $url -OutFile $temp
        Expand-Archive $temp -DestinationPath "deps"
    }
}

$deps = $deps | Where-Object {$needs.Keys -NotContains $_}
if ($deps.Count -gt 0) {
    throw "dependencies not found: $deps"
}
