# Fix-Touchpad.ps1
# Diagnostics & auto-reset utility for ASUS Touchpad I2C HID Device

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$Silent,
    [string]$LogFile = "$env:ProgramData\TouchpadFixer\touchpad-fixer.log",
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$CreateShortcut,
    [switch]$RemoveShortcut,
    [switch]$RegisterPath,
    [switch]$UnregisterPath
)

$TOUCHPAD_HARDWARE_ID = "*ASUP1204*"
$TOUCHPAD_FRIENDLED_NAME = "I2C HID Device"
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

# Toast Notification Helper
function Send-Notification {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Title,
        [string]$Message
    )

    try {
        [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime]
        [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType=WindowsRuntime]
        
        $toastXml = [Windows.Data.Xml.Dom.XmlDocument]::new()
        $escapedTitle = [System.Security.SecurityElement]::Escape($Title)
        $escapedMessage = [System.Security.SecurityElement]::Escape($Message)
        
        $template = @"
<toast>
  <visual>
    <binding template="ToastGeneric">
      <text>$escapedTitle</text>
      <text>$escapedMessage</text>
    </binding>
  </visual>
</toast>
"@
        $toastXml.LoadXml($template)
        
        $appId = "Microsoft.Windows.Explorer"
        $toast = [Windows.UI.Notifications.ToastNotification]::new($toastXml)
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
        Write-Log "Toast notification sent: '$Title' - '$Message'" "INFO"
    } catch {
        Write-Log "Failed to show toast notification: $_" "WARNING"
    }
}

function Test-IsAdmin {
    return [bool]([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-TouchpadDevice {
    $device = Get-PnpDevice -FriendlyName $TOUCHPAD_FRIENDLED_NAME -ErrorAction SilentlyContinue | 
              Where-Object { $_.HardwareID -like $TOUCHPAD_HARDWARE_ID -or $_.InstanceId -like "*ASUP*" }
    
    if (-not $device) {
        $device = Get-PnpDevice -FriendlyName $TOUCHPAD_FRIENDLED_NAME -ErrorAction SilentlyContinue
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

function Get-GPIOControllers {
    return Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { 
        $_.FriendlyName -like "*GPIO Host Controller*" -or 
        $_.FriendlyName -like "*GPIO Controller*"
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
            Send-Notification -Title "Touchpad Auto-Fixer" -Message "Touchpad was successfully reset and is now working (Method 1)."
            return $true
        }
    } catch {
        Write-Log "Method 1 failed: $_" "WARNING"
    }

    # Method 2: Coordinated Reset of Serial IO GPIO and I2C Host Controllers
    Write-Log "Method 2: Coordinated reset of Serial IO GPIO and I2C Host Controllers..." "INFO"
    $i2cCtrls = Get-I2CControllers
    $gpioCtrls = Get-GPIOControllers
    
    try {
        # 1. Disable Touchpad Device
        Write-Log "Disabling touchpad device..." "INFO"
        Disable-PnpDevice -InstanceId $device.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
        
        # 2. Disable I2C Controllers
        if ($i2cCtrls) {
            foreach ($ctrl in $i2cCtrls) {
                Write-Log "Disabling controller: $($ctrl.FriendlyName)..." "INFO"
                Disable-PnpDevice -InstanceId $ctrl.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
            }
        }

        # 3. Disable GPIO Controllers
        if ($gpioCtrls) {
            foreach ($gpio in $gpioCtrls) {
                Write-Log "Disabling GPIO controller: $($gpio.FriendlyName)..." "INFO"
                Disable-PnpDevice -InstanceId $gpio.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
            }
        }

        # 4. Wait for power to drain
        Write-Log "Waiting 3 seconds for power-cycle/drain..." "INFO"
        Start-Sleep -Seconds 3

        # 5. Enable GPIO Controllers (GPIO first to establish interrupts/power)
        if ($gpioCtrls) {
            foreach ($gpio in $gpioCtrls) {
                Write-Log "Enabling GPIO controller: $($gpio.FriendlyName)..." "INFO"
                Enable-PnpDevice -InstanceId $gpio.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
            }
        }

        # 6. Enable I2C Controllers
        if ($i2cCtrls) {
            foreach ($ctrl in $i2cCtrls) {
                Write-Log "Enabling controller: $($ctrl.FriendlyName)..." "INFO"
                Enable-PnpDevice -InstanceId $ctrl.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
            }
        }

        # 7. Enable Touchpad Device
        Write-Log "Enabling touchpad device..." "INFO"
        Enable-PnpDevice -InstanceId $device.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        
        $device = Get-TouchpadDevice
        if ($device.Status -eq "OK") {
            Write-Log "Success: Touchpad is now working (Method 2)." "SUCCESS"
            Send-Notification -Title "Touchpad Auto-Fixer" -Message "Coordinated I2C/GPIO bus reset succeeded (Method 2)."
            return $true
        }
    } catch {
        Write-Log "Method 2 failed: $_" "WARNING"
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
            Send-Notification -Title "Touchpad Auto-Fixer" -Message "Touchpad driver reinstalled. Touchpad is working (Method 3)."
            return $true
        }
    } catch {
        Write-Log "Method 3 failed: $_" "WARNING"
    }

    Write-Log "All reset methods completed. Checking final status..." "INFO"
    $device = Get-TouchpadDevice
    if ($device -and $device.Status -eq "OK") {
        Write-Log "Touchpad is working!" "SUCCESS"
        Send-Notification -Title "Touchpad Auto-Fixer" -Message "Touchpad reset succeeded."
        return $true
    } else {
        Write-Log "Could not recover the touchpad. Manual intervention or a restart may be required." "ERROR"
        Send-Notification -Title "Touchpad Auto-Fixer" -Message "Failed to recover touchpad. Manual reset or restart required."
        return $false
    }
}

function Register-AutomationTask {
    Write-Log "Registering Windows Scheduled Task for automation..." "INFO"
    
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
        Get-ScheduledTask -TaskName $TASK_NAME -ErrorAction Stop | Out-Null
        Unregister-ScheduledTask -TaskName $TASK_NAME -Confirm:$false | Out-Null
        Write-Log "Successfully unregistered Scheduled Task '$TASK_NAME'." "SUCCESS"
    } catch {
        Write-Log "Scheduled Task '$TASK_NAME' is not registered or could not be removed." "WARNING"
    }
}

function New-StartMenuShortcut {
    Write-Log "Creating Start Menu shortcut for manual execution..." "INFO"
    
    $startMenuPrograms = [System.IO.Path]::Combine($env:APPDATA, "Microsoft\Windows\Start Menu\Programs")
    $shortcutPath = [System.IO.Path]::Combine($startMenuPrograms, "Fix Touchpad.lnk")
    
    try {
        # Create shortcut via COM Object
        $WshShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut($shortcutPath)
        $Shortcut.TargetPath = "powershell.exe"
        $Shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
        $Shortcut.WorkingDirectory = [System.IO.Path]::GetDirectoryName($PSCommandPath)
        
        # Use a nice system hardware/touchpad-like icon
        $Shortcut.IconLocation = "$env:SystemRoot\System32\imageres.dll,26"
        $Shortcut.Description = "Instantly diagnoses and resets the ASUS Touchpad and I2C controllers."
        $Shortcut.Save()
        
        # Force the shortcut to run as Administrator by setting the 21st byte's 6th bit
        if (Test-Path $shortcutPath) {
            $bytes = [System.IO.File]::ReadAllBytes($shortcutPath)
            $bytes[21] = $bytes[21] -bor 0x20
            [System.IO.File]::WriteAllBytes($shortcutPath, $bytes)
        }
        
        Write-Log "Successfully created Start Menu shortcut 'Fix Touchpad'." "SUCCESS"
        Write-Log "You can now search for 'Fix Touchpad' in your Start Menu to reset the touchpad at any time." "SUCCESS"
    } catch {
        Write-Log "Failed to create Start Menu shortcut: $_" "ERROR"
        exit 1
    }
}

function Remove-StartMenuShortcut {
    Write-Log "Removing Start Menu shortcut..." "INFO"
    
    $startMenuPrograms = [System.IO.Path]::Combine($env:APPDATA, "Microsoft\Windows\Start Menu\Programs")
    $shortcutPath = [System.IO.Path]::Combine($startMenuPrograms, "Fix Touchpad.lnk")
    
    try {
        if (Test-Path $shortcutPath) {
            Remove-Item $shortcutPath -Force | Out-Null
            Write-Log "Successfully removed Start Menu shortcut 'Fix Touchpad'." "SUCCESS"
        } else {
            Write-Log "Start Menu shortcut 'Fix Touchpad' does not exist." "WARNING"
        }
    } catch {
        Write-Log "Failed to remove Start Menu shortcut: $_" "ERROR"
        exit 1
    }
}

function Register-CommandPath {
    $scriptDir = [System.IO.Path]::GetDirectoryName($PSCommandPath)
    Write-Log "Registering script directory in User PATH environment variable..." "INFO"
    Write-Log "Path: $scriptDir" "INFO"
    
    try {
        $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
        $paths = $currentPath -split ";" | Where-Object { $_ -ne "" }
        
        # Normalize paths to avoid slash and case mismatches
        $normalizedPaths = $paths | ForEach-Object { [System.IO.Path]::GetFullPath($_).TrimEnd([System.IO.Path]::DirectorySeparatorChar) }
        $normalizedScriptDir = [System.IO.Path]::GetFullPath($scriptDir).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
        
        if ($normalizedPaths -contains $normalizedScriptDir) {
            Write-Log "Directory is already registered in PATH." "SUCCESS"
            return
        }
        
        $newPath = ($paths + $scriptDir) -join ";"
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        
        Write-Log "Successfully added script directory to User PATH." "SUCCESS"
        Write-Log "Please OPEN A NEW terminal window for the global 'Fix-Touchpad' command to take effect." "SUCCESS"
    } catch {
        Write-Log "Failed to register PATH: $_" "ERROR"
        exit 1
    }
}

function Unregister-CommandPath {
    $scriptDir = [System.IO.Path]::GetDirectoryName($PSCommandPath)
    Write-Log "Removing script directory from User PATH environment variable..." "INFO"
    
    try {
        $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
        $paths = $currentPath -split ";" | Where-Object { $_ -ne "" }
        
        # Normalize paths for comparison
        $normalizedScriptDir = [System.IO.Path]::GetFullPath($scriptDir).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
        
        $newPaths = $paths | Where-Object { 
            [System.IO.Path]::GetFullPath($_).TrimEnd([System.IO.Path]::DirectorySeparatorChar) -ne $normalizedScriptDir 
        }
        
        if ($paths.Count -eq $newPaths.Count) {
            Write-Log "Directory is not registered in PATH." "WARNING"
            return
        }
        
        $newPath = $newPaths -join ";"
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        
        Write-Log "Successfully removed script directory from User PATH." "SUCCESS"
    } catch {
        Write-Log "Failed to unregister PATH: $_" "ERROR"
        exit 1
    }
}

# Main Execution Flow
if (-not $Silent) {
    Write-Host "ASUS Touchpad Fixer Utility" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host "===========================" -ForegroundColor White
}

# 1. Check Admin Elevation for Task Actions or Reset
$isAdmin = Test-IsAdmin

if ($Install -or $Uninstall -or $CreateShortcut -or $RemoveShortcut -or $RegisterPath -or $UnregisterPath) {
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
    }

    if ($Install) {
        Register-AutomationTask
    } elseif ($Uninstall) {
        Unregister-AutomationTask
    } elseif ($CreateShortcut) {
        New-StartMenuShortcut
    } elseif ($RemoveShortcut) {
        Remove-StartMenuShortcut
    } elseif ($RegisterPath) {
        Register-CommandPath
    } elseif ($UnregisterPath) {
        Unregister-CommandPath
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
