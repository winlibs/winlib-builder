param (
    [Parameter(Mandatory)] [String] $lib,
    [Parameter(Mandatory)] [String] $version,
    [Parameter(Mandatory)] [String] $vs,
    [Parameter(Mandatory)] [String] $arch,
    [Parameter(Mandatory)] [String] $stability,
    [String] $workflow_run_ids = "",
    [String] $repository = ""
)

$ErrorActionPreference = "Stop"

$deps = @{
    "curl" = "brotli", "libssh2", "libzstd", "nghttp2", "openssl", "zlib";
    "cyrus-sasl" = "liblmdb", "openssl", "sqlite3";
    "enchant" = "glib";
    "glib" = "libffi", "libintl", "zlib";
    "libpng" = "zlib";
    "librdkafka" = "libzstd", "openssl", "zlib";
    "libssh2" = "openssl", "zlib";
    "libtiff" = "zlib", "libjpeg-turbo", "libwebp", "libzstd", "liblzma";
    "libxml2" = "libiconv";
    "libxslt" = "libiconv", "libxml2";
    "libzip" = "libbzip2", "zlib";
    "net-snmp" = "openssl";
    "openldap" = "openssl", "libsasl";
    "postgresql" = "openssl"
}
if ($version -ge "8.0") {
    $deps."libzip" += "liblzma"
}
$deps = $deps.$lib
if (-not $deps) {
    exit
}

function Get-GitHubApiHeaders {
    $headers = @{
        "Accept" = "application/vnd.github+json";
        "X-GitHub-Api-Version" = "2022-11-28";
        "User-Agent" = "winlib-builder"
    }

    if ($env:GITHUB_TOKEN) {
        $headers.Authorization = "Bearer $env:GITHUB_TOKEN"
    } else {
        Write-Warning "GITHUB_TOKEN is not set. GitHub API requests may fail or be rate-limited."
    }

    return $headers
}

function Resolve-GitHubArtifactDependencies {
    param (
        [String[]] $Dependencies,
        [String] $RunIds,
        [String] $Repository,
        [String] $Destination
    )

    $resolved = @{}
    $parsedRunIds = @(($RunIds -split "[,\s]+") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($parsedRunIds.Count -eq 0) {
        return $resolved
    }

    if ([string]::IsNullOrWhiteSpace($Repository)) {
        $Repository = $env:GITHUB_REPOSITORY
    }
    if ([string]::IsNullOrWhiteSpace($Repository)) {
        $Repository = "winlibs/winlib-builder"
    }

    $headers = Get-GitHubApiHeaders
    foreach ($runId in $parsedRunIds) {
        Write-Host "Fetching dependency artifacts from $Repository workflow run $runId"
        $artifactsUrl = "https://api.github.com/repos/$Repository/actions/runs/$runId/artifacts?per_page=100"
        $response = Invoke-RestMethod -Uri $artifactsUrl -Headers $headers -Method Get
        if ($response.total_count -eq 0) {
            Write-Warning "No artifacts found for workflow run $runId"
            continue
        }

        foreach ($dep in $Dependencies) {
            if ($resolved.ContainsKey($dep)) {
                continue
            }

            $artifactPattern = "^$([regex]::Escape($dep))-\d.*-$([regex]::Escape($vs))-$([regex]::Escape($arch))$"
            $matchingArtifacts = @($response.artifacts | Where-Object { $_.name -match $artifactPattern })
            $artifact = @($matchingArtifacts | Where-Object { -not $_.expired } | Select-Object -First 1)

            if ($artifact.Count -eq 0) {
                if ($matchingArtifacts.Count -gt 0) {
                    Write-Warning "Matching artifact for $dep in workflow run $runId is expired"
                }
                continue
            }

            Write-Host "Fetching $($artifact[0].name) from workflow run $runId"
            $temp = New-TemporaryFile | Rename-Item -NewName { $_.Name + ".zip" } -PassThru
            try {
                Invoke-WebRequest -Uri $artifact[0].archive_download_url -Headers $headers -OutFile $temp
                Expand-Archive -Path $temp -DestinationPath $Destination -Force
                $resolved[$dep] = $artifact[0].name
            } finally {
                Remove-Item -LiteralPath $temp.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    }

    return $resolved
}

function Resolve-DownloadDependencies {
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

            if ($line -match "^$([regex]::Escape($dep))-(.+)-$([regex]::Escape($vs))-$([regex]::Escape($arch))\.zip$") {
                $resolved[$dep] = @{
                    Version = $matches[1];
                    BaseUrl = $BaseUrl
                }
            }
        }
    }

    return $resolved
}

New-Item "deps" -ItemType "directory" -Force | Out-Null

$artifactDeps = Resolve-GitHubArtifactDependencies `
    -Dependencies $deps `
    -RunIds $workflow_run_ids `
    -Repository $repository `
    -Destination "deps"

$deps = $deps | Where-Object { -not $artifactDeps.ContainsKey($_) }
if ($deps.Count -eq 0) {
    exit
}

$needs = Resolve-DownloadDependencies `
    -Dependencies $deps `
    -PackagesUrl "https://downloads.php.net/~windows/php-sdk/deps/series/packages-$version-$vs-$arch-$stability.txt" `
    -BaseUrl "https://downloads.php.net/~windows/php-sdk/deps/$vs/$arch"

$deps = $deps | Where-Object {$needs.Keys -NotContains $_}
if ($deps.Count -gt 0) {
    $peclNeeds = Resolve-DownloadDependencies `
        -Dependencies $deps `
        -PackagesUrl "https://downloads.php.net/~windows/pecl/deps/packages.txt" `
        -BaseUrl "https://downloads.php.net/~windows/pecl/deps"

    foreach ($dep in $peclNeeds.Keys) {
        $needs[$dep] = $peclNeeds[$dep]
    }
}

$deps = $deps | Where-Object {$needs.Keys -NotContains $_}
if ($deps.Count -gt 0) {
    throw "dependencies not found: $deps"
}

foreach ($dep in $needs.Keys) {
    $package = $needs[$dep]
    $url = "$($package.BaseUrl)/$dep-$($package.Version)-$vs-$arch.zip"
    Write-Output "Fetching $url"
    $temp = New-TemporaryFile | Rename-Item -NewName {$_.Name + ".zip"} -PassThru
    try {
        Invoke-WebRequest -Uri $url -OutFile $temp
        Expand-Archive -Path $temp -DestinationPath "deps" -Force
    } finally {
        Remove-Item -LiteralPath $temp.FullName -Force -ErrorAction SilentlyContinue
    }
}
