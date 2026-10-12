# Installs Temurin JDK 21 and Ghidra 12.1.4 for REA, then refreshes the VS Code registration.
# No administrator rights. Files go under %LOCALAPPDATA%\rea-tools.
# Run: powershell -ExecutionPolicy Bypass -File .\install-ghidra-java.ps1

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Root = Join-Path $env:LOCALAPPDATA 'rea-tools'
$Download = Join-Path $Root 'downloads'
New-Item -ItemType Directory -Force -Path $Download | Out-Null

$JdkZipName = 'OpenJDK21U-jdk_x64_windows_hotspot_21.0.12.1_1.zip'
$JdkUrl = 'https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.12.1%2B1/OpenJDK21U-jdk_x64_windows_hotspot_21.0.12.1_1.zip'
$JdkSha256 = 'F9D6E191AB098C0D416E7D588A24420A8621CD2F4720DAB2459B8B7B2D2D8B4E'
$JdkHome = Join-Path $Root 'jdk-21.0.12.1+1'

$GhidraZipName = 'ghidra_12.1.4_PUBLIC_20260921.zip'
$GhidraUrl = 'https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_12.1.4_build/ghidra_12.1.4_PUBLIC_20260921.zip'
$GhidraSha256 = 'DDAC49F903DA9D5BAC833E5CC79395098B9C33CFD3279BE5F31BD00387D2D4DB'
$GhidraHome = Join-Path $Root 'ghidra_12.1.4_PUBLIC'

function Get-VerifiedZip {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256
    )
    $expected = $ExpectedSha256.ToUpperInvariant()
    if (Test-Path -LiteralPath $Destination) {
        $existing = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToUpperInvariant()
        if ($existing -eq $expected) {
            Write-Host "Checksum ok: $Destination"
            return
        }
        Write-Host "Checksum mismatch, downloading again: $Destination"
        Remove-Item -LiteralPath $Destination -Force
    }
    Write-Host "Downloading $Url"
    & curl.exe -fL --retry 3 --retry-delay 2 -o $Destination $Url
    if ($LASTEXITCODE -ne 0) {
        throw "Download failed ($LASTEXITCODE): $Url"
    }
    $actual = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actual -ne $expected) {
        throw "Checksum mismatch for $Destination`nExpected $expected`nActual   $actual"
    }
    Write-Host "Checksum ok: $Destination"
}

function Expand-ZipIfMissing {
    param(
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [Parameter(Mandatory = $true)][string]$Marker
    )
    if (Test-Path -LiteralPath $Marker) {
        Write-Host "Already extracted: $Marker"
        return
    }
    Write-Host "Extracting $ZipPath"
    & tar.exe -xf $ZipPath -C $Root
    if ($LASTEXITCODE -ne 0) {
        throw "Extract failed ($LASTEXITCODE): $ZipPath"
    }
    if (-not (Test-Path -LiteralPath $Marker)) {
        throw "Extract finished but $Marker is missing."
    }
}

$jdkZip = Join-Path $Download $JdkZipName
$ghidraZip = Join-Path $Download $GhidraZipName

Get-VerifiedZip -Url $JdkUrl -Destination $jdkZip -ExpectedSha256 $JdkSha256
Get-VerifiedZip -Url $GhidraUrl -Destination $ghidraZip -ExpectedSha256 $GhidraSha256

Expand-ZipIfMissing -ZipPath $jdkZip -Marker (Join-Path $JdkHome 'bin\java.exe')
Expand-ZipIfMissing -ZipPath $ghidraZip -Marker (Join-Path $GhidraHome 'support\analyzeHeadless.bat')

Write-Host "JAVA_HOME=$JdkHome"
& (Join-Path $JdkHome 'bin\java.exe') -version
Write-Host "GHIDRA_INSTALL_DIR=$GhidraHome"

[Environment]::SetEnvironmentVariable('JAVA_HOME', $JdkHome, 'User')
[Environment]::SetEnvironmentVariable('GHIDRA_INSTALL_DIR', $GhidraHome, 'User')
$env:JAVA_HOME = $JdkHome
$env:GHIDRA_INSTALL_DIR = $GhidraHome

$jdkBin = Join-Path $JdkHome 'bin'
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ([string]::IsNullOrEmpty($userPath)) {
    [Environment]::SetEnvironmentVariable('Path', $jdkBin, 'User')
}
elseif ($userPath.Split(';') -notcontains $jdkBin) {
    [Environment]::SetEnvironmentVariable('Path', "$jdkBin;$userPath", 'User')
}

Write-Host 'Refreshing the VS Code REA registration so it receives JAVA_HOME and GHIDRA_INSTALL_DIR...'
& npx -y rea-agents@latest setup --client vscode --yes
if ($LASTEXITCODE -ne 0) {
    throw "REA setup failed ($LASTEXITCODE). Java and Ghidra are installed. Re-run: npx rea-agents@latest setup --client vscode"
}

Write-Host ''
Write-Host 'Installed.'
Write-Host "JDK:    $JdkHome"
Write-Host "Ghidra: $GhidraHome"
Write-Host 'Restart VS Code, then open a new terminal so the user environment variables load.'
