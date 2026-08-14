# Fix-Touchpad.ps1
# Diagnostics & auto-reset utility for ASUS Touchpad I2C HID Device

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$Silent,
    [string]$LogFile = "$env:ProgramData\TouchpadFixer\touchpad-fixer.log"
)

$TOUCHPAD_HARDWARE_ID = "*ASUP1204*"
$TOUCHPAD_FRIENDLY_NAME = "I2C HID Device"

# Initialize Logging
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Type = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] [$Type] $Message"

    # Console Output (if not silent)
    if (-not $Silent) {
        $color = switch ($Type) {
            "WARNING" { "Yellow" }
            "ERROR"   { "Red" }
            "SUCCESS" { "Green" }
            default   { "White" }
        }
        Write-Host $Message -ForegroundColor $color
    }

    # File Output
    if ($LogFile) {
        try {
            $logDir = [System.IO.Path]::GetDirectoryName($LogFile)
            if ($logDir -and -not (Test-Path $logDir)) {
                New-Item -ItemType Directory -Path $logDir -Force | Out-Null
            }
            $logLine | Out-File -FilePath $LogFile -Append -Encoding utf8
        } catch {
            if (-not $Silent) {
                Write-Warning "Could not write to log file: $_"
            }
        }
    }
}

function Test-IsAdmin {
    return [bool]([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-TouchpadDevice {
    $device = Get-PnpDevice -FriendlyName $TOUCHPAD_FRIENDLY_NAME -ErrorAction SilentlyContinue | 
              Where-Object { $_.HardwareID -like $TOUCHPAD_HARDWARE_ID -or $_.InstanceId -like "*ASUP*" }
    
    if (-not $device) {
        $device = Get-PnpDevice -FriendlyName $TOUCHPAD_FRIENDLY_NAME -ErrorAction SilentlyContinue
    }

    if ($device -is [array]) {
        $errorDevice = $device | Where-Object { $_.Status -ne "OK" }
        $device = if ($errorDevice) { $errorDevice[0] } else { $device[0] }
    }

    return $device
}

function Get-I2CControllers {
    return Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { 
        $_.FriendlyName -like "*I2C Host Controller*" -or 
        $_.FriendlyName -like "*I2C Controller*" -or
        $_.FriendlyName -like "*Serial IO I2C*"
    }
}

function Reset-Touchpad {
    $device = Get-TouchpadDevice
    if (-not $device) {
        Write-Log "Cannot reset: No touchpad device found." "ERROR"
        return $false
    }

    Write-Log "Attempting to reset touchpad device..." "INFO"

    # Method 1: Try disabling and enabling the I2C HID Device
    Write-Log "Method 1: Toggling I2C HID Device (disable/enable)..." "INFO"
    try {
        Disable-PnpDevice -InstanceId $device.InstanceId -Confirm:$false -ErrorAction Stop
        Start-Sleep -Seconds 1
        Enable-PnpDevice -InstanceId $device.InstanceId -Confirm:$false -ErrorAction Stop
        Start-Sleep -Seconds 1
        
        $device = Get-TouchpadDevice
        if ($device.Status -eq "OK") {
            Write-Log "Success: Touchpad is now working (Method 1)." "SUCCESS"
            return $true
        }
    } catch {
        Write-Log "Method 1 failed: $_" "WARNING"
    }

    # Method 2: Try power-cycling the I2C Controllers
    Write-Log "Method 2: Resetting Intel/AMD Serial IO I2C Host Controllers..." "INFO"
    $controllers = Get-I2CControllers
    if ($controllers) {
        foreach ($ctrl in $controllers) {
            Write-Log "Restarting: $($ctrl.FriendlyName)..." "INFO"
            try {
                Disable-PnpDevice -InstanceId $ctrl.InstanceId -Confirm:$false -ErrorAction Stop
                Start-Sleep -Seconds 1
                Enable-PnpDevice -InstanceId $ctrl.InstanceId -Confirm:$false -ErrorAction Stop
            } catch {
                Write-Log "Failed to restart controller $($ctrl.FriendlyName): $_" "WARNING"
            }
        }
        Start-Sleep -Seconds 2
        
        $device = Get-TouchpadDevice
        if ($device.Status -eq "OK") {
            Write-Log "Success: Touchpad is now working (Method 2)." "SUCCESS"
            return $true
        }
    }

    # Method 3: Uninstall device and scan for hardware changes (Matches the manual user fix)
    Write-Log "Method 3: Uninstalling device and scanning for hardware changes..." "INFO"
    try {
        pnputil /remove-device $device.InstanceId | Out-Null
        Start-Sleep -Seconds 2
        pnputil /scan-devices | Out-Null
        Start-Sleep -Seconds 2

        $device = Get-TouchpadDevice
        if ($device -and $device.Status -eq "OK") {
            Write-Log "Success: Touchpad has been reinstalled and is now working (Method 3)." "SUCCESS"
            return $true
        }
    } catch {
        Write-Log "Method 3 failed: $_" "WARNING"
    }

    Write-Log "All reset methods completed. Checking final status..." "INFO"
    $device = Get-TouchpadDevice
    if ($device -and $device.Status -eq "OK") {
        Write-Log "Touchpad is working!" "SUCCESS"
        return $true
    } else {
        Write-Log "Could not recover the touchpad. Manual intervention or a restart may be required." "ERROR"
        return $false
    }
}

# Main Execution Flow
if (-not $Silent) {
    Write-Host "ASUS Touchpad Fixer Utility" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host "===========================" -ForegroundColor White
}

Write-Log "Starting touchpad diagnostics..." "INFO"

# 1. Diagnose
$device = Get-TouchpadDevice
if (-not $device) {
    Write-Log "No touchpad device found." "WARNING"
    exit 1
}

Write-Log "Device: $($device.FriendlyName) [$($device.InstanceId)]" "INFO"
Write-Log "Status: $($device.Status)" "INFO"

if ($device.Status -eq "OK" -and -not $Force) {
    Write-Log "The touchpad is already working normally. Run with -Force to reset anyway." "SUCCESS"
    exit 0
}

# 2. Check Admin Elevation
$isAdmin = Test-IsAdmin
if (-not $isAdmin) {
    Write-Log "Script is not running with Administrator privileges. Requesting elevation..." "WARNING"
    
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($Force) { $argList += " -Force" }
    if ($Silent) { $argList += " -Silent" }
    if ($LogFile) { $argList += " -LogFile `"$LogFile`"" }
    
    try {
        Start-Process powershell -ArgumentList $argList -Verb RunAs
        exit 0
    } catch {
        Write-Log "UAC elevation failed. Run PowerShell as Administrator to reset." "ERROR"
        exit 1
    }
}

# 3. Perform Reset
$result = Reset-Touchpad
if ($result) {
    exit 0
} else {
    exit 1
}
