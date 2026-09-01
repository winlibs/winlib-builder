param (
    [Parameter(Mandatory)] [String] $SourceRoot,
    [Parameter(Mandatory)] [String] $DependencyRoot,
    [Parameter(Mandatory)] [String] $OutputDirectory
)

$ErrorActionPreference = 'Stop'

$sourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
$dependencyRoot = (Resolve-Path -LiteralPath $DependencyRoot).Path
New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
$outputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path

Copy-Item "$sourceRoot/config.h.win32" "$sourceRoot/config.h" -Force
Copy-Item "$sourceRoot/glib/glibconfig.h.win32" "$sourceRoot/glib/glibconfig.h" -Force

$sources = @(
    'gatomicarray.c'
    'gbinding.c'
    'gboxed.c'
    'gclosure.c'
    'genums.c'
    'gmarshal.c'
    'gobject.c'
    'gparam.c'
    'gparamspecs.c'
    'gsignal.c'
    'gsourceclosure.c'
    'gtype.c'
    'gtypemodule.c'
    'gtypeplugin.c'
    'gvalue.c'
    'gvaluearray.c'
    'gvaluetransform.c'
    'gvaluetypes.c'
)

$includeArguments = @(
    "/I$sourceRoot"
    "/I$sourceRoot/glib"
    "/I$sourceRoot/gobject"
    "/I$dependencyRoot/include"
    "/I$dependencyRoot/include/glib-2.0"
    "/I$dependencyRoot/lib/glib-2.0/include"
)

$objects = @()
foreach ($source in $sources) {
    $object = Join-Path $outputDirectory ($source -replace '\.c$', '.obj')
    $arguments = @(
        '/nologo'
        '/c'
        '/MD'
        '/O2'
        '/Zi'
        '/DGOBJECT_COMPILATION'
        '/DGOBJECT_STATIC_COMPILATION'
        '/DHAVE_CONFIG_H'
        "/Fd$outputDirectory/gobject.pdb"
        "/Fo$object"
    ) + $includeArguments + (Join-Path $sourceRoot "gobject/$source")
    & cl.exe $arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to compile $source"
    }
    $objects += $object
}

$library = Join-Path $outputDirectory 'gobject-2.0.lib'
& lib.exe /nologo "/out:$library" $objects
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to archive static GObject'
}
