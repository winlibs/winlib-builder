param (
    [Parameter(Mandatory)]
    [ValidateSet("cairo", "pango")]
    [String] $Library,

    [String] $DependencyRoot = "deps"
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path -LiteralPath $DependencyRoot).Path
$prefix = $root.Replace("\", "/")
$pkgConfigDir = Join-Path $root "lib/pkgconfig"
New-Item -Path $pkgConfigDir -ItemType Directory -Force | Out-Null

function Get-DefineValue {
    param (
        [Parameter(Mandatory)] [String] $Path,
        [Parameter(Mandatory)] [String] $Name,
        [Switch] $Quoted
    )

    $content = Get-Content -LiteralPath $Path -Raw
    $pattern = if ($Quoted) {
        "(?m)^\s*#\s*define\s+$([regex]::Escape($Name))\s+`"([^`"]+)`""
    } else {
        "(?m)^\s*#\s*define\s+$([regex]::Escape($Name))\s+(\d+)"
    }
    $match = [regex]::Match($content, $pattern)
    if (-not $match.Success) {
        throw "Could not find $Name in $Path"
    }

    return $match.Groups[1].Value
}

function Write-PkgConfig {
    param (
        [Parameter(Mandatory)] [String] $FileBase,
        [Parameter(Mandatory)] [String] $Name,
        [Parameter(Mandatory)] [String] $Description,
        [Parameter(Mandatory)] [String] $Version,
        [Parameter(Mandatory)] [AllowEmptyString()] [String] $Libraries,
        [Parameter(Mandatory)] [AllowEmptyString()] [String] $Cflags,
        [String] $Requires = "",
        [String] $RequiresPrivate = "",
        [String[]] $Variables = @()
    )

    $lines = [System.Collections.Generic.List[String]]::new()
    $lines.Add("prefix=$prefix")
    $lines.Add('exec_prefix=${prefix}')
    $lines.Add('libdir=${prefix}/lib')
    $lines.Add('includedir=${prefix}/include')
    $lines.Add('bindir=${prefix}/bin')
    foreach ($variable in $Variables) {
        $lines.Add($variable)
    }
    $lines.Add("")
    $lines.Add("Name: $Name")
    $lines.Add("Description: $Description")
    $lines.Add("Version: $Version")
    if ($Requires) {
        $lines.Add("Requires: $Requires")
    }
    if ($RequiresPrivate) {
        $lines.Add("Requires.private: $RequiresPrivate")
    }
    $lines.Add("Libs: -L`${libdir} $Libraries")
    $lines.Add("Cflags: $Cflags")

    $path = Join-Path $pkgConfigDir "$FileBase.pc"
    [System.IO.File]::WriteAllLines($path, $lines, [System.Text.UTF8Encoding]::new($false))
}

if ($Library -eq "cairo") {
    $zlibVersion = Get-DefineValue -Path (Join-Path $root "include/zlib.h") -Name "ZLIB_VERSION" -Quoted
    $pngVersion = Get-DefineValue -Path (Join-Path $root "include/libpng16/png.h") -Name "PNG_LIBPNG_VER_STRING" -Quoted

    Write-PkgConfig `
        -FileBase "zlib" `
        -Name "zlib" `
        -Description "zlib compression library" `
        -Version $zlibVersion `
        -Libraries "-lzlib_a" `
        -Cflags '-I${includedir}'

    Write-PkgConfig `
        -FileBase "libpng" `
        -Name "libpng" `
        -Description "PNG reference library" `
        -Version $pngVersion `
        -Libraries "-llibpng" `
        -Cflags '-I${includedir}/libpng16' `
        -RequiresPrivate "zlib"
}

if ($Library -eq "pango") {
    $glibConfig = Join-Path $root "lib/glib-2.0/include/glibconfig.h"
    $glibVersion = @(
        Get-DefineValue -Path $glibConfig -Name "GLIB_MAJOR_VERSION"
        Get-DefineValue -Path $glibConfig -Name "GLIB_MINOR_VERSION"
        Get-DefineValue -Path $glibConfig -Name "GLIB_MICRO_VERSION"
    ) -join "."

    $cairoVersionHeader = Join-Path $root "include/cairo/cairo-version.h"
    $cairoVersion = @(
        Get-DefineValue -Path $cairoVersionHeader -Name "CAIRO_VERSION_MAJOR"
        Get-DefineValue -Path $cairoVersionHeader -Name "CAIRO_VERSION_MINOR"
        Get-DefineValue -Path $cairoVersionHeader -Name "CAIRO_VERSION_MICRO"
    ) -join "."

    Write-PkgConfig `
        -FileBase "glib-2.0" `
        -Name "GLib" `
        -Description "C utility library" `
        -Version $glibVersion `
        -Libraries "-lglib-2.0" `
        -Cflags '-I${includedir}/glib-2.0 -I${libdir}/glib-2.0/include' `
        -Variables 'glib_mkenums=${bindir}/glib-mkenums'

    Write-PkgConfig `
        -FileBase "gobject-2.0" `
        -Name "GObject" `
        -Description "GLib type, object and signal system" `
        -Version $glibVersion `
        -Libraries "-lgobject-2.0" `
        -Cflags '-I${includedir}/glib-2.0 -I${libdir}/glib-2.0/include' `
        -Requires "glib-2.0"

    Write-PkgConfig `
        -FileBase "gio-2.0" `
        -Name "GIO" `
        -Description "GLib I/O library" `
        -Version $glibVersion `
        -Libraries "-lgio-2.0" `
        -Cflags '-I${includedir}/glib-2.0 -I${libdir}/glib-2.0/include' `
        -Requires "gobject-2.0, glib-2.0"

    Write-PkgConfig `
        -FileBase "cairo" `
        -Name "cairo" `
        -Description "Multi-platform 2D graphics library" `
        -Version $cairoVersion `
        -Libraries "-lcairo" `
        -Cflags '-I${includedir}/cairo'

    foreach ($feature in @("cairo-win32", "cairo-dwrite-font", "cairo-win32-dwrite-font")) {
        Write-PkgConfig `
            -FileBase $feature `
            -Name $feature `
            -Description "Cairo Windows font backend" `
            -Version $cairoVersion `
            -Libraries "" `
            -Cflags "" `
            -Requires "cairo"
    }
}
