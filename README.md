# Touchpad Fixer (ASUS Vivobook/Zenbook)

A lightweight PowerShell utility to diagnose, automatically reset, and permanently fix the recurring ASUS touchpad `I2C HID Device Code 10` error ("This device cannot start") on sleep/wake transitions.

## The Troubleshooting Journey

### 1. The Problem Faced
On ASUS Vivobook and Zenbook laptops (specifically models like the Vivobook S14 OLED), waking the laptop from sleep, hibernation, or modern standby occasionally causes the touchpad to completely stop responding. 
In Windows Device Manager, the **I2C HID Device** shows a yellow warning triangle with the error:
> *This device cannot start. (Code 10)*
> *A request for the HID descriptor failed.*

### 2. HW vs. SW Diagnosis: How it was identified as a Software Issue
Before attempting to fix it, it was critical to determine if this was a physical hardware failure (e.g., a loose ribbon cable or a faulty touchpad sensor) or a software driver/ACPI issue:
- **Explicit Driver Failure**: Windows Device Manager explicitly flagged the driver with a yellow warning triangle (`Code 10`), indicating that the OS kernel itself was actively refusing to start the driver due to a failed handshake, rather than the device physically disappearing from the PCI/ACPI bus.
- **One-way Hardware Key Lockup**: Pressing the touchpad toggle hotkey (typically **F6** or **Fn+F9**) could disable the touchpad, but would completely fail to enable it back. This proved that the underlying driver software was in a hung state and unresponsive to OS-level inputs.
- **No Physical Intermittency**: The touchpad never cut out during active typing, moving the laptop, or adjusting the screen angle (which is typical for loose hardware cables). It only failed *precisely* when transitioning system power states (resuming from Sleep/Modern Standby or a hybrid shutdown).
- **100% Software Recovery**: Uninstalling the device in Device Manager and rebooting the laptop restored touchpad functionality without fail, proving the physical hardware module was fully operational and the issue was entirely state-based.
- **Protocol Failure (Descriptor Timeout)**: The `Code 10: HID descriptor failed` error indicated a low-level protocol mismatch where the Windows driver timed out waiting for the device to send its configuration descriptors on wakeup. 

### 3. The Temporary Fix
The initial workaround was to manually open Device Manager, right-click and uninstall the `I2C HID Device`, and reboot the PC. While effective, it was highly disruptive, requiring all work to be saved and interrupting active tasks.

### 4. The Permanent Solution (Zero-Reboot Automation)
To solve this permanently without reboots, we engineered a script that targets the root cause—the system power state of the I2C bus:
- **Deep Coordinated Bus Power Cycle**: Instead of restarting the computer, the script disables the touchpad, the `Intel Serial IO I2C Host Controllers`, and the `Intel Serial IO GPIO Host Controller` (which manages the touchpad's physical power and interrupt lines). It waits 3 seconds to fully discharge any residual voltage, and then enables them in the correct physical dependency sequence (GPIO -> I2C -> Touchpad). This forces the physical I2C bus to re-negotiate the handshake, instantly clearing the Code 10 error.
- **Event-Driven Automation**: The script installs a Windows Scheduled Task running under `HighestAvailable` (SYSTEM) privileges that triggers automatically on Windows event logs:
  - User Logon
  - System Wake-from-sleep (`Kernel-Power` Event ID 107)
  - System Exit from Modern Standby (`Kernel-Power` Event ID 507)
  - General Resume (`Power-Troubleshooter` Event ID 1)

This results in a completely hands-off solution: the moment your laptop wakes up, the script runs in the background and resolves the issue before you even place your hand on the trackpad.

---

## Features
- **Fast Diagnostics**: Instantly check if the I2C HID Device is in an error state.
- **Deep Bus Reset Logic**: Performs a coordinated power cycle of the GPIO and I2C controllers.
- **Admin Elevation**: Prompts for UAC automatically if run manually.
- **Silently Automated**: Windows Scheduled Task is configured to run silently in the background, bypasses default battery constraints, and completes in ~5 seconds.
- **Windows Toast Notifications**: Pushes a native toast notification indicating successful recovery.

---

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
- `-Install`: Installs the Windows Scheduled Task.
- `-Uninstall`: Removes the Windows Scheduled Task.

## Uninstallation
To remove the background task, run:
```powershell
.\Fix-Touchpad.ps1 -Uninstall
```
