Set-StrictMode -Version Latest

function Copy-TreeContents {
    param (
        [Parameter(Mandatory)] [string] $Source,
        [Parameter(Mandatory)] [string] $Destination
    )

    if (-not (Test-Path $Source)) {
        return
    }

    New-Item -Path $Destination -ItemType Directory -Force | Out-Null
    Get-ChildItem -Path $Source -Force | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $Destination -Recurse -Force
    }
}
