# Fix-Touchpad.ps1
# Diagnostics & auto-reset utility for ASUS Touchpad I2C HID Device

$TOUCHPAD_HARDWARE_ID = "*ASUP1204*"
$TOUCHPAD_FRIENDLY_NAME = "I2C HID Device"

function Get-TouchpadStatus {
    Write-Host "Scanning for Touchpad (I2C HID Device)..." -ForegroundColor Cyan
    
    # Search by hardware ID or friendly name
    $device = Get-PnpDevice -FriendlyName $TOUCHPAD_FRIENDLY_NAME -ErrorAction SilentlyContinue | 
              Where-Object { $_.HardwareID -like $TOUCHPAD_HARDWARE_ID -or $_.InstanceId -like "*ASUP*" }
    
    if (-not $device) {
        # Fallback to check any I2C HID Device if specific ASUS hardware ID isn't found
        $device = Get-PnpDevice -FriendlyName $TOUCHPAD_FRIENDLY_NAME -ErrorAction SilentlyContinue
    }

    if (-not $device) {
        Write-Warning "No I2C HID Device (Touchpad) found on this system."
        return $null
    }

    # If multiple, take the first one or the one with Error
    if ($device -is [array]) {
        $errorDevice = $device | Where-Object { $_.Status -ne "OK" }
        if ($errorDevice) {
            $device = $errorDevice[0]
        } else {
            $device = $device[0]
        }
    }

    Write-Host "Found Device: $($device.FriendlyName)"
    Write-Host "Instance ID:  $($device.InstanceId)"
    
    if ($device.Status -eq "OK") {
        Write-Host "Status:       OK (Device is working normally)" -ForegroundColor Green
    } else {
        Write-Host "Status:       $($device.Status) (Error detected!)" -ForegroundColor Red
        if ($device.ProblemDescription) {
            Write-Host "Description:  $($device.ProblemDescription)" -ForegroundColor Yellow
        } else {
            Write-Host "Description:  Code $($device.ConfigManagerErrorCode) - This device cannot start." -ForegroundColor Yellow
        }
    }

    return $device
}

# Run diagnostics
$touchpad = Get-TouchpadStatus
