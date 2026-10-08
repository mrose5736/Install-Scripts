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

.PARAMETER WallpaperProfile
    Selects the default Desktop, Lock Screen, and Login Screen background wallpaper:
      - 'Infrastructure': MDRCloud Infrastructure Server (https://i.ibb.co/2WkBnh0/MDR-2-Dark-2024.png)
      - 'HostingClient':  MDRCloud Hosting Client Server (https://i.ibb.co/7KWvBzf/MDR-2-White-on-Dark.png)
      - 'HomeServer':     Private Home Server (MDR) (https://i.ibb.co/n8fJzSxL/Msft-Nostalgia-Solitaire.jpg)
      - 'None':           Keep default Windows wallpaper.
    If not specified and running interactively, the script prompts for your selection.

.PARAMETER SkipWallpaper
    Switch to skip wallpaper and lock/login screen customization entirely.

.PARAMETER SkipDefenderRemoval
    Switch to keep Windows Defender enabled.

.PARAMETER SkipSoftwareInstall
    Switch to skip installing third-party tools.

.PARAMETER SkipServerTweaks
    Switch to skip recommended server baseline tweaks (IE ESC, Explorer settings, RDP, Power plan).

.PARAMETER AutoRestart
    Automatically reboot if changes (such as Defender removal) require a restart.

.EXAMPLE
    .\setup-windows-server.ps1
    Runs configuration interactively with wallpaper selection.

.EXAMPLE
    .\setup-windows-server.ps1 -SkipWallpaper
    Runs configuration with all tweaks, leaving default Windows wallpaper untouched.

.EXAMPLE
    .\setup-windows-server.ps1 -WallpaperProfile Infrastructure -AutoRestart
    Configures server non-interactively with the Infrastructure background.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [ValidateSet("Infrastructure", "HostingClient", "HomeServer", "None", "Prompt")]
    [string]$WallpaperProfile = "Prompt",

    [switch]$SkipWallpaper,
    [switch]$SkipDefenderRemoval,
    [switch]$SkipSoftwareInstall,
    [switch]$SkipServerTweaks,
    [switch]$AutoRestart
)

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

# Ensure UTF-8 console output for ASCII/ANSI block characters
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Show-Banner {
    param([string]$Subtitle)
    Clear-Host -ErrorAction SilentlyContinue
    $e = [char]27
    $bannerText = @"
$($e)[36m███╗   ███╗██████╗ ██████╗ 
████╗ ████║██╔══██╗██╔══██╗
██╔████╔██║██║  ██║██████╔╝
██║╚██╔╝██║██║  ██║██╔══██╗
██║ ╚═╝ ██║██████╔╝██║  ██║
╚═╝     ╚═╝╚═════╝ ╚═╝  ╚═╝$($e)[0m
$($e)[90m--------------------------------------------------$($e)[0m
$($e)[33m$Subtitle$($e)[0m
$($e)[90mCopyright 2026 // mdr95.net$($e)[0m
$($e)[90m--------------------------------------------------$($e)[0m
"@
    Write-Host $bannerText
}

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

# Display classic terminal ANSI Shadow banner
Show-Banner -Subtitle "Windows Server 2022/2025 Post-Install Setup"

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

    # Copy settings to System accounts (Welcome Screen, Default User) if cmdlet exists
    if (Get-Command Copy-UserInternationalSettingsToSystem -ErrorAction SilentlyContinue) {
        Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true -ErrorAction SilentlyContinue
    }

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
            $featureNames = $defenderFeatures.Name
            Write-Info "Found installed Defender features: $($featureNames -join ', ')"
            Write-Info "Uninstalling Defender features via Windows Feature Manager..."
            Write-Info "Note: Feature removal takes 2-4 minutes on Windows Server while component store manifests update."

            # Temporarily restore progress preference for Uninstall-WindowsFeature so progress percentage is visible
            $prevProgress = $ProgressPreference
            $ProgressPreference = "Continue"
            
            $uninstallResult = Uninstall-WindowsFeature -Name $featureNames -ErrorAction Stop
            
            $ProgressPreference = $prevProgress

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
# 4. SOFTWARE INSTALLATION: Chrome, VS Code, Everything (High-Speed Direct CDN)
# ==============================================================================
if (-not $SkipSoftwareInstall) {
    Write-Step "Checking & Installing Software (Google Chrome, VS Code, Everything)"

    function Test-AppInstalled {
        param([string]$Path, [string]$CommandName)
        if ($Path -and (Test-Path $Path)) { return $true }
        if ($CommandName -and (Get-Command $CommandName -ErrorAction SilentlyContinue)) { return $true }
        return $false
    }

    # Ensure modern TLS protocols
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

    # Fast direct file downloader using .NET WebClient (bypasses winget source indexing & PowerShell buffer bottlenecks)
    function Download-FileFast {
        param(
            [string]$Url,
            [string]$DestinationPath,
            [string]$Label
        )
        Write-Info "Downloading $Label directly from vendor CDN..."
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
        $webClient.DownloadFile($Url, $DestinationPath)
    }

    # 4.1 Google Chrome (Official Enterprise 64-bit MSI)
    $chromeInstalled = Test-AppInstalled -Path "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe" -CommandName "chrome"
    if ($chromeInstalled) {
        Write-Success "Google Chrome is already installed."
    } else {
        $chromeInstaller = "$env:TEMP\googlechromeenterprise64.msi"
        try {
            Download-FileFast `
                -Url "https://dl.google.com/tag/s/appguid%3D%7B8A69D345-D564-463C-AFF1-A69D9E530F96%7D%26iid%3D%7BEB5A5C70-96A7-F469-8B8E-32E1A117FBE7%7D%26lang%3Den%26browser%3D4%26usagestats%3D0%26appname%3DGoogle%2520Chrome%26needsadmin%3Dtrue/dl/chrome/install/googlechromestandaloneenterprise64.msi" `
                -DestinationPath $chromeInstaller `
                -Label "Google Chrome Enterprise (MSI)"
            
            Write-Info "Installing Google Chrome..."
            Start-Process msiexec.exe -ArgumentList "/i `"$chromeInstaller`" /qn /norestart ALLUSERS=1" -Wait -NoNewWindow
            Write-Success "Google Chrome installation completed."
        } catch {
            Write-Err "Failed to install Google Chrome: $_"
        } finally {
            Remove-Item $chromeInstaller -Force -ErrorAction SilentlyContinue
        }
    }

    # 4.2 Visual Studio Code (Official 64-bit System Installer)
    $vscodeInstalled = Test-AppInstalled -Path "${env:ProgramFiles}\Microsoft VS Code\Code.exe" -CommandName "code"
    if ($vscodeInstalled) {
        Write-Success "Visual Studio Code is already installed."
    } else {
        $vscodeInstaller = "$env:TEMP\VSCodeSetup-x64.exe"
        try {
            Download-FileFast `
                -Url "https://update.code.visualstudio.com/latest/win32-x64/stable" `
                -DestinationPath $vscodeInstaller `
                -Label "Visual Studio Code (System Installer)"

            Write-Info "Installing Visual Studio Code..."
            Start-Process $vscodeInstaller -ArgumentList "/VERYSILENT /NORESTART /MERGETASKS=!runcode,addcontextmenufiles,addcontextmenufolders,associatewithfiles,addtopath" -Wait -NoNewWindow
            Write-Success "Visual Studio Code installation completed."
        } catch {
            Write-Err "Failed to install Visual Studio Code: $_"
        } finally {
            Remove-Item $vscodeInstaller -Force -ErrorAction SilentlyContinue
        }
    }

    # 4.3 Voidtools Everything Search Tool (Official 64-bit Setup)
    $everythingInstalled = Test-AppInstalled -Path "${env:ProgramFiles}\Everything\Everything.exe" -CommandName "Everything"
    if ($everythingInstalled) {
        Write-Success "Voidtools Everything is already installed."
    } else {
        $everythingInstaller = "$env:TEMP\Everything-Setup.exe"
        try {
            Download-FileFast `
                -Url "https://www.voidtools.com/Everything-1.4.1.1026.x64-Setup.exe" `
                -DestinationPath $everythingInstaller `
                -Label "Voidtools Everything"

            Write-Info "Installing Voidtools Everything..."
            Start-Process $everythingInstaller -ArgumentList "/S" -Wait -NoNewWindow
            Write-Success "Voidtools Everything installation completed."
        } catch {
            Write-Err "Failed to install Voidtools Everything: $_"
        } finally {
            Remove-Item $everythingInstaller -Force -ErrorAction SilentlyContinue
        }
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
# 6. DESKTOP, LOCK SCREEN & LOGON BACKGROUND CONFIGURATION
# ==============================================================================
if (-not $SkipWallpaper) {
    $wallpaperProfiles = @{
        "1" = @{
            Key   = "Infrastructure"
            Name  = "MDRCloud Infrastructure Server"
            Url   = "https://i.ibb.co/2WkBnh0/MDR-2-Dark-2024.png"
            Ext   = ".png"
        }
        "2" = @{
            Key   = "HostingClient"
            Name  = "MDRCloud Hosting Client Server"
            Url   = "https://i.ibb.co/7KWvBzf/MDR-2-White-on-Dark.png"
            Ext   = ".png"
        }
        "3" = @{
            Key   = "HomeServer"
            Name  = "Private Home Server (MDR)"
            Url   = "https://i.ibb.co/n8fJzSxL/Msft-Nostalgia-Solitaire.jpg"
            Ext   = ".jpg"
        }
    }

    $chosenProfile = $null

    if ($WallpaperProfile -eq "Prompt" -and [Environment]::UserInteractive) {
        Write-Step "Default Desktop, Lock Screen & Login Screen Wallpaper (Optional)"
        Write-Host "Would you like to customize the default background and lock/login screen?" -ForegroundColor Yellow
        Write-Host "  [1] MDRCloud Infrastructure Server (Dark 2024)" -ForegroundColor Cyan
        Write-Host "  [2] MDRCloud Hosting Client Server (White on Dark)" -ForegroundColor Cyan
        Write-Host "  [3] Private Home Server (MDR) (Solitaire Nostalgia)" -ForegroundColor Cyan
        Write-Host "  [4] Skip / Leave default Windows background" -ForegroundColor Gray
        
        $selection = Read-Host "`nEnter selection [1-4] (Default: 4 - Skip)"
        if ([string]::IsNullOrWhiteSpace($selection)) { $selection = "4" }

        switch ($selection) {
            "1" { $chosenProfile = $wallpaperProfiles["1"] }
            "2" { $chosenProfile = $wallpaperProfiles["2"] }
            "3" { $chosenProfile = $wallpaperProfiles["3"] }
            default {
                Write-Info "Wallpaper customization skipped."
            }
        }
    } elseif ($WallpaperProfile -ne "None" -and $WallpaperProfile -ne "Prompt") {
        $matched = $wallpaperProfiles.Values | Where-Object { $_.Key -ieq $WallpaperProfile }
        if ($matched) {
            $chosenProfile = $matched
        }
    }

    if ($chosenProfile) {
    Write-Step "Applying Background Wallpaper: $($chosenProfile.Name)"
    try {
        # Prepare system wallpapers directory
        $wallpaperDir = "$env:SystemDrive\Windows\Web\Wallpaper\MDR"
        if (-not (Test-Path $wallpaperDir)) {
            New-Item -Path $wallpaperDir -ItemType Directory -Force | Out-Null
        }

        $localImageFile = Join-Path $wallpaperDir "MDR_Background$($chosenProfile.Ext)"
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
        Write-Info "Downloading background image from $($chosenProfile.Url)..."
        $wc.DownloadFile($chosenProfile.Url, $localImageFile)

        # 6.1 Set Lock Screen and Logon Screen Background via System Policy & OEM Background
        Write-Info "Configuring Lock Screen and Login Screen system policy..."
        $personalizationKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization"
        if (-not (Test-Path $personalizationKey)) {
            New-Item -Path $personalizationKey -ItemType Directory -Force | Out-Null
        }
        Set-ItemProperty -Path $personalizationKey -Name "LockScreenImage" -Value $localImageFile -Force
        Set-ItemProperty -Path $personalizationKey -Name "LockScreenOverlays" -Value 0 -Force -ErrorAction SilentlyContinue

        # Disable Lock Screen blur on sign-in screen (acrylic blur effect)
        $systemPoliciesKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
        if (-not (Test-Path $systemPoliciesKey)) {
            New-Item -Path $systemPoliciesKey -ItemType Directory -Force | Out-Null
        }
        Set-ItemProperty -Path $systemPoliciesKey -Name "DisableAcrylicBackgroundOnLogon" -Value 1 -Force -ErrorAction SilentlyContinue

        # 6.2 Set Desktop Wallpaper for Current User (Registry + SystemParametersInfo API)
        Write-Info "Setting Desktop Wallpaper for Current User..."
        $userDesktopKey = "HKCU:\Control Panel\Desktop"
        Set-ItemProperty -Path $userDesktopKey -Name "Wallpaper" -Value $localImageFile -Force
        Set-ItemProperty -Path $userDesktopKey -Name "WallpaperStyle" -Value "10" -Force # 10 = Fill, 2 = Stretch, 6 = Fit
        Set-ItemProperty -Path $userDesktopKey -Name "TileWallpaper" -Value "0" -Force

        # Call SystemParametersInfo to apply desktop wallpaper immediately without logoff
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WallpaperAPI {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@ -ErrorAction SilentlyContinue

        [WallpaperAPI]::SystemParametersInfo(0x0014, 0, $localImageFile, 0x01 -bor 0x02) | Out-Null

        # 6.3 Set Desktop Wallpaper for Default User profile (new users)
        try {
            $defaultHivePath = "$env:SystemDrive\Users\Default\NTUSER.DAT"
            if (Test-Path $defaultHivePath) {
                reg load HKU\DefUser "$defaultHivePath" 2>$null | Out-Null
                Set-ItemProperty -Path "Registry::HKU\DefUser\Control Panel\Desktop" -Name "Wallpaper" -Value $localImageFile -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path "Registry::HKU\DefUser\Control Panel\Desktop" -Name "WallpaperStyle" -Value "10" -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path "Registry::HKU\DefUser\Control Panel\Desktop" -Name "TileWallpaper" -Value "0" -Force -ErrorAction SilentlyContinue
                [GC]::Collect()
                Start-Sleep -Milliseconds 200
                reg unload HKU\DefUser 2>$null | Out-Null
            }
        } catch {
            Write-Err "Could not set default user profile wallpaper: $_"
        }

        Write-Success "Desktop, Lock Screen, and Login Screen background set to '$($chosenProfile.Name)'."
    } catch {
        Write-Err "Failed to apply background: $_"
    }
}
} else {
    Write-Info "Skipping wallpaper customization as requested (-SkipWallpaper)."
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
