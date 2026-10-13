param([Parameter(Mandatory)] [ValidateSet('vs16')] [string] $Version)

$ErrorActionPreference = 'Stop'
$installation = & vswhere -latest -products '*' -property installationPath
if (-not $installation) { throw 'Visual Studio is not installed' }

# VS16 packages use the v142 compiler in the runner's existing VS installation.
$compiler = Get-ChildItem "$installation/VC/Tools/MSVC/14.2*/bin/Hostx64/arm64/cl.exe" -ErrorAction SilentlyContinue
if ($compiler) {
    Write-Host "$Version ARM64 compiler is already installed"
    return
}

$installer = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/setup.exe"
$arguments = @('modify', '--installPath', "`"$installation`"", '--quiet', '--norestart',
    '--add', 'Microsoft.VisualStudio.Component.VC.v142.x86.x64',
    '--add', 'Microsoft.VisualStudio.Component.VC.v142.ARM64')
$process = Start-Process $installer -ArgumentList $arguments -Wait -PassThru
if ($process.ExitCode -notin 0, 3010) { throw "$Version installation failed: $($process.ExitCode)" }
