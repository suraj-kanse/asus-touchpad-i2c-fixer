# Fix-Touchpad.ps1
# Diagnostics & auto-reset utility for ASUS Touchpad I2C HID Device

$TOUCHPAD_HARDWARE_ID = "*ASUP1204*"
$TOUCHPAD_FRIENDLY_NAME = "I2C HID Device"

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
        Write-Warning "Cannot reset: No touchpad device found."
        return $false
    }

    Write-Host "Attempting to reset touchpad device..." -ForegroundColor Cyan

    # Method 1: Try disabling and enabling the I2C HID Device
    Write-Host "Method 1: Toggling I2C HID Device (disable/enable)..." -ForegroundColor Gray
    try {
        Disable-PnpDevice -InstanceId $device.InstanceId -Confirm:$false -ErrorAction Stop
        Start-Sleep -Seconds 1
        Enable-PnpDevice -InstanceId $device.InstanceId -Confirm:$false -ErrorAction Stop
        Start-Sleep -Seconds 1
        
        $device = Get-TouchpadDevice
        if ($device.Status -eq "OK") {
            Write-Host "Success: Touchpad is now working (Method 1)." -ForegroundColor Green
            return $true
        }
    } catch {
        Write-Warning "Method 1 failed: $_"
    }

    # Method 2: Try power-cycling the I2C Controllers
    Write-Host "Method 2: Resetting Intel/AMD Serial IO I2C Host Controllers..." -ForegroundColor Gray
    $controllers = Get-I2CControllers
    if ($controllers) {
        foreach ($ctrl in $controllers) {
            Write-Host "Restarting: $($ctrl.FriendlyName)..." -ForegroundColor Gray
            try {
                Disable-PnpDevice -InstanceId $ctrl.InstanceId -Confirm:$false -ErrorAction Stop
                Start-Sleep -Seconds 1
                Enable-PnpDevice -InstanceId $ctrl.InstanceId -Confirm:$false -ErrorAction Stop
            } catch {
                Write-Warning "Failed to restart controller $($ctrl.FriendlyName): $_"
            }
        }
        Start-Sleep -Seconds 2
        
        $device = Get-TouchpadDevice
        if ($device.Status -eq "OK") {
            Write-Host "Success: Touchpad is now working (Method 2)." -ForegroundColor Green
            return $true
        }
    }

    # Method 3: Uninstall device and scan for hardware changes (Matches the manual user fix)
    Write-Host "Method 3: Uninstalling device and scanning for hardware changes..." -ForegroundColor Gray
    try {
        # Using pnputil which is extremely reliable on Windows 10/11
        pnputil /remove-device $device.InstanceId | Out-Null
        Start-Sleep -Seconds 2
        pnputil /scan-devices | Out-Null
        Start-Sleep -Seconds 2

        $device = Get-TouchpadDevice
        if ($device -and $device.Status -eq "OK") {
            Write-Host "Success: Touchpad has been reinstalled and is now working (Method 3)." -ForegroundColor Green
            return $true
        }
    } catch {
        Write-Warning "Method 3 failed: $_"
    }

    Write-Host "All reset methods completed. Checking final status..."
    $device = Get-TouchpadDevice
    if ($device -and $device.Status -eq "OK") {
        Write-Host "Touchpad is working!" -ForegroundColor Green
        return $true
    } else {
        Write-Error "Could not recover the touchpad. Manual intervention or a restart may be required."
        return $false
    }
}

# Main Execution Flow
Write-Host "ASUS Touchpad Fixer Utility" -ForegroundColor White -BackgroundColor DarkBlue
Write-Host "===========================" -ForegroundColor White

# 1. Diagnose
$device = Get-TouchpadDevice
if (-not $device) {
    Write-Warning "No touchpad device found."
    exit 1
}

Write-Host "Device: $($device.FriendlyName) [$($device.InstanceId)]"
Write-Host "Status: $($device.Status)"

if ($device.Status -eq "OK") {
    Write-Host "The touchpad is already working normally." -ForegroundColor Green
    exit 0
}

# 2. Check Admin Elevation
$isAdmin = Test-IsAdmin
if (-not $isAdmin) {
    Write-Host "Script is not running with Administrator privileges." -ForegroundColor Yellow
    Write-Host "Requesting UAC elevation to reset hardware..." -ForegroundColor Cyan
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit 0
}

# 3. Perform Reset
Reset-Touchpad
