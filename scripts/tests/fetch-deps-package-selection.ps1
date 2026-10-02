$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Load only the resolver definition: running fetch-deps itself has download and
# extraction side effects unrelated to these deterministic index regressions.
$path = Join-Path $PSScriptRoot '../fetch-deps.ps1'
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path $path), [ref] $tokens, [ref] $errors
)
if ($errors.Count) { throw "PowerShell parse errors: $errors" }
$definition = $ast.Find({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Resolve-DownloadDependencies'
}, $true)
if ($null -eq $definition) { throw 'Resolver function is missing' }
Invoke-Expression $definition.Extent.Text

$vs = 'vs17'
$arch = 'x64'
$script:index = @'
cairo-1.18.4-vs17-x64.zip
cairo-1.18.6-vs17-x64.zip
cairo-1.99.0-vs18-x64.zip
cairo-1.99.0-vs17-x86.zip
pango-1.58.0-vs17-x64.zip
pango-1.58.2-vs17-x64.zip
librrd-1.11.0-vs17-x64.zip
librrd-1.8.0-vs17-x64.zip
librrd-1.11.0-2-vs17-x64.zip
librrd-1.11.0-10-vs17-x64.zip
librrd-1.12.0-rc1-vs17-x64.zip
'@
function Invoke-WebRequest { param($Uri, [switch]$UseBasicParsing) return @{Content=$script:index} }
$arguments = @{Dependencies=@('cairo','pango','librrd'); PackagesUrl='https://example.invalid/packages.txt'; BaseUrl='https://example.invalid/deps'}
$latest = Resolve-DownloadDependencies @arguments -Latest
foreach ($entry in @{cairo='1.18.6'; pango='1.58.2'; librrd='1.11.0-10'}.GetEnumerator()) {
    if ($latest[$entry.Key].Version -ne $entry.Value) { throw "Wrong latest selection for $($entry.Key)" }
}
$series = Resolve-DownloadDependencies @arguments
foreach ($entry in @{cairo='1.18.4'; pango='1.58.0'; librrd='1.11.0'}.GetEnumerator()) {
    if ($series[$entry.Key].Version -ne $entry.Value) { throw "Series selection changed for $($entry.Key)" }
}
$script:index = ($script:index -split '\r?\n' | Sort-Object -Descending) -join "`n"
$reversed = Resolve-DownloadDependencies @arguments -Latest
foreach ($name in $arguments.Dependencies) {
    if ($reversed[$name].Version -ne $latest[$name].Version) { throw "Selection depends on index order: $name" }
}
Write-Host 'PASS: PECL numeric versions, rebuild suffixes, architecture/toolset filtering, stable-only selection, order independence, and PHP series preservation'
