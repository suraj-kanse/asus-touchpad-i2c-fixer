# Fix-Touchpad.ps1
# Diagnostics & auto-reset utility for ASUS Touchpad I2C HID Device

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$Silent,
    [string]$LogFile = "$env:ProgramData\TouchpadFixer\touchpad-fixer.log",
    [switch]$Install,
    [switch]$Uninstall
)

$TOUCHPAD_HARDWARE_ID = "*ASUP1204*"
$TOUCHPAD_FRIENDLY_NAME = "I2C HID Device"
$TASK_NAME = "TouchpadFixer"

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

function Register-AutomationTask {
    Write-Log "Registering Windows Scheduled Task for automation..." "INFO"
    
    # Task XML template for wakeup and logon triggers
    $xmlTemplate = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Date>2026-08-14T19:22:00</Date>
    <Author>Touchpad Fixer Utility</Author>
    <Description>Automatically runs touchpad diagnostics and resets the I2C bus on wakeup/logon.</Description>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
    </LogonTrigger>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="System"&gt;&lt;Select Path="System"&gt;*[System[Provider[@Name='Microsoft-Windows-Kernel-Power'] and (EventID=107 or EventID=507)]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription>
    </EventTrigger>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="System"&gt;&lt;Select Path="System"&gt;*[System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and (EventID=1)]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription>
    </EventTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <GroupId>S-1-5-32-544</GroupId>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT1M</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "SCRIPT_PATH" -Silent</Arguments>
    </Exec>
  </Actions>
</Task>
"@

    $xml = $xmlTemplate.Replace("SCRIPT_PATH", $PSCommandPath)

    try {
        Register-ScheduledTask -TaskName $TASK_NAME -Xml $xml -Force | Out-Null
        Write-Log "Successfully registered Scheduled Task '$TASK_NAME'." "SUCCESS"
        Write-Log "The script will run automatically on logon and system wake (from sleep or Modern Standby)." "SUCCESS"
    } catch {
        Write-Log "Failed to register Scheduled Task: $_" "ERROR"
        exit 1
    }
}

function Unregister-AutomationTask {
    Write-Log "Unregistering Windows Scheduled Task..." "INFO"
    try {
        # Check if task exists
        Get-ScheduledTask -TaskName $TASK_NAME -ErrorAction Stop | Out-Null
        Unregister-ScheduledTask -TaskName $TASK_NAME -Confirm:$false | Out-Null
        Write-Log "Successfully unregistered Scheduled Task '$TASK_NAME'." "SUCCESS"
    } catch {
        Write-Log "Scheduled Task '$TASK_NAME' is not registered or could not be removed." "WARNING"
    }
}

# Main Execution Flow
if (-not $Silent) {
    Write-Host "ASUS Touchpad Fixer Utility" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host "===========================" -ForegroundColor White
}

# 1. Check Admin Elevation for Task Actions or Reset
$isAdmin = Test-IsAdmin

if ($Install -or $Uninstall) {
    if (-not $isAdmin) {
        Write-Log "Action requires Administrator privileges. Requesting elevation..." "WARNING"
        $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        if ($Install) { $argList += " -Install" }
        if ($Uninstall) { $argList += " -Uninstall" }
        if ($LogFile) { $argList += " -LogFile `"$LogFile`"" }
        
        try {
            Start-Process powershell -ArgumentList $argList -Verb RunAs
            exit 0
        } catch {
            Write-Log "UAC elevation failed. Please run PowerShell as Administrator to install/uninstall." "ERROR"
            exit 1
        }
    }

    if ($Install) {
        Register-AutomationTask
    } elseif ($Uninstall) {
        Unregister-AutomationTask
    }
    exit 0
}

Write-Log "Starting touchpad diagnostics..." "INFO"

# 2. Diagnose Touchpad
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

# 3. Check Admin Elevation for Reset
if (-not $isAdmin) {
    Write-Log "Reset requires Administrator privileges. Requesting elevation..." "WARNING"
    
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

# 4. Perform Reset
$result = Reset-Touchpad
if ($result) {
    exit 0
} else {
    exit 1
}
