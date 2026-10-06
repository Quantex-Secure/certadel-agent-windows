#requires -Version 7
<#
.SYNOPSIS
  Builds the acme-manager Windows installer (.msi).

.DESCRIPTION
  Publishes the Service as a self-contained win-x64 build (no .NET runtime
  required on the target server), then compiles the WiX installer that packages
  it, registers the "AcmeManager" Windows Service, and adds a firewall rule for
  the web UI on TCP 9443.

  Output: packaging/AcmeManager.Installer/bin/x64/Release/acme-manager-setup.msi

.PARAMETER Version
  Product version stamped into the MSI. Defaults to the project's VersionPrefix
  (from Directory.Build.props), so a bare invocation stamps the real version.

.PARAMETER Runtime
  .NET runtime identifier to publish (default win-x64).

.EXAMPLE
  pwsh packaging/build-msi.ps1 -Version 0.2.0
#>
[CmdletBinding()]
param(
    [string] $Version = "",
    [string] $Runtime = "win-x64",
    [string] $Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$repoRoot   = Resolve-Path (Join-Path $PSScriptRoot "..")
$svcProj    = Join-Path $repoRoot "core/src/AcmeManager.Service/AcmeManager.Service.csproj"

# Default the version to the project's VersionPrefix (honours Directory.Build.props)
# so a bare invocation stamps the real product version, not a placeholder that would
# be a downgrade over an installed build. Pass -Version to override.
if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = (dotnet msbuild $svcProj -getProperty:VersionPrefix -nologo).Trim()
    if ([string]::IsNullOrWhiteSpace($Version)) { throw "Could not resolve the project version; pass -Version explicitly." }
    Write-Host "==> Version not specified; using project VersionPrefix $Version" -ForegroundColor DarkGray
}

$wixProj    = Join-Path $PSScriptRoot "AcmeManager.Installer/AcmeManager.Installer.wixproj"
$publishDir = Join-Path $repoRoot "artifacts/publish/$Runtime"

Write-Host "==> Publishing self-contained $Runtime build..." -ForegroundColor Cyan
if (Test-Path $publishDir) { Remove-Item -Recurse -Force $publishDir }
dotnet publish $svcProj `
    -c $Configuration -r $Runtime --self-contained true `
    -p:PublishSingleFile=false `
    -o $publishDir
if ($LASTEXITCODE) { throw "dotnet publish failed ($LASTEXITCODE)" }

Write-Host "==> Building MSI (v$Version)..." -ForegroundColor Cyan
dotnet build $wixProj `
    -c $Configuration `
    -p:PublishDir=$publishDir `
    -p:ProductVersion=$Version
if ($LASTEXITCODE) { throw "MSI build failed ($LASTEXITCODE)" }

$msi = Join-Path $PSScriptRoot "AcmeManager.Installer/bin/x64/$Configuration/acme-manager-setup.msi"
Write-Host ""
Write-Host "MSI built: $msi" -ForegroundColor Green
Write-Host ("Size: {0:N1} MB" -f ((Get-Item $msi).Length / 1MB))
