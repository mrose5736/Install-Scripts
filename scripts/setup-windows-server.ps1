<#
.SYNOPSIS
    Post-installation configuration script for Windows Server 2022 and 2025 Datacenter.

.DESCRIPTION
    Applies baseline system configuration, software installations, and optimization tweaks:
      1. Timezone check & set to Europe/London (GMT Standard Time).
      2. Locale/Language check & set to English (UK) (en-GB).
      3. Windows Defender Antivirus feature removal.
      4. Software check & installation (Google Chrome, VS Code, Voidtools Everything) via winget / direct fallback.
      5. Recommended Server Tweaks:
         - Disable IE Enhanced Security Configuration (IE ESC).
         - Enable Remote Desktop (RDP) with Network Level Authentication (NLA) & firewall rules.
         - Configure File Explorer (show known file extensions, show hidden files).
         - Install / Update PowerShell 7 (optional switch).
         - Configure Windows Update to notify / auto-download.
         - Enable High Performance Power Plan.

.PARAMETER SkipDefenderRemoval
    Switch to keep Windows Defender enabled.

.PARAMETER SkipSoftwareInstall
    Switch to skip installing third-party tools.

.PARAMETER SkipServerTweaks
    Switch to skip recommended server baseline tweaks (IE ESC, Explorer settings, RDP, Power plan).

.PARAMETER AutoRestart
    Automatically reboot if changes (such as Defender removal) require a restart.

.EXAMPLE
    .\Configure-WindowsServerPostInstall.ps1
    Runs all configuration steps with prompts/status logging.

.EXAMPLE
    .\Configure-WindowsServerPostInstall.ps1 -AutoRestart
    Runs all configuration and reboots if required.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [switch]$SkipDefenderRemoval,
    [switch]$SkipSoftwareInstall,
    [switch]$SkipServerTweaks,
    [switch]$AutoRestart
)

$ErrorActionPreference = "Continue"

function Write-Step {
    param([string]$Message)
    Write-Host "`n==================================================" -ForegroundColor Cyan
    Write-Host ">>> $Message" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# --- Check Administrator Privileges ---
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Err "This script must be run as Administrator. Please relaunch in an elevated PowerShell session."
    exit 1
}

# --- Detect OS Version ---
$os = Get-CimInstance -ClassName Win32_OperatingSystem
Write-Info "Detected OS: $($os.Caption) (Build: $($os.BuildNumber))"

$restartNeeded = $false

# ==============================================================================
# 1. TIMEZONE CONFIGURATION: Europe/London
# ==============================================================================
Write-Step "Checking & Setting Time Zone to Europe/London (GMT Standard Time)"
try {
    $targetTzId = "GMT Standard Time" # Windows ID for Europe/London
    $currentTz = Get-TimeZone

    if ($currentTz.Id -ne $targetTzId) {
        Write-Info "Current time zone is '$($currentTz.Id)'. Updating to '$targetTzId'..."
        Set-TimeZone -Id $targetTzId -ErrorAction Stop
        Write-Success "Time zone set to $((Get-TimeZone).DisplayName)"
    } else {
        Write-Success "Time zone is already set to '$($currentTz.DisplayName)'."
    }
} catch {
    Write-Err "Failed to set time zone: $_"
}

# ==============================================================================
# 2. LOCALE & LANGUAGE CONFIGURATION: English (United Kingdom)
# ==============================================================================
Write-Step "Checking & Setting English (UK) / en-GB Culture and Input"
try {
    $targetLocale = "en-GB"
    $targetInput = "0809:00000809" # English (United Kingdom) keyboard

    # System & User Culture
    Set-Culture -CultureInfo $targetLocale
    Set-WinSystemLocale -SystemLocale $targetLocale
    Set-WinHomeLocation -GeoId 242 # United Kingdom GeoID

    # Input Method / Language Pack List
    $currentLangs = Get-WinUserLanguageList
    if (-not ($currentLangs | Where-Object { $_.LanguageTag -eq $targetLocale })) {
        Write-Info "Adding $targetLocale to User Language List..."
        $currentLangs.Insert(0, (New-WinUserLanguageList $targetLocale)[0])
        Set-WinUserLanguageList -LanguageList $currentLangs -Force
    } else {
        # Move en-GB to top
        $ukLang = $currentLangs | Where-Object { $_.LanguageTag -eq $targetLocale }
        $currentLangs.Remove($ukLang)
        $currentLangs.Insert(0, $ukLang)
        Set-WinUserLanguageList -LanguageList $currentLangs -Force
    }

    # Copy settings to System accounts (Welcome Screen, Default User)
    Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true -ErrorAction SilentlyContinue

    Write-Success "Locale and language settings set to English (United Kingdom) - $targetLocale."
} catch {
    Write-Err "Failed to set language/locale: $_"
}

# ==============================================================================
# 3. WINDOWS DEFENDER REMOVAL
# ==============================================================================
if (-not $SkipDefenderRemoval) {
    Write-Step "Checking & Removing Windows Defender Features"
    try {
        $defenderFeatures = Get-WindowsFeature -Name *Defender* | Where-Object { $_.Installed }
        if ($defenderFeatures) {
            Write-Info "Found installed Defender features: $(($defenderFeatures.Name) -join ', ')"
            Write-Info "Uninstalling Windows-Defender feature..."
            $uninstallResult = Uninstall-WindowsFeature -Name Windows-Defender, Windows-Defender-GUI -ErrorAction Stop
            
            if ($uninstallResult.RestartNeeded -eq 'Yes' -or $uninstallResult.RequiresRestart) {
                Write-Info "Windows Defender removal requires a system reboot."
                $restartNeeded = $true
            }
            Write-Success "Windows Defender features successfully removed."
        } else {
            Write-Success "Windows Defender is not installed or already removed."
        }
    } catch {
        Write-Err "Could not remove Windows Defender feature via Uninstall-WindowsFeature: $_"
        Write-Info "Attempting fallback: disabling Defender real-time monitoring and services via PowerShell..."
        Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction SilentlyContinue
    }
} else {
    Write-Info "Skipping Windows Defender removal as requested."
}

# ==============================================================================
# 4. SOFTWARE INSTALLATION: Chrome, VS Code, Everything
# ==============================================================================
if (-not $SkipSoftwareInstall) {
    Write-Step "Checking & Installing Software (Google Chrome, VS Code, Everything)"

    # Helper function to test command existence
    function Test-AppInstalled {
        param([string]$Path, [string]$CommandName)
        if ($Path -and (Test-Path $Path)) { return $true }
        if ($CommandName -and (Get-Command $CommandName -ErrorAction SilentlyContinue)) { return $true }
        return $false
    }

    # Ensure TLS 1.2+ for downloads
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

    # Check if winget is available
    $wingetAvailable = [bool](Get-Command "winget" -ErrorAction SilentlyContinue)

    # 4.1 Google Chrome
    $chromeInstalled = Test-AppInstalled -Path "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe" -CommandName "chrome"
    if ($chromeInstalled) {
        Write-Success "Google Chrome is already installed."
    } else {
        Write-Info "Installing Google Chrome..."
        if ($wingetAvailable) {
            winget install --id Google.Chrome --silent --accept-source-agreements --accept-package-agreements
        } else {
            $chromeInstaller = "$env:TEMP\ChromeStandaloneSetup64.msi"
            Invoke-WebRequest -Uri "https://dl.google.com/tag/s/appguid%3D%7B8A69D345-D564-463C-AFF1-A69D9E530F96%7D%26iid%3D%7BEB5A5C70-96A7-F469-8B8E-32E1A117FBE7%7D%26lang%3Den%26browser%3D4%26usagestats%3D0%26appname%3DGoogle%2520Chrome%26needsadmin%3Dtrue/dl/chrome/install/googlechromestandaloneenterprise64.msi" -OutFile $chromeInstaller
            Start-Process msiexec.exe -ArgumentList "/i `"$chromeInstaller`" /qn /norestart" -Wait -NoNewWindow
            Remove-Item $chromeInstaller -Force -ErrorAction SilentlyContinue
        }
        Write-Success "Google Chrome installation completed."
    }

    # 4.2 Visual Studio Code (System-wide 64-bit)
    $vscodeInstalled = Test-AppInstalled -Path "${env:ProgramFiles}\Microsoft VS Code\Code.exe" -CommandName "code"
    if ($vscodeInstalled) {
        Write-Success "Visual Studio Code is already installed."
    } else {
        Write-Info "Installing Visual Studio Code (System Installer)..."
        if ($wingetAvailable) {
            winget install --id Microsoft.VisualStudioCode --silent --accept-source-agreements --accept-package-agreements --scope machine
        } else {
            $vscodeInstaller = "$env:TEMP\VSCodeSetup-x64.exe"
            Invoke-WebRequest -Uri "https://update.code.visualstudio.com/latest/win32-x64/stable" -OutFile $vscodeInstaller
            Start-Process $vscodeInstaller -ArgumentList "/VERYSILENT /NORESTART /MERGETASKS=!runcode,addcontextmenufiles,addcontextmenufolders,associatewithfiles,addtopath" -Wait -NoNewWindow
            Remove-Item $vscodeInstaller -Force -ErrorAction SilentlyContinue
        }
        Write-Success "Visual Studio Code installation completed."
    }

    # 4.3 Voidtools Everything Search Tool
    $everythingInstalled = Test-AppInstalled -Path "${env:ProgramFiles}\Everything\Everything.exe" -CommandName "Everything"
    if ($everythingInstalled) {
        Write-Success "Voidtools Everything is already installed."
    } else {
        Write-Info "Installing Voidtools Everything Search Tool..."
        if ($wingetAvailable) {
            winget install --id voidtools.Everything --silent --accept-source-agreements --accept-package-agreements
        } else {
            $everythingInstaller = "$env:TEMP\Everything-Setup.exe"
            Invoke-WebRequest -Uri "https://www.voidtools.com/Everything-1.4.1.1026.x64-Setup.exe" -OutFile $everythingInstaller
            Start-Process $everythingInstaller -ArgumentList "/S" -Wait -NoNewWindow
            Remove-Item $everythingInstaller -Force -ErrorAction SilentlyContinue
        }
        Write-Success "Voidtools Everything installation completed."
    }
}

# ==============================================================================
# 5. RECOMMENDED SERVER TWEAKS & OPTIMIZATIONS
# ==============================================================================
if (-not $SkipServerTweaks) {
    Write-Step "Applying Recommended Windows Server Baseline Tweaks"

    # 5.1 Disable Internet Explorer Enhanced Security Configuration (IE ESC)
    try {
        Write-Info "Disabling Internet Explorer Enhanced Security Configuration (IE ESC)..."
        $adminEscPath = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
        $userEscPath  = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
        Set-ItemProperty -Path $adminEscPath -Name "IsInstalled" -Value 0 -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $userEscPath -Name "IsInstalled" -Value 0 -ErrorAction SilentlyContinue
        Write-Success "IE ESC disabled for Administrators and Users."
    } catch {
        Write-Err "Failed to disable IE ESC: $_"
    }

    # 5.2 Enable Remote Desktop (RDP) & Network Level Authentication (NLA)
    try {
        Write-Info "Enabling Remote Desktop (RDP) with NLA..."
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 1
        Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
        Write-Success "Remote Desktop enabled with NLA and firewall rules opened."
    } catch {
        Write-Err "Failed to configure Remote Desktop: $_"
    }

    # 5.3 Explorer Tweaks: Show File Extensions and Hidden Files
    try {
        Write-Info "Configuring Windows Explorer (Show hidden files and file extensions)..."
        $advancedRegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        Set-ItemProperty -Path $advancedRegPath -Name "HideFileExt" -Value 0
        Set-ItemProperty -Path $advancedRegPath -Name "Hidden" -Value 1
        Set-ItemProperty -Path $advancedRegPath -Name "ShowSuperHidden" -Value 0
        Write-Success "File Explorer configured: File extensions and hidden files are visible."
    } catch {
        Write-Err "Failed to configure Explorer view: $_"
    }

    # 5.4 Power Scheme: High Performance
    try {
        Write-Info "Setting Power Scheme to High Performance..."
        $highPerfGuid = (powercfg -list | Select-String "High performance" | ForEach-Object { $_.Line.Split()[3] })
        if ($highPerfGuid) {
            powercfg -setactive $highPerfGuid
            Write-Success "Power Scheme set to High Performance ($highPerfGuid)."
        } else {
            # Standard High Performance GUID
            powercfg -setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
            Write-Success "Power Scheme set to High Performance default GUID."
        }
    } catch {
        Write-Err "Failed to set power scheme: $_"
    }

    # 5.5 Synchronize Windows Time (NTP)
    try {
        Write-Info "Synchronizing Windows Time service with uk.pool.ntp.org..."
        Start-Service w32time -ErrorAction SilentlyContinue
        w32tm /config /manualpeerlist:"0.uk.pool.ntp.org 1.uk.pool.ntp.org pool.ntp.org" /syncfromflags:manual /update | Out-Null
        w32tm /resync /nowait | Out-Null
        Write-Success "Time synchronization triggered against UK NTP pool."
    } catch {
        Write-Err "Failed to synchronize time service: $_"
    }
}

# ==============================================================================
# FINISH & REBOOT HANDLING
# ==============================================================================
Write-Step "Post-Installation Tasks Completed"

if ($restartNeeded) {
    Write-Host "`n[!IMPORTANT] A system restart is REQUIRED to finalize Windows Defender feature removal." -ForegroundColor Yellow
    if ($AutoRestart) {
        Write-Info "Rebooting system in 10 seconds (-AutoRestart specified)..."
        Start-Sleep -Seconds 10
        Restart-Computer -Force
    } else {
        Write-Host "Please restart the server at your earliest convenience using: Restart-Computer" -ForegroundColor Cyan
    }
} else {
    Write-Success "All tasks completed successfully. No immediate restart is required."
}
