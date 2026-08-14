# Touchpad Fixer (ASUS Vivobook/Zenbook)

A lightweight PowerShell utility to diagnose, automatically reset, and permanently fix the recurring ASUS touchpad `I2C HID Device Code 10` error ("This device cannot start").

## The Problem
ASUS Vivobook and Zenbook laptops (such as the Vivobook S14 OLED) often suffer from a recurring touchpad failure after waking up from sleep or during hybrid boot. In Device Manager, the **I2C HID Device** shows a yellow triangle with **Code 10 (A request for the HID descriptor failed)**.

Instead of restarting the PC to temporarily resolve the issue, this utility power-cycles the parent I2C Host Controller, resetting the bus and restoring the touchpad in under 3 seconds without a reboot.

## Features
- **Fast Diagnostics**: Instantly check if the I2C HID Device is in an error state.
- **Layered Bus Reset Logic**:
  1. Toggles (disables/enables) the `I2C HID Device` itself.
  2. If that fails, power-cycles the Intel/AMD Serial IO I2C Host Controllers.
  3. If still unsuccessful, uninstalls the touchpad and triggers a hardware scan (equivalent to your manual Device Manager fix).
- **Admin Elevation**: Prompts for UAC automatically if needed to perform device management commands.
- **Automated Fix (Scheduled Task)**: Installs a task that runs silently in the background whenever the computer wakes up from sleep/hibernation or on system login. Runs on battery power too!
- **Windows Toast Notifications**: Displays a native system notification when the touchpad is successfully recovered.

## Installation & Setup

1. Open PowerShell as **Administrator** and navigate to this folder.
2. Run the following command to register the automatic background fixer:
   ```powershell
   .\Fix-Touchpad.ps1 -Install
   ```
3. (Optional) Run the script manually to diagnose or force a reset at any time:
   ```powershell
   # Standard diagnostic run (only resets if error is detected)
   .\Fix-Touchpad.ps1

   # Force reset regardless of current detected status
   .\Fix-Touchpad.ps1 -Force
   ```

## Command Line Parameters
- `-Force`: Resets the touchpad and I2C controllers even if diagnostics report that the touchpad is working normally.
- `-Silent`: Suppresses console window logs (used by the automation background task).
- `-LogFile <Path>`: Logs actions to a text file (defaults to `C:\ProgramData\TouchpadFixer\touchpad-fixer.log`).
- `-Install`: Installs the Windows Scheduled Task to run this script automatically on login and sleep wakeups.
- `-Uninstall`: Removes the Windows Scheduled Task.

## Uninstallation
To remove the background task, run:
```powershell
.\Fix-Touchpad.ps1 -Uninstall
```
