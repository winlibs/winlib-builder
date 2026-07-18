[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Library,

    [Parameter(Mandatory = $true)]
    [string]$Version,

    [Parameter(Mandatory = $true)]
    [string]$InstallRoot,

    [string]$Vs,

    [string]$Arch,

    [string]$PhpVersion,

    [string[]]$DependencyRoot = @(),

    [string]$MetadataPath = (Join-Path $PSScriptRoot '..\sbom')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function ConvertTo-Array {
    param([AllowNull()]$Value)

    if ($null -eq $Value) {
        return @()
    }

    if ($Value -is [System.Array]) {
        return @($Value)
    }

    return @($Value)
}

function Get-JsonProperty {
    param(
        [AllowNull()]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    if ($Object -is [System.Collections.IDictionary]) {
        return $Object[$Name]
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Get-UtcTimestamp {
    return (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}

function ConvertTo-Slug {
    param([Parameter(Mandatory = $true)][string]$Value)
    return ($Value -replace '[^A-Za-z0-9.-]', '-')
}

function Expand-Template {
    param(
        [AllowNull()][string]$Template,
        [hashtable]$Values
    )

    if ([string]::IsNullOrWhiteSpace($Template)) {
        return $null
    }

    $expanded = $Template
    foreach ($key in $Values.Keys) {
        $expanded = $expanded.Replace("{$key}", [string]$Values[$key])
    }

    return $expanded
}

function Get-TemplateValues {
    param(
        [string]$Component,
        [string]$LibraryName,
        [string]$PackageVersion,
        [string]$UpstreamVersion,
        [string]$InputTag,
        [string]$SourceTag
    )

    return @{
        component = $Component
        library = $LibraryName
        version = $UpstreamVersion
        versionDash = $UpstreamVersion -replace '[._]', '-'
        versionUnderscore = $UpstreamVersion -replace '[.-]', '_'
        packageVersion = $PackageVersion
        upstreamVersion = $UpstreamVersion
        tag = $InputTag
        sourceTag = $SourceTag
    }
}

function Normalize-Version {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputVersion,
        [AllowNull()]$VersionMetadata
    )

    $normalized = $InputVersion
    do {
        $changed = $false
        foreach ($prefix in ConvertTo-Array (Get-JsonProperty $VersionMetadata 'stripPrefixes')) {
            if ($normalized.StartsWith([string]$prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                $normalized = $normalized.Substring(([string]$prefix).Length)
                $changed = $true
                break
            }
        }
    } while ($changed)

    return $normalized
}

function Get-DefaultUpstreamVersion {
    param(
        [Parameter(Mandatory = $true)][string]$PackageVersion,
        [AllowNull()]$VersionMetadata
    )

    if ((Get-JsonProperty $VersionMetadata 'stripRebuildSuffix') -ne $false -and $PackageVersion -match '^(.+)-\d+$') {
        return $matches[1]
    }

    return $PackageVersion
}

function Get-BomRef {
    param(
        [string]$Component,
        [string]$PackageVersion
    )

    return "pkg:php-windows-deps/$Component@$PackageVersion"
}

function Get-GitInfo {
    param([string[]]$Candidates)

    foreach ($candidate in $Candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique) {
        $path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($candidate)
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            continue
        }

        $commit = & git -C $path rev-parse HEAD 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($commit)) {
            $global:LASTEXITCODE = 0
            continue
        }

        $remote = & git -C $path remote get-url origin 2>$null
        $tag = & git -C $path describe --tags --exact-match HEAD 2>$null
        if ($LASTEXITCODE -ne 0) {
            $tag = $null
            $global:LASTEXITCODE = 0
        }

        $repository = $null
        $url = [string]$remote
        if ($url -match '^(?:git@|https?://)github\.com[:/]([^/]+/[^/]+?)(?:\.git)?$') {
            $repository = $matches[1]
            $url = "https://github.com/$repository"
        } elseif ($url.EndsWith('.git', [System.StringComparison]::OrdinalIgnoreCase)) {
            $url = $url.Substring(0, $url.Length - 4)
        }

        return [pscustomobject]@{
            Path = $path
            Repository = $repository
            Url = $url
            Commit = ([string]$commit).Trim()
            Tag = if ($null -eq $tag) { $null } else { ([string]$tag).Trim() }
        }
    }

    return $null
}

function Get-LibraryMetadata {
    param(
        [Parameter(Mandatory = $true)]
        $Metadata,
        [Parameter(Mandatory = $true)]
        [string]$RequestedLibrary
    )

    foreach ($property in $Metadata.libraries.PSObject.Properties) {
        $entry = $property.Value
        $aliases = @($property.Name) + (ConvertTo-Array (Get-JsonProperty $entry 'aliases')) + (ConvertTo-Array (Get-JsonProperty $entry 'component'))
        foreach ($alias in $aliases) {
            if ([string]::Equals([string]$alias, $RequestedLibrary, [System.StringComparison]::OrdinalIgnoreCase)) {
                return [pscustomobject]@{
                    Key = $property.Name
                    Entry = $entry
                }
            }
        }
    }

    return $null
}

function Get-PatchedBuild {
    param(
        [AllowNull()]$Entry,
        [string]$InputTag,
        [string]$PackageVersion
    )

    $patchedBuilds = ConvertTo-Array (Get-JsonProperty $Entry 'patchedBuilds')
    foreach ($patchedBuild in $patchedBuilds) {
        $tags = ConvertTo-Array (Get-JsonProperty $patchedBuild 'tags')
        $tag = Get-JsonProperty $patchedBuild 'tag'
        if ($null -ne $tag) {
            $tags += $tag
        }

        foreach ($candidate in $tags) {
            if ([string]::Equals([string]$candidate, $InputTag, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $patchedBuild
            }
        }

        $patchedVersion = Get-JsonProperty $patchedBuild 'version'
        if ($null -ne $patchedVersion -and [string]::Equals([string]$patchedVersion, $PackageVersion, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $patchedBuild
        }
    }

    $versionMatch = $null
    $versionMetadata = Get-JsonProperty $Entry 'version'
    foreach ($patchedBuild in $patchedBuilds) {
        $tags = ConvertTo-Array (Get-JsonProperty $patchedBuild 'tags')
        $tag = Get-JsonProperty $patchedBuild 'tag'
        if ($null -ne $tag) {
            $tags += $tag
        }

        foreach ($candidate in $tags) {
            $candidateVersion = Normalize-Version -InputVersion ([string]$candidate) -VersionMetadata $versionMetadata
            if ([string]::Equals($candidateVersion, $PackageVersion, [System.StringComparison]::OrdinalIgnoreCase)) {
                if ($null -ne $versionMatch) {
                    throw "Multiple patched builds match package version '$PackageVersion'."
                }
                $versionMatch = $patchedBuild
                break
            }
        }
    }

    return $versionMatch
}

function Get-SpdxLicenseExpression {
    param(
        [AllowNull()]$License,
        [System.Collections.Generic.List[object]]$ExtractedLicenses,
        [string]$InstallRootPath
    )

    $expression = Get-JsonProperty $License 'expression'
    if ($null -ne $expression) {
        $result = [string]$expression
    } elseif ($null -ne ($id = Get-JsonProperty $License 'id')) {
        $result = [string]$id
    } elseif ($null -ne ($name = Get-JsonProperty $License 'name')) {
        $licenseRef = Get-JsonProperty $License 'licenseRef'
        if ($null -eq $licenseRef) {
            $licenseRef = 'LicenseRef-' + (ConvertTo-Slug $name)
        }
        $result = [string]$licenseRef
    } else {
        $result = 'NOASSERTION'
    }

    $customLicenses = [System.Collections.Generic.List[object]]::new()
    if ($result -like 'LicenseRef-*') {
        $customLicenses.Add($License) | Out-Null
    }
    foreach ($customLicense in ConvertTo-Array (Get-JsonProperty $License 'extractedLicenses')) {
        $customLicenses.Add($customLicense) | Out-Null
    }

    foreach ($customLicense in $customLicenses) {
        $licenseRef = [string](Get-JsonProperty $customLicense 'licenseRef')
        $name = [string](Get-JsonProperty $customLicense 'name')
        if ([string]::IsNullOrWhiteSpace($licenseRef)) {
            $licenseRef = 'LicenseRef-' + (ConvertTo-Slug $name)
        }
        $extractedText = Get-LicenseText -License $customLicense -InstallRootPath $InstallRootPath
        $existing = $ExtractedLicenses | Where-Object { $_.licenseId -eq $licenseRef } | Select-Object -First 1
        if ($null -eq $existing) {
            $ExtractedLicenses.Add([ordered]@{
                licenseId = $licenseRef
                extractedText = $extractedText
                name = $name
            }) | Out-Null
        } elseif ([string](Get-JsonProperty $existing 'extractedText') -ne [string]$extractedText) {
            throw "Conflicting extracted license text for '$licenseRef'."
        }
    }

    return $result
}

function New-CycloneDxLicenseChoice {
    param([AllowNull()]$License)

    $expression = Get-JsonProperty $License 'expression'
    if ($null -ne $expression) {
        return [ordered]@{ expression = [string]$expression }
    }

    $id = Get-JsonProperty $License 'id'
    if ($null -ne $id) {
        return [ordered]@{ license = [ordered]@{ id = [string]$id } }
    }

    $licenseRef = Get-JsonProperty $License 'licenseRef'
    if ($null -ne $licenseRef) {
        return [ordered]@{ expression = [string]$licenseRef }
    }

    $name = Get-JsonProperty $License 'name'
    if ($null -ne $name) {
        return [ordered]@{ license = [ordered]@{ name = [string]$name } }
    }

    return [ordered]@{ license = [ordered]@{ name = 'NOASSERTION' } }
}

function Get-LicenseText {
    param(
        [AllowNull()]$License,
        [string]$InstallRootPath
    )

    $parts = [System.Collections.Generic.List[string]]::new()
    $inlineText = Get-JsonProperty $License 'text'
    if (-not [string]::IsNullOrWhiteSpace([string]$inlineText)) {
        $parts.Add(([string]$inlineText).Trim()) | Out-Null
    }

    foreach ($relativePath in ConvertTo-Array (Get-JsonProperty $License 'textFiles')) {
        $path = Join-Path $InstallRootPath ([string]$relativePath)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Missing custom license text file '$path'."
        }
        $parts.Add((Get-Content -LiteralPath $path -Raw).Trim()) | Out-Null
    }

    if ($parts.Count -eq 0) {
        return $null
    }

    return [string]::Join("`n`n", $parts)
}

function New-ExternalReference {
    param(
        [string]$Category,
        [string]$Type,
        [string]$Locator
    )

    if ([string]::IsNullOrWhiteSpace($Locator)) {
        return $null
    }

    return [ordered]@{
        referenceCategory = $Category
        referenceType = $Type
        referenceLocator = $Locator
    }
}

function Get-SpdxOriginator {
    param(
        [AllowNull()][string]$Repository,
        [AllowNull()][string]$Url
    )

    if (-not [string]::IsNullOrWhiteSpace($Repository) -and $Repository.Contains('/')) {
        return 'Organization: ' + $Repository.Split('/')[0]
    }
    if (-not [string]::IsNullOrWhiteSpace($Url)) {
        try {
            $uri = [uri]($Url -replace '^git\+', '')
            if ($uri.Host -eq 'github.com' -and $uri.Segments.Count -gt 1) {
                return 'Organization: ' + $uri.Segments[1].Trim('/')
            }
            if ($uri.Host -match '(^|\.)apache\.org$') {
                return 'Organization: Apache Software Foundation'
            }
            if ($uri.Host -match '(^|\.)lua\.org$') {
                return 'Organization: Lua.org'
            }
            return 'Organization: ' + $uri.Host
        } catch {
        }
    }
    return 'NOASSERTION'
}

function Complete-VcpkgSpdxPackages {
    param(
        $Sbom,
        [string]$BinarySupplier,
        [AllowNull()]$Overrides
    )

    $packages = @(ConvertTo-Array (Get-JsonProperty $Sbom 'packages'))
    $portPackage = $packages | Where-Object {
        (Get-JsonProperty $_ 'comment') -eq 'This is the port (recipe) consumed by vcpkg.' -or
        (Get-JsonProperty $_ 'SPDXID') -eq 'SPDXRef-port'
    } | Select-Object -First 1
    if ($null -eq $portPackage) {
        return $Sbom
    }

    $portVersion = ([string](Get-JsonProperty $portPackage 'versionInfo')) -replace '#\d+$', ''
    $portLicense = [string](Get-JsonProperty $portPackage 'licenseConcluded')

    foreach ($package in $packages) {
        $name = [string](Get-JsonProperty $package 'name')
        $override = Get-JsonProperty $Overrides $name
        $comment = [string](Get-JsonProperty $package 'comment')

        $purpose = [string](Get-JsonProperty $package 'primaryPackagePurpose')
        if ([string]::IsNullOrWhiteSpace($purpose)) {
            $purpose = if ($comment -eq 'This is a binary package built by vcpkg.' -or $name -match ':[^:]+$') { 'LIBRARY' } else { 'SOURCE' }
            $package | Add-Member -NotePropertyName primaryPackagePurpose -NotePropertyValue $purpose -Force
        }

        if ($package -eq $portPackage) {
            $externalRefs = @(ConvertTo-Array (Get-JsonProperty $package 'externalRefs'))
            if (-not ($externalRefs | Where-Object { (Get-JsonProperty $_ 'referenceType') -eq 'purl' })) {
                $externalRefs += New-ExternalReference `
                    -Category 'PACKAGE-MANAGER' `
                    -Type 'purl' `
                    -Locator "pkg:github/microsoft/vcpkg#ports/$(ConvertTo-Slug $name)"
                $package | Add-Member -NotePropertyName externalRefs -NotePropertyValue $externalRefs -Force
            }
        }

        $version = [string](Get-JsonProperty $package 'versionInfo')
        if ([string]::IsNullOrWhiteSpace($version)) {
            $downloadLocation = [string](Get-JsonProperty $package 'downloadLocation')
            if ($downloadLocation -match '@([^@]+)$' -and $matches[1] -notmatch '\$\{') {
                $version = $matches[1] -replace '^refs/tags/', ''
                if ($version -notmatch '^[0-9a-f]{40}$') {
                    $version = $version -replace '^v(?=\d)', '' -replace '^(?:openssl|pcre2)-(?=\d)', ''
                }
            } else {
                $version = $portVersion
            }
            $overrideVersion = Get-JsonProperty $override 'versionInfo'
            if ($null -ne $overrideVersion) {
                $version = [string]$overrideVersion
            }
            $package | Add-Member -NotePropertyName versionInfo -NotePropertyValue $version -Force
        }

        $supplier = [string](Get-JsonProperty $package 'supplier')
        if ([string]::IsNullOrWhiteSpace($supplier) -or $supplier -eq 'NOASSERTION') {
            $overrideSupplier = Get-JsonProperty $override 'supplier'
            if ($null -ne $overrideSupplier) {
                $supplier = [string]$overrideSupplier
            } elseif ($package -eq $portPackage) {
                $supplier = 'Organization: Microsoft'
            } elseif ($comment -eq 'This is a binary package built by vcpkg.' -or $name -match ':[^:]+$') {
                $supplier = "Organization: $BinarySupplier"
            } else {
                $supplier = Get-SpdxOriginator -Url ([string](Get-JsonProperty $package 'downloadLocation'))
                if ($supplier -eq 'NOASSERTION') {
                    $supplier = 'Organization: Microsoft'
                }
            }
            $package | Add-Member -NotePropertyName supplier -NotePropertyValue $supplier -Force
        }

        $license = [string](Get-JsonProperty $package 'licenseConcluded')
        if ([string]::IsNullOrWhiteSpace($license) -or $license -eq 'NOASSERTION') {
            $overrideLicense = Get-JsonProperty $override 'licenseConcluded'
            $license = if ($null -eq $overrideLicense) { $portLicense } else { [string]$overrideLicense }
            $package | Add-Member -NotePropertyName licenseConcluded -NotePropertyValue $license -Force
        }

        $packageCopyright = [string](Get-JsonProperty $package 'copyrightText')
        if ([string]::IsNullOrWhiteSpace($packageCopyright) -or $packageCopyright -eq 'NOASSERTION') {
            $package | Add-Member -NotePropertyName copyrightText -NotePropertyValue 'See accompanying license and notice files.' -Force
        }
    }

    return $Sbom
}

function Add-OptionalProperty {
    param(
        [System.Collections.Generic.List[object]]$Properties,
        [string]$Name,
        [AllowNull()][string]$Value
    )

    if (-not [string]::IsNullOrWhiteSpace($Value)) {
        $Properties.Add([ordered]@{ name = $Name; value = $Value }) | Out-Null
    }
}

function Add-Dependency {
    param(
        [hashtable]$Map,
        [string]$Ref,
        [AllowNull()]$DependsOn
    )

    if ([string]::IsNullOrWhiteSpace($Ref)) {
        return
    }
    if (-not $Map.ContainsKey($Ref)) {
        $Map[$Ref] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    }
    foreach ($dependency in ConvertTo-Array $DependsOn) {
        if (-not [string]::IsNullOrWhiteSpace([string]$dependency)) {
            $Map[$Ref].Add([string]$dependency) | Out-Null
        }
    }
}

function ConvertTo-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        $Object,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $json = $Object | ConvertTo-Json -Depth 100
    Set-Content -Path $Path -Value $json -Encoding utf8
}

function Read-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowNull()][string]$SchemaPath
    )

    $json = Get-Content -LiteralPath $Path -Raw
    if (-not [string]::IsNullOrWhiteSpace($SchemaPath) -and -not ($json | Test-Json -SchemaFile $SchemaPath)) {
        throw "SBOM metadata '$Path' does not match '$SchemaPath'."
    }

    return $json | ConvertFrom-Json -Depth 100
}

function Get-SbomMetadata {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$RequestedLibrary
    )

    $resolvedPath = (Resolve-Path -Path $Path).ProviderPath
    $item = Get-Item -Path $resolvedPath

    if (-not $item.PSIsContainer) {
        $metadata = Read-JsonFile -Path $resolvedPath
        $libraryMetadata = Get-LibraryMetadata -Metadata $metadata -RequestedLibrary $RequestedLibrary
        if ($null -eq $libraryMetadata) {
            return $null
        }

        return [pscustomobject]@{
            Document = $metadata.document
            Library = $libraryMetadata
            Source = $resolvedPath
        }
    }

    $documentPath = Join-Path $resolvedPath 'document.json'
    $librariesRoot = Join-Path $resolvedPath 'libraries'
    $schemaPath = Join-Path $resolvedPath 'schema.json'
    if (-not (Test-Path -Path $documentPath -PathType Leaf)) {
        throw "Missing SBOM document metadata file '$documentPath'."
    }
    if (-not (Test-Path -Path $librariesRoot -PathType Container)) {
        throw "Missing SBOM library metadata directory '$librariesRoot'."
    }
    if (-not (Test-Path -Path $schemaPath -PathType Leaf)) {
        throw "Missing SBOM metadata schema '$schemaPath'."
    }

    $document = Read-JsonFile -Path $documentPath -SchemaPath $schemaPath
    foreach ($metadataFile in Get-ChildItem -Path $librariesRoot -Filter '*.json' | Sort-Object -Property Name) {
        $entry = Read-JsonFile -Path $metadataFile.FullName -SchemaPath $schemaPath
        $key = [System.IO.Path]::GetFileNameWithoutExtension($metadataFile.Name)
        $aliases = @($key) + (ConvertTo-Array (Get-JsonProperty $entry 'aliases')) + (ConvertTo-Array (Get-JsonProperty $entry 'component'))
        foreach ($alias in $aliases) {
            if ([string]::Equals([string]$alias, $RequestedLibrary, [System.StringComparison]::OrdinalIgnoreCase)) {
                return [pscustomobject]@{
                    Document = $document
                    Library = [pscustomobject]@{
                        Key = $key
                        Entry = $entry
                    }
                    Source = $metadataFile.FullName
                }
            }
        }
    }

    return $null
}

$metadata = Get-SbomMetadata -Path $MetadataPath -RequestedLibrary $Library

if ($null -eq $metadata) {
    throw "No SBOM metadata found for library '$Library' in $MetadataPath."
}

$documentMetadata = $metadata.Document
$libraryMetadata = $metadata.Library
$entry = $libraryMetadata.Entry
$componentName = [string](Get-JsonProperty $entry 'component')
if ([string]::IsNullOrWhiteSpace($componentName)) {
    $componentName = $libraryMetadata.Key
}

$packageVersion = Normalize-Version -InputVersion $Version -VersionMetadata (Get-JsonProperty $entry 'version')
$patchedBuild = Get-PatchedBuild -Entry $entry -InputTag $Version -PackageVersion $packageVersion

$upstream = Get-JsonProperty $entry 'upstream'
$sourceRepository = [string](Get-JsonProperty $upstream 'repository')
$sourceBaseUrl = [string](Get-JsonProperty $upstream 'url')
if ([string]::IsNullOrWhiteSpace($sourceBaseUrl) -and -not [string]::IsNullOrWhiteSpace($sourceRepository)) {
    $sourceBaseUrl = "https://github.com/$sourceRepository"
}
$upstreamVersion = Get-DefaultUpstreamVersion -PackageVersion $packageVersion -VersionMetadata (Get-JsonProperty $entry 'version')
$sourceTag = [string](Get-JsonProperty $upstream 'tag')
if ([string]::IsNullOrWhiteSpace($sourceTag)) {
    $sourceTag = Expand-Template -Template (Get-JsonProperty $upstream 'tagTemplate') -Values (Get-TemplateValues -Component $componentName -LibraryName $Library -PackageVersion $packageVersion -UpstreamVersion $upstreamVersion -InputTag $Version)
}
$forkRepository = $null
$forkTag = $null
$fixedCves = @()
$notAffectedCves = @(ConvertTo-Array (Get-JsonProperty $entry 'notAffectedCves'))

if ($null -ne $patchedBuild) {
    $patchUpstream = Get-JsonProperty $patchedBuild 'upstream'
    $patchFork = Get-JsonProperty $patchedBuild 'fork'
    $patchUpstreamVersion = Get-JsonProperty $patchUpstream 'version'
    $patchUpstreamRepository = Get-JsonProperty $patchUpstream 'repository'
    $patchUpstreamTag = Get-JsonProperty $patchUpstream 'tag'

    if ($null -ne $patchUpstreamVersion) {
        $upstreamVersion = [string]$patchUpstreamVersion
    }
    if ($null -ne $patchUpstreamRepository) {
        $sourceRepository = [string]$patchUpstreamRepository
    }
    if ($null -ne $patchUpstreamTag) {
        $sourceTag = [string]$patchUpstreamTag
    }

    $forkRepository = [string](Get-JsonProperty $patchFork 'repository')
    $forkTag = [string](Get-JsonProperty $patchFork 'tag')
    if ([string]::IsNullOrWhiteSpace($forkTag)) {
        $forkTag = $Version
    }

    $fixedCves = @(ConvertTo-Array (Get-JsonProperty $patchedBuild 'fixedCves'))
    $notAffectedCves += @(ConvertTo-Array (Get-JsonProperty $patchedBuild 'notAffectedCves'))
}

$values = Get-TemplateValues -Component $componentName -LibraryName $Library -PackageVersion $packageVersion -UpstreamVersion $upstreamVersion -InputTag $Version -SourceTag $sourceTag

$purl = Expand-Template -Template (Get-JsonProperty $entry 'purl') -Values $values
if ([string]::IsNullOrWhiteSpace($purl)) {
    $purl = "pkg:generic/$componentName@$upstreamVersion"
}

$cpe = Expand-Template -Template (Get-JsonProperty $entry 'cpe') -Values $values
$homepage = Expand-Template -Template (Get-JsonProperty $entry 'homepage') -Values $values
if ([string]::IsNullOrWhiteSpace($homepage) -and -not [string]::IsNullOrWhiteSpace($sourceBaseUrl)) {
    $homepage = $sourceBaseUrl
}

$sourceCandidates = @(
    (Get-JsonProperty $entry 'sourcePath'),
    $Library,
    $componentName,
    $libraryMetadata.Key,
    ($sourceRepository -replace '^.*/', '')
) + (ConvertTo-Array (Get-JsonProperty $entry 'aliases'))
$gitInfo = Get-GitInfo -Candidates $sourceCandidates
$checkoutRepository = if ($null -ne $patchedBuild) { $forkRepository } else { $sourceRepository }
$checkoutRef = if ($null -ne $patchedBuild) { $forkTag } else { $sourceTag }
$checkoutCommit = $null
$checkoutUrl = if ([string]::IsNullOrWhiteSpace($checkoutRepository)) { $sourceBaseUrl } else { "https://github.com/$checkoutRepository" }
$declaredSourceUrl = Expand-Template -Template (Get-JsonProperty $entry 'sourceUrl') -Values $values
if (-not [string]::IsNullOrWhiteSpace($declaredSourceUrl)) {
    $checkoutRepository = $null
    $checkoutRef = $Version
    $checkoutUrl = $declaredSourceUrl
}
if ($null -ne $gitInfo) {
    if (-not [string]::IsNullOrWhiteSpace($gitInfo.Repository)) {
        $checkoutRepository = $gitInfo.Repository
    }
    if (-not [string]::IsNullOrWhiteSpace($gitInfo.Url)) {
        $checkoutUrl = $gitInfo.Url
    }
    if (-not [string]::IsNullOrWhiteSpace($gitInfo.Tag)) {
        $checkoutRef = $gitInfo.Tag
    }
    $checkoutCommit = $gitInfo.Commit
}

$sourceOrigin = if ([string]::Equals($checkoutRepository, $sourceRepository, [System.StringComparison]::OrdinalIgnoreCase)) {
    'upstream'
} elseif ($checkoutRepository -like 'winlibs/*') {
    'winlibs-fork'
} else {
    'alternate-source'
}

$sourceTagUrl = $null
$sourceTagUrlTemplate = Get-JsonProperty $upstream 'tagUrlTemplate'
if (-not [string]::IsNullOrWhiteSpace([string]$sourceTagUrlTemplate)) {
    $sourceTagUrl = Expand-Template -Template $sourceTagUrlTemplate -Values $values
} elseif (-not [string]::IsNullOrWhiteSpace($sourceRepository) -and -not [string]::IsNullOrWhiteSpace($sourceTag)) {
    $sourceTagUrl = "https://github.com/$sourceRepository/tree/$([uri]::EscapeDataString($sourceTag))"
} elseif (-not [string]::IsNullOrWhiteSpace($sourceBaseUrl)) {
    $sourceTagUrl = $sourceBaseUrl
}

$checkoutVcsUrl = $null
if (-not [string]::IsNullOrWhiteSpace($checkoutUrl) -and -not [string]::IsNullOrWhiteSpace($checkoutCommit)) {
    $checkoutVcsUrl = "git+$checkoutUrl.git@$checkoutCommit"
} elseif (-not [string]::IsNullOrWhiteSpace($declaredSourceUrl)) {
    $checkoutVcsUrl = $declaredSourceUrl
} elseif ($sourceOrigin -ne 'upstream' -and -not [string]::IsNullOrWhiteSpace($checkoutUrl) -and -not [string]::IsNullOrWhiteSpace($checkoutRef)) {
    $checkoutVcsUrl = "$checkoutUrl/tree/$([uri]::EscapeDataString($checkoutRef))"
}

$installRootPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InstallRoot)
New-Item -Path $installRootPath -ItemType Directory -Force | Out-Null
$sbomRoot = Join-Path $installRootPath 'share\sbom'
New-Item -Path $sbomRoot -ItemType Directory -Force | Out-Null
$licenseMetadata = Get-JsonProperty $entry 'license'
$inlineLicenseText = Get-JsonProperty $licenseMetadata 'text'
if (-not [string]::IsNullOrWhiteSpace([string]$inlineLicenseText)) {
    $licenseRoot = Join-Path $installRootPath "share\licenses\$componentName"
    New-Item -Path $licenseRoot -ItemType Directory -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $licenseRoot 'LICENSE') -Value ([string]$inlineLicenseText).Trim() -Encoding utf8
}

$componentCopyright = [string](Get-JsonProperty $entry 'copyrightText')
if ([string]::IsNullOrWhiteSpace($componentCopyright)) {
    $componentCopyright = 'See accompanying license and notice files.'
}

$created = Get-UtcTimestamp
$documentNamespaceBase = [string]$documentMetadata.namespace
$toolName = [string]$documentMetadata.tool
$author = [string]$documentMetadata.author
$downloadBaseUrl = [string](Get-JsonProperty $documentMetadata 'downloadBaseUrl')
$licenseListVersion = [string](Invoke-RestMethod -Uri ([string](Get-JsonProperty $documentMetadata 'licenseListUrl')) -TimeoutSec 30).licenseListVersion
$licenseListVersion = [string]::Join('.', @($licenseListVersion.Split('.')[0..1]))
$bomRef = Get-BomRef -Component $componentName -PackageVersion $packageVersion
$artifactNameParts = @($componentName, $packageVersion) + @($Vs, $Arch | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$artifactFileName = [string]::Join('-', $artifactNameParts) + '.zip'
$artifactPathParts = @($Vs, $Arch | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) + @($artifactFileName)
$artifactDownloadLocation = $downloadBaseUrl.TrimEnd('/') + '/' + [string]::Join('/', $artifactPathParts)
$originator = Get-SpdxOriginator -Repository $sourceRepository -Url $sourceBaseUrl
$baseName = $componentName -replace '[^A-Za-z0-9_.-]', '-'
$properties = [System.Collections.Generic.List[object]]::new()
Add-OptionalProperty -Properties $properties -Name 'php:library' -Value $Library
Add-OptionalProperty -Properties $properties -Name 'php:component' -Value $componentName
Add-OptionalProperty -Properties $properties -Name 'php:version' -Value $packageVersion
Add-OptionalProperty -Properties $properties -Name 'php:upstream-version' -Value $upstreamVersion
Add-OptionalProperty -Properties $properties -Name 'php:source-origin' -Value $sourceOrigin
Add-OptionalProperty -Properties $properties -Name 'php:upstream-repository' -Value $sourceRepository
Add-OptionalProperty -Properties $properties -Name 'php:upstream-url' -Value $sourceBaseUrl
Add-OptionalProperty -Properties $properties -Name 'php:upstream-tag' -Value $sourceTag
Add-OptionalProperty -Properties $properties -Name 'php:source-repository' -Value $checkoutRepository
Add-OptionalProperty -Properties $properties -Name 'php:source-url' -Value $checkoutUrl
Add-OptionalProperty -Properties $properties -Name 'php:source-ref' -Value $checkoutRef
Add-OptionalProperty -Properties $properties -Name 'php:source-commit' -Value $checkoutCommit
Add-OptionalProperty -Properties $properties -Name 'php:input-version' -Value $Version
Add-OptionalProperty -Properties $properties -Name 'php:vs' -Value $Vs
Add-OptionalProperty -Properties $properties -Name 'php:arch' -Value $Arch
Add-OptionalProperty -Properties $properties -Name 'php:php-version' -Value $PhpVersion
Add-OptionalProperty -Properties $properties -Name 'php:package-file-name' -Value $artifactFileName
Add-OptionalProperty -Properties $properties -Name 'php:download-location' -Value $artifactDownloadLocation

$externalReferences = [System.Collections.Generic.List[object]]::new()
$externalReferences.Add([ordered]@{ type = 'distribution'; url = $artifactDownloadLocation }) | Out-Null
$checkoutReferenceType = if ([string]::IsNullOrWhiteSpace($declaredSourceUrl)) { 'vcs' } else { 'distribution' }
foreach ($reference in @(
        @{ Type = 'website'; Url = $homepage },
        @{ Type = 'vcs'; Url = $sourceTagUrl },
        @{ Type = $checkoutReferenceType; Url = $checkoutVcsUrl }
    )) {
    if (-not [string]::IsNullOrWhiteSpace($reference.Url)) {
        $externalReferences.Add([ordered]@{ type = $reference.Type; url = $reference.Url }) | Out-Null
    }
}

$component = [ordered]@{
    type = 'library'
    'bom-ref' = $bomRef
    name = $componentName
    version = $packageVersion
    purl = $purl
    licenses = @(New-CycloneDxLicenseChoice -License $licenseMetadata)
    copyright = $componentCopyright
    supplier = [ordered]@{ name = $author }
    externalReferences = @($externalReferences)
    properties = @($properties)
}

if (-not [string]::IsNullOrWhiteSpace($cpe)) {
    $component.cpe = $cpe
}

if ($sourceOrigin -ne 'upstream') {
    $patchIssues = [System.Collections.Generic.List[object]]::new()
    foreach ($cve in $fixedCves) {
        $issue = [ordered]@{
            type = 'security'
            id = [string](Get-JsonProperty $cve 'id')
            source = [ordered]@{
                name = [string](Get-JsonProperty $cve 'source')
                url = [string](Get-JsonProperty $cve 'url')
            }
        }
        $description = Get-JsonProperty $cve 'detail'
        if ($null -ne $description) {
            $issue.description = [string]$description
        }
        $references = @(ConvertTo-Array (Get-JsonProperty $cve 'references'))
        if ($references.Count -gt 0) {
            $issue.references = @($references)
        }
        $patchIssues.Add($issue) | Out-Null
    }

    $pedigreePatches = [System.Collections.Generic.List[object]]::new()
    if ($patchIssues.Count -gt 0) {
        $pedigreePatches.Add([ordered]@{
            type = 'backport'
            resolves = @($patchIssues)
        }) | Out-Null
    }
    $patchDetails = [System.Collections.Generic.List[string]]::new()
    foreach ($patchMetadata in ConvertTo-Array (Get-JsonProperty $patchedBuild 'patches')) {
        $patch = [ordered]@{
            type = 'backport'
            diff = [ordered]@{ url = [string](Get-JsonProperty $patchMetadata 'url') }
        }
        $detail = Get-JsonProperty $patchMetadata 'detail'
        if (-not [string]::IsNullOrWhiteSpace([string]$detail)) {
            $patchDetails.Add([string]$detail) | Out-Null
        }
        $pedigreePatches.Add($patch) | Out-Null
    }

    $upstreamIdentity = if ([string]::IsNullOrWhiteSpace($sourceRepository)) { $sourceBaseUrl } else { $sourceRepository }
    $pedigreeNotes = "Built from $checkoutRepository ref $checkoutRef$([string]::IsNullOrWhiteSpace($checkoutCommit) ? '' : " at commit $checkoutCommit") with upstream identity $upstreamIdentity tag $sourceTag."
    if ($patchDetails.Count -gt 0) {
        $pedigreeNotes += ' ' + [string]::Join(' ', $patchDetails)
    }
    $component.pedigree = [ordered]@{
        ancestors = @(
            [ordered]@{
                type = 'library'
                'bom-ref' = "urn:php:upstream:$(ConvertTo-Slug $componentName):$(ConvertTo-Slug $upstreamVersion)"
                name = $componentName
                version = $upstreamVersion
                purl = $purl
            }
        )
        notes = $pedigreeNotes
    }
    if ($pedigreePatches.Count -gt 0) {
        $component.pedigree.patches = @($pedigreePatches)
    }
}

$vulnerabilities = [System.Collections.Generic.List[object]]::new()
$cycloneDxJustifications = @{
    component_not_present = 'code_not_present'
    vulnerable_code_not_present = 'code_not_present'
    vulnerable_code_not_in_execute_path = 'code_not_reachable'
    vulnerable_code_cannot_be_controlled_by_adversary = 'protected_by_mitigating_control'
    inline_mitigations_already_exist = 'protected_by_mitigating_control'
}
foreach ($cve in $fixedCves) {
    $cveId = [string](Get-JsonProperty $cve 'id')
    $detail = [string](Get-JsonProperty $cve 'detail')
    if ([string]::IsNullOrWhiteSpace($detail)) {
        $detail = "Fixed by patched winlibs build $forkRepository tag $forkTag."
    }

    $vulnerabilities.Add([ordered]@{
        id = $cveId
        source = [ordered]@{
            name = [string](Get-JsonProperty $cve 'source')
            url = [string](Get-JsonProperty $cve 'url')
        }
        affects = @(
            [ordered]@{ ref = $bomRef }
        )
        analysis = [ordered]@{
            state = 'resolved_with_pedigree'
            response = @('update')
            detail = $detail
        }
    }) | Out-Null
}
foreach ($cve in $notAffectedCves) {
    $vulnerabilities.Add([ordered]@{
        id = [string](Get-JsonProperty $cve 'id')
        source = [ordered]@{
            name = [string](Get-JsonProperty $cve 'source')
            url = [string](Get-JsonProperty $cve 'url')
        }
        affects = @(
            [ordered]@{ ref = $bomRef }
        )
        analysis = [ordered]@{
            state = 'not_affected'
            justification = $cycloneDxJustifications[[string](Get-JsonProperty $cve 'justification')]
            detail = [string](Get-JsonProperty $cve 'detail')
        }
    }) | Out-Null
}

$embeddedRecords = [System.Collections.Generic.List[object]]::new()
$componentMap = @{}
$dependencyMap = @{}
$rootDependencyRefs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($embeddedEntry in ConvertTo-Array (Get-JsonProperty $entry 'components')) {
    $embeddedName = [string](Get-JsonProperty $embeddedEntry 'component')
    $embeddedPath = [string](Get-JsonProperty $embeddedEntry 'sourcePath')
    $embeddedGit = Get-GitInfo -Candidates @($embeddedPath)
    $embeddedVersionMetadata = Get-JsonProperty $embeddedEntry 'version'
    $embeddedInputVersion = Expand-Template -Template (Get-JsonProperty $embeddedVersionMetadata 'value') -Values $values
    if ([string]::IsNullOrWhiteSpace($embeddedInputVersion) -and $null -ne $embeddedGit) {
        $embeddedInputVersion = if ([string]::IsNullOrWhiteSpace($embeddedGit.Tag)) { $embeddedGit.Commit } else { $embeddedGit.Tag }
    }
    if ([string]::IsNullOrWhiteSpace($embeddedInputVersion)) {
        throw "Unable to determine the version of embedded component '$embeddedName' from '$embeddedPath'."
    }

    $embeddedPackageVersion = Normalize-Version -InputVersion $embeddedInputVersion -VersionMetadata $embeddedVersionMetadata
    $embeddedUpstreamVersion = Get-DefaultUpstreamVersion -PackageVersion $embeddedPackageVersion -VersionMetadata $embeddedVersionMetadata
    $embeddedUpstream = Get-JsonProperty $embeddedEntry 'upstream'
    $embeddedRepository = [string](Get-JsonProperty $embeddedUpstream 'repository')
    $embeddedBaseUrl = [string](Get-JsonProperty $embeddedUpstream 'url')
    if ([string]::IsNullOrWhiteSpace($embeddedBaseUrl) -and -not [string]::IsNullOrWhiteSpace($embeddedRepository)) {
        $embeddedBaseUrl = "https://github.com/$embeddedRepository"
    }
    $embeddedTag = [string](Get-JsonProperty $embeddedUpstream 'tag')
    $embeddedValues = Get-TemplateValues -Component $embeddedName -LibraryName $Library -PackageVersion $embeddedPackageVersion -UpstreamVersion $embeddedUpstreamVersion -InputTag $embeddedInputVersion
    if ([string]::IsNullOrWhiteSpace($embeddedTag)) {
        $embeddedTag = Expand-Template -Template (Get-JsonProperty $embeddedUpstream 'tagTemplate') -Values $embeddedValues
    }
    $embeddedValues.sourceTag = $embeddedTag
    $embeddedPurl = Expand-Template -Template (Get-JsonProperty $embeddedEntry 'purl') -Values $embeddedValues
    $embeddedRef = Get-BomRef -Component $embeddedName -PackageVersion $embeddedPackageVersion
    $embeddedProperties = [System.Collections.Generic.List[object]]::new()
    Add-OptionalProperty -Properties $embeddedProperties -Name 'php:component-origin' -Value 'embedded'
    Add-OptionalProperty -Properties $embeddedProperties -Name 'php:source-path' -Value $embeddedPath
    Add-OptionalProperty -Properties $embeddedProperties -Name 'php:upstream-repository' -Value $embeddedRepository
    Add-OptionalProperty -Properties $embeddedProperties -Name 'php:upstream-url' -Value $embeddedBaseUrl
    Add-OptionalProperty -Properties $embeddedProperties -Name 'php:upstream-tag' -Value $embeddedTag
    if ($null -ne $embeddedGit) {
        Add-OptionalProperty -Properties $embeddedProperties -Name 'php:source-repository' -Value $embeddedGit.Repository
        Add-OptionalProperty -Properties $embeddedProperties -Name 'php:source-url' -Value $embeddedGit.Url
        Add-OptionalProperty -Properties $embeddedProperties -Name 'php:source-ref' -Value $embeddedGit.Tag
        Add-OptionalProperty -Properties $embeddedProperties -Name 'php:source-commit' -Value $embeddedGit.Commit
    }

    $embeddedReferences = [System.Collections.Generic.List[object]]::new()
    $embeddedHomepage = [string](Get-JsonProperty $embeddedEntry 'homepage')
    if ([string]::IsNullOrWhiteSpace($embeddedHomepage)) {
        $embeddedHomepage = $embeddedBaseUrl
    }
    $embeddedReferences.Add([ordered]@{ type = 'website'; url = $embeddedHomepage }) | Out-Null
    $embeddedTagUrl = Expand-Template -Template (Get-JsonProperty $embeddedUpstream 'tagUrlTemplate') -Values $embeddedValues
    if ([string]::IsNullOrWhiteSpace($embeddedTagUrl) -and -not [string]::IsNullOrWhiteSpace($embeddedRepository)) {
        $embeddedTagUrl = "https://github.com/$embeddedRepository/tree/$([uri]::EscapeDataString($embeddedTag))"
    } elseif ([string]::IsNullOrWhiteSpace($embeddedTagUrl)) {
        $embeddedTagUrl = $embeddedBaseUrl
    }
    $embeddedReferences.Add([ordered]@{ type = 'vcs'; url = $embeddedTagUrl }) | Out-Null
    if ($null -ne $embeddedGit -and -not [string]::IsNullOrWhiteSpace($embeddedGit.Url)) {
        $embeddedReferences.Add([ordered]@{ type = 'vcs'; url = "git+$($embeddedGit.Url).git@$($embeddedGit.Commit)" }) | Out-Null
    }

    $embeddedCopyright = 'See accompanying license and notice files.'

    $embeddedComponent = [ordered]@{
        type = 'library'
        'bom-ref' = $embeddedRef
        name = $embeddedName
        version = $embeddedPackageVersion
        purl = $embeddedPurl
        licenses = @(New-CycloneDxLicenseChoice -License (Get-JsonProperty $embeddedEntry 'license'))
        copyright = $embeddedCopyright
        supplier = [ordered]@{ name = $author }
        externalReferences = @($embeddedReferences)
        properties = @($embeddedProperties)
    }
    $embeddedCpe = Expand-Template -Template (Get-JsonProperty $embeddedEntry 'cpe') -Values $embeddedValues
    if (-not [string]::IsNullOrWhiteSpace($embeddedCpe)) {
        $embeddedComponent.cpe = $embeddedCpe
    }

    $componentMap[$embeddedRef] = $embeddedComponent
    $rootDependencyRefs.Add($embeddedRef) | Out-Null
    Add-Dependency -Map $dependencyMap -Ref $embeddedRef -DependsOn @()
    $embeddedRecords.Add([pscustomobject]@{
        Entry = $embeddedEntry
        Name = $embeddedName
        Version = $embeddedPackageVersion
        Purl = $embeddedPurl
        Ref = $embeddedRef
        SourcePath = $embeddedPath
        DownloadLocation = $embeddedTagUrl
        Originator = Get-SpdxOriginator -Repository $embeddedRepository -Url $embeddedBaseUrl
        Copyright = $embeddedCopyright
    }) | Out-Null
}

$dependencySbomFiles = [System.Collections.Generic.List[string]]::new()
$vcpkgBuildHelperPattern = '^vcpkg-cmake(?:-config|-get-vars)?(?::|$)'
$dependencyRoots = @($DependencyRoot) + @('deps', 'deps-install')
foreach ($root in $dependencyRoots | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique) {
    $resolvedRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($root)
    if (-not (Test-Path -LiteralPath $resolvedRoot -PathType Container)) {
        continue
    }
    Get-ChildItem -LiteralPath $resolvedRoot -Recurse -File | Where-Object {
        $_.Name -match '\.(cdx|spdx)\.json$' -and -not $_.FullName.StartsWith($installRootPath, [System.StringComparison]::OrdinalIgnoreCase)
    } | ForEach-Object {
        if (-not $dependencySbomFiles.Contains($_.FullName)) {
            $dependencySbomFiles.Add($_.FullName) | Out-Null
        }
    }
}

foreach ($file in $dependencySbomFiles | Where-Object { $_ -match '\.cdx\.json$' } | Sort-Object) {
    $dependencySbom = Read-JsonFile -Path $file
    $dependencyRootComponent = Get-JsonProperty (Get-JsonProperty $dependencySbom 'metadata') 'component'
    $dependencyRootRef = [string](Get-JsonProperty $dependencyRootComponent 'bom-ref')
    $dependencyComponents = @($dependencyRootComponent) + (ConvertTo-Array (Get-JsonProperty $dependencySbom 'components'))
    $excludedDependencyRefs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($dependencyComponent in $dependencyComponents) {
        $ref = [string](Get-JsonProperty $dependencyComponent 'bom-ref')
        if ((Get-JsonProperty $dependencyComponent 'name') -match $vcpkgBuildHelperPattern -and
            -not [string]::IsNullOrWhiteSpace($ref)) {
            $excludedDependencyRefs.Add($ref) | Out-Null
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($dependencyRootRef) -and -not $excludedDependencyRefs.Contains($dependencyRootRef)) {
        $rootDependencyRefs.Add($dependencyRootRef) | Out-Null
    }
    foreach ($dependencyComponent in $dependencyComponents) {
        $ref = [string](Get-JsonProperty $dependencyComponent 'bom-ref')
        if (-not [string]::IsNullOrWhiteSpace($ref) -and -not $excludedDependencyRefs.Contains($ref) -and -not $componentMap.ContainsKey($ref)) {
            $componentCopy = $dependencyComponent | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
            $nestedComponents = @(ConvertTo-Array (Get-JsonProperty $componentCopy 'components') |
                Where-Object { (Get-JsonProperty $_ 'type') -ne 'file' -and (Get-JsonProperty $_ 'name') -notmatch $vcpkgBuildHelperPattern })
            if ($nestedComponents.Count -eq 0) {
                $componentCopy.PSObject.Properties.Remove('components')
            } else {
                $componentCopy.components = $nestedComponents
            }
            $componentMap[$ref] = $componentCopy
        }
    }
    foreach ($dependency in ConvertTo-Array (Get-JsonProperty $dependencySbom 'dependencies')) {
        $ref = [string](Get-JsonProperty $dependency 'ref')
        if (-not $excludedDependencyRefs.Contains($ref)) {
            $dependsOn = @(ConvertTo-Array (Get-JsonProperty $dependency 'dependsOn') |
                Where-Object { -not $excludedDependencyRefs.Contains([string]$_) })
            Add-Dependency -Map $dependencyMap -Ref $ref -DependsOn $dependsOn
        }
    }
    foreach ($vulnerability in ConvertTo-Array (Get-JsonProperty $dependencySbom 'vulnerabilities')) {
        $vulnerabilities.Add($vulnerability) | Out-Null
    }
}

foreach ($file in $dependencySbomFiles | Where-Object { $_ -match '\.spdx\.json$' } | Sort-Object) {
    if (Test-Path -LiteralPath ($file -replace '\.spdx\.json$', '.cdx.json')) {
        continue
    }
    $dependencySbom = Complete-VcpkgSpdxPackages `
        -Sbom (Read-JsonFile -Path $file) `
        -BinarySupplier $author `
        -Overrides (Get-JsonProperty $entry 'spdxPackageOverrides')
    $spdxRefs = @{}
    foreach ($package in ConvertTo-Array (Get-JsonProperty $dependencySbom 'packages')) {
        $packagePurl = $null
        foreach ($externalRef in ConvertTo-Array (Get-JsonProperty $package 'externalRefs')) {
            if ((Get-JsonProperty $externalRef 'referenceType') -eq 'purl') {
                $packagePurl = [string](Get-JsonProperty $externalRef 'referenceLocator')
                break
            }
        }
        $packageName = [string](Get-JsonProperty $package 'name')
        if ($packageName -match $vcpkgBuildHelperPattern) {
            continue
        }
        $dependencyPackageVersion = [string](Get-JsonProperty $package 'versionInfo')
        $ref = if ([string]::IsNullOrWhiteSpace($packagePurl)) { "pkg:generic/$(ConvertTo-Slug $packageName)@$dependencyPackageVersion" } else { $packagePurl }
        $spdxRefs[[string](Get-JsonProperty $package 'SPDXID')] = $ref
        if (-not $componentMap.ContainsKey($ref)) {
            $converted = [ordered]@{ type = 'library'; 'bom-ref' = $ref; name = $packageName; version = $dependencyPackageVersion }
            if (-not [string]::IsNullOrWhiteSpace($packagePurl)) { $converted.purl = $packagePurl }
            $packageLicense = [string](Get-JsonProperty $package 'licenseDeclared')
            if ([string]::IsNullOrWhiteSpace($packageLicense) -or $packageLicense -eq 'NOASSERTION') {
                $packageLicense = [string](Get-JsonProperty $package 'licenseConcluded')
            }
            if (-not [string]::IsNullOrWhiteSpace($packageLicense) -and $packageLicense -ne 'NOASSERTION') {
                $converted.licenses = @([ordered]@{ expression = $packageLicense })
            }
            $packageCopyright = [string](Get-JsonProperty $package 'copyrightText')
            if (-not [string]::IsNullOrWhiteSpace($packageCopyright) -and $packageCopyright -ne 'NOASSERTION') {
                $converted.copyright = $packageCopyright
            }
            $packageSupplier = [string](Get-JsonProperty $package 'supplier')
            if (-not [string]::IsNullOrWhiteSpace($packageSupplier) -and $packageSupplier -ne 'NOASSERTION') {
                $converted.supplier = [ordered]@{ name = ($packageSupplier -replace '^(?:Organization|Person):\s*', '') }
            }
            $componentMap[$ref] = $converted
        }
    }
    foreach ($described in ConvertTo-Array (Get-JsonProperty $dependencySbom 'documentDescribes')) {
        if ($spdxRefs.ContainsKey([string]$described)) {
            $rootDependencyRefs.Add($spdxRefs[[string]$described]) | Out-Null
        }
    }
    foreach ($relationship in ConvertTo-Array (Get-JsonProperty $dependencySbom 'relationships')) {
        $from = $spdxRefs[[string](Get-JsonProperty $relationship 'spdxElementId')]
        $to = $spdxRefs[[string](Get-JsonProperty $relationship 'relatedSpdxElement')]
        if ($null -ne $from -and $null -ne $to -and (Get-JsonProperty $relationship 'relationshipType') -in @('DEPENDS_ON', 'CONTAINS')) {
            Add-Dependency -Map $dependencyMap -Ref $from -DependsOn @($to)
        }
    }
}

Add-Dependency -Map $dependencyMap -Ref $bomRef -DependsOn @($rootDependencyRefs)
$cycloneDependencies = foreach ($ref in $dependencyMap.Keys | Sort-Object) {
    [ordered]@{ ref = $ref; dependsOn = @($dependencyMap[$ref] | Sort-Object) }
}

$cycloneDx = [ordered]@{
    bomFormat = 'CycloneDX'
    specVersion = '1.6'
    serialNumber = "urn:uuid:$([guid]::NewGuid().ToString())"
    version = 1
    metadata = [ordered]@{
        timestamp = $created
        tools = [ordered]@{
            components = @(
                [ordered]@{
                    type = 'application'
                    name = $toolName
                    version = '1.0.0'
                }
            )
        }
        component = $component
    }
    components = @($componentMap.Values | Sort-Object -Property name, version)
    dependencies = @($cycloneDependencies)
}

if ($vulnerabilities.Count -gt 0) {
    $vulnerabilityMap = @{}
    foreach ($vulnerability in $vulnerabilities) {
        $affectedRefs = @(ConvertTo-Array (Get-JsonProperty $vulnerability 'affects') | ForEach-Object {
            [string](Get-JsonProperty $_ 'ref')
        } | Sort-Object -Unique)
        $key = "$(Get-JsonProperty $vulnerability 'id')|$([string]::Join(',', $affectedRefs))"
        if (-not $vulnerabilityMap.ContainsKey($key)) {
            $vulnerabilityMap[$key] = $vulnerability
        }
    }
    $cycloneDx.vulnerabilities = @($vulnerabilityMap.Keys | Sort-Object | ForEach-Object { $vulnerabilityMap[$_] })
}

$extractedLicenses = [System.Collections.Generic.List[object]]::new()
$spdxLicense = Get-SpdxLicenseExpression -License $licenseMetadata -ExtractedLicenses $extractedLicenses -InstallRootPath $installRootPath
$spdxId = 'SPDXRef-' + (ConvertTo-Slug "$componentName-$packageVersion")
$externalRefs = [System.Collections.Generic.List[object]]::new()
$externalRefs.Add((New-ExternalReference -Category 'PACKAGE-MANAGER' -Type 'purl' -Locator $purl)) | Out-Null
if (-not [string]::IsNullOrWhiteSpace($cpe)) {
    $externalRefs.Add((New-ExternalReference -Category 'SECURITY' -Type 'cpe23Type' -Locator $cpe)) | Out-Null
}
foreach ($locator in @($homepage, $sourceTagUrl, $checkoutVcsUrl)) {
    $externalRef = New-ExternalReference -Category 'OTHER' -Type 'website' -Locator $locator
    if ($null -ne $externalRef) {
        $externalRefs.Add($externalRef) | Out-Null
    }
}

$annotationParts = [System.Collections.Generic.List[string]]::new()
$annotationParts.Add("source-origin=$sourceOrigin") | Out-Null
if (-not [string]::IsNullOrWhiteSpace($sourceRepository)) { $annotationParts.Add("upstream=$sourceRepository@$sourceTag") | Out-Null }
if ([string]::IsNullOrWhiteSpace($sourceRepository) -and -not [string]::IsNullOrWhiteSpace($sourceBaseUrl)) { $annotationParts.Add("upstream=$sourceBaseUrl@$sourceTag") | Out-Null }
if (-not [string]::IsNullOrWhiteSpace($checkoutRepository)) { $annotationParts.Add("source=$checkoutRepository@$checkoutRef") | Out-Null }
if ([string]::IsNullOrWhiteSpace($checkoutRepository) -and -not [string]::IsNullOrWhiteSpace($checkoutUrl)) { $annotationParts.Add("source=$checkoutUrl") | Out-Null }
if (-not [string]::IsNullOrWhiteSpace($checkoutCommit)) { $annotationParts.Add("source-commit=$checkoutCommit") | Out-Null }
if ($fixedCves.Count -gt 0) {
    $annotationParts.Add("fixed-cves=$([string]::Join(',', @($fixedCves | ForEach-Object { Get-JsonProperty $_ 'id' })))") | Out-Null
}
if ($notAffectedCves.Count -gt 0) {
    $annotationParts.Add("not-affected-cves=$([string]::Join(',', @($notAffectedCves | ForEach-Object { Get-JsonProperty $_ 'id' })))") | Out-Null
}

$spdx = [ordered]@{
    spdxVersion = 'SPDX-2.3'
    dataLicense = 'CC0-1.0'
    SPDXID = 'SPDXRef-DOCUMENT'
    name = "$componentName-$packageVersion"
    documentNamespace = "$documentNamespaceBase/$componentName/$packageVersion/$([guid]::NewGuid().ToString())"
    creationInfo = [ordered]@{
        created = $created
        creators = @("Tool: $toolName-1.0.0", "Organization: $author")
        licenseListVersion = $licenseListVersion
    }
    documentDescribes = @($spdxId)
    packages = @(
        [ordered]@{
            name = $componentName
            SPDXID = $spdxId
            versionInfo = $packageVersion
            packageFileName = $artifactFileName
            downloadLocation = $artifactDownloadLocation
            filesAnalyzed = $false
            licenseConcluded = $spdxLicense
            licenseDeclared = $spdxLicense
            copyrightText = $componentCopyright
            supplier = "Organization: $author"
            originator = $originator
            primaryPackagePurpose = 'LIBRARY'
            externalRefs = @($externalRefs | Where-Object { $null -ne $_ })
            annotations = @(
                [ordered]@{
                    annotationType = 'OTHER'
                    annotator = "Tool: $toolName-1.0.0"
                    annotationDate = $created
                    comment = [string]::Join('; ', $annotationParts)
                }
            )
        }
    )
    relationships = @(
        [ordered]@{
            spdxElementId = 'SPDXRef-DOCUMENT'
            relationshipType = 'DESCRIBES'
            relatedSpdxElement = $spdxId
        }
    )
}

$spdxPackageIdsByKey = @{}
$spdxPackageIdsByKey["$componentName|$packageVersion|$purl|$spdxLicense"] = $spdxId
$spdxRelationshipKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$spdxRelationshipKeys.Add("SPDXRef-DOCUMENT|DESCRIBES|$spdxId") | Out-Null
$spdxPackageCount = 0
foreach ($record in $embeddedRecords) {
    $spdxPackageCount++
    $embeddedLicenseMetadata = Get-JsonProperty $record.Entry 'license'
    $embeddedLicense = Get-SpdxLicenseExpression -License $embeddedLicenseMetadata -ExtractedLicenses $extractedLicenses -InstallRootPath $installRootPath
    $embeddedSpdxId = 'SPDXRef-Embedded-' + (ConvertTo-Slug "$($record.Name)-$($record.Version)-$spdxPackageCount")
    $spdx.packages += [ordered]@{
        name = $record.Name
        SPDXID = $embeddedSpdxId
        versionInfo = $record.Version
        downloadLocation = $record.DownloadLocation
        filesAnalyzed = $false
        licenseConcluded = $embeddedLicense
        licenseDeclared = $embeddedLicense
        copyrightText = $record.Copyright
        supplier = "Organization: $author"
        originator = $record.Originator
        primaryPackagePurpose = 'LIBRARY'
        sourceInfo = "Embedded from $($record.SourcePath)."
        externalRefs = @((New-ExternalReference -Category 'PACKAGE-MANAGER' -Type 'purl' -Locator $record.Purl))
    }
    $spdxPackageIdsByKey["$($record.Name)|$($record.Version)|$($record.Purl)|$embeddedLicense"] = $embeddedSpdxId
    $spdx.relationships += [ordered]@{
        spdxElementId = $spdxId
        relationshipType = 'DEPENDS_ON'
        relatedSpdxElement = $embeddedSpdxId
    }
    $spdxRelationshipKeys.Add("$spdxId|DEPENDS_ON|$embeddedSpdxId") | Out-Null
}

foreach ($file in $dependencySbomFiles | Where-Object { $_ -match '\.spdx\.json$' } | Sort-Object) {
    $dependencySbom = Complete-VcpkgSpdxPackages `
        -Sbom (Read-JsonFile -Path $file) `
        -BinarySupplier $author `
        -Overrides (Get-JsonProperty $entry 'spdxPackageOverrides')
    $spdxIdMap = @{}
    foreach ($package in ConvertTo-Array (Get-JsonProperty $dependencySbom 'packages')) {
        $packageName = [string](Get-JsonProperty $package 'name')
        if ($packageName -match $vcpkgBuildHelperPattern) {
            continue
        }
        $packagePurl = $null
        foreach ($externalRef in ConvertTo-Array (Get-JsonProperty $package 'externalRefs')) {
            if ((Get-JsonProperty $externalRef 'referenceType') -eq 'purl') {
                $packagePurl = [string](Get-JsonProperty $externalRef 'referenceLocator')
                break
            }
        }
        $packageKey = "$packageName|$(Get-JsonProperty $package 'versionInfo')|$packagePurl|$(Get-JsonProperty $package 'licenseDeclared')"
        if ($spdxPackageIdsByKey.ContainsKey($packageKey)) {
            $newSpdxId = $spdxPackageIdsByKey[$packageKey]
        } else {
            $spdxPackageCount++
            $newSpdxId = 'SPDXRef-Dependency-' + (ConvertTo-Slug "$(Get-JsonProperty $package 'name')-$(Get-JsonProperty $package 'versionInfo')-$spdxPackageCount")
            $packageCopy = $package | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
            $packageCopy.SPDXID = $newSpdxId
            $packageCopy | Add-Member -NotePropertyName filesAnalyzed -NotePropertyValue $false -Force
            $packageCopy.PSObject.Properties.Remove('packageVerificationCode')
            $packageCopy.PSObject.Properties.Remove('licenseInfoFromFiles')
            $spdx.packages += $packageCopy
            $spdxPackageIdsByKey[$packageKey] = $newSpdxId
        }
        $spdxIdMap[[string](Get-JsonProperty $package 'SPDXID')] = $newSpdxId
    }
    foreach ($license in ConvertTo-Array (Get-JsonProperty $dependencySbom 'hasExtractedLicensingInfos')) {
        $licenseId = [string](Get-JsonProperty $license 'licenseId')
        $existingLicense = $extractedLicenses | Where-Object { $_.licenseId -eq $licenseId } | Select-Object -First 1
        if ($null -eq $existingLicense) {
            $extractedLicenses.Add($license) | Out-Null
        } elseif ([string](Get-JsonProperty $existingLicense 'extractedText') -ne [string](Get-JsonProperty $license 'extractedText')) {
            throw "Conflicting extracted license text for '$licenseId' in '$file'."
        }
    }
    foreach ($described in ConvertTo-Array (Get-JsonProperty $dependencySbom 'documentDescribes')) {
        $related = $spdxIdMap[[string]$described]
        $key = "$spdxId|DEPENDS_ON|$related"
        if (-not [string]::IsNullOrWhiteSpace($related) -and $spdxRelationshipKeys.Add($key)) {
            $spdx.relationships += [ordered]@{ spdxElementId = $spdxId; relationshipType = 'DEPENDS_ON'; relatedSpdxElement = $related }
        }
    }
    foreach ($relationship in ConvertTo-Array (Get-JsonProperty $dependencySbom 'relationships')) {
        $from = $spdxIdMap[[string](Get-JsonProperty $relationship 'spdxElementId')]
        $to = $spdxIdMap[[string](Get-JsonProperty $relationship 'relatedSpdxElement')]
        $type = [string](Get-JsonProperty $relationship 'relationshipType')
        $key = "$from|$type|$to"
        if ($null -ne $from -and $null -ne $to -and $spdxRelationshipKeys.Add($key)) {
            $spdx.relationships += [ordered]@{ spdxElementId = $from; relationshipType = $type; relatedSpdxElement = $to }
        }
    }
}

if ($extractedLicenses.Count -gt 0) {
    $spdx.hasExtractedLicensingInfos = @($extractedLicenses)
}

if ($fixedCves.Count -gt 0 -or $notAffectedCves.Count -gt 0) {
    $openVexStatements = [System.Collections.Generic.List[object]]::new()
    foreach ($cve in $fixedCves) {
        $cveId = [string](Get-JsonProperty $cve 'id')
        $detail = [string](Get-JsonProperty $cve 'detail')
        if ([string]::IsNullOrWhiteSpace($detail)) {
            $detail = "Fixed by patched winlibs build $forkRepository tag $forkTag."
        }

        $openVexStatements.Add([ordered]@{
            vulnerability = [ordered]@{ name = $cveId }
            timestamp = $created
            products = @(
                [ordered]@{
                    '@id' = $bomRef
                    identifiers = [ordered]@{ purl = $purl }
                }
            )
            status = 'fixed'
            action_statement = $detail
        }) | Out-Null
    }
    foreach ($cve in $notAffectedCves) {
        $openVexStatements.Add([ordered]@{
            vulnerability = [ordered]@{ name = [string](Get-JsonProperty $cve 'id') }
            timestamp = $created
            products = @(
                [ordered]@{
                    '@id' = $bomRef
                    identifiers = [ordered]@{ purl = $purl }
                }
            )
            status = 'not_affected'
            justification = [string](Get-JsonProperty $cve 'justification')
            impact_statement = [string](Get-JsonProperty $cve 'detail')
        }) | Out-Null
    }

    $openVex = [ordered]@{
        '@context' = 'https://openvex.dev/ns/v0.2.0'
        '@id' = "$documentNamespaceBase/$componentName/$packageVersion/vex/$([guid]::NewGuid().ToString())"
        author = $author
        timestamp = $created
        version = 1
        statements = @($openVexStatements)
    }
}

$cycloneDxPath = Join-Path $sbomRoot "$baseName.cdx.json"
$spdxPath = Join-Path $sbomRoot "$baseName.spdx.json"
$openVexPath = Join-Path $sbomRoot "$baseName.openvex.json"
ConvertTo-JsonFile -Object $cycloneDx -Path $cycloneDxPath
ConvertTo-JsonFile -Object $spdx -Path $spdxPath

if ($fixedCves.Count -gt 0 -or $notAffectedCves.Count -gt 0) {
    ConvertTo-JsonFile -Object $openVex -Path $openVexPath
} elseif (Test-Path -LiteralPath $openVexPath -PathType Leaf) {
    Remove-Item -LiteralPath $openVexPath -Force
}

Write-Host "Generated SBOMs for $componentName $packageVersion"
Write-Host "CycloneDX: $cycloneDxPath"
Write-Host "SPDX: $spdxPath"
if ($fixedCves.Count -gt 0 -or $notAffectedCves.Count -gt 0) {
    Write-Host "OpenVEX: $openVexPath"
}
