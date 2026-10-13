param([Parameter(Mandatory)] [string] $Php)

$ErrorActionPreference = 'Stop'
$architectures = @('x64', 'x86', 'arm64')
if ($Php -notin '8.2', '8.3', '8.4', '8.5', '8.6', '8.7', 'master') {
    $architectures = @('x64', 'x86')
}
$vs18 = $Php -in '8.6', '8.7', 'master'
$matrix = @{
    include = @(
        foreach ($arch in $architectures) {
            $runner = if ($vs18) { 'windows-2025-vs2026' } else { 'windows-2022' }
            $sdk = if ($vs18) { '10.0.26100.0' }
                elseif ($Php -in '8.4', '8.5') { '10.0.22621.0' }
                elseif ($Php -in '7.3', '7.4') { '10.0.17763.0' }
                else { '10.0.19041.0' }
            $msvcArch = $arch
            $msvcSdk = ''
            if ($arch -eq 'arm64') {
                $runner = if ($vs18) { 'windows-11-vs2026-arm' } else { 'windows-11-arm' }
                $sdk = if ($vs18) { '10.0.26100.0' } else { '10.0.22621.0' }
                $msvcArch = if ($Php -in '8.2', '8.3') { 'amd64_arm64' } else { 'arm64' }
                $msvcSdk = $sdk
            }
            @{ arch = $arch; msvc_arch = $msvcArch; runner = $runner; sdk = $sdk; msvc_sdk = $msvcSdk }
        }
    )
}
$json = $matrix | ConvertTo-Json -Depth 3 -Compress
Write-Output $json
if ($env:GITHUB_OUTPUT) { "matrix=$json" | Add-Content $env:GITHUB_OUTPUT -Encoding utf8 }
