# Touchpad Fixer (ASUS Vivobook/Zenbook)

A lightweight PowerShell utility to diagnose, automatically reset, and permanently fix the recurring ASUS touchpad `I2C HID Device Code 10` error ("This device cannot start").

## The Problem
ASUS Vivobook and Zenbook laptops (such as the Vivobook S14 OLED) often suffer from a recurring touchpad failure after waking up from sleep or during hybrid boot. In Device Manager, the **I2C HID Device** shows a yellow triangle with **Code 10 (A request for the HID descriptor failed)**.

Instead of restarting the PC to temporarily resolve the issue, this utility power-cycles the parent I2C Host Controller, resetting the bus and restoring the touchpad in under 3 seconds without a reboot.

## Features
- **Fast Diagnostics**: Instantly check if the I2C HID Device is in an error state.
- **Bus Power Cycle**: Restarts the Intel/AMD Serial IO I2C Host Controller, forcing the I2C bus to reinitialize.
- **Admin Elevation**: Prompts for UAC automatically if needed to perform device management commands.
- **Automated Fix (Scheduled Task)**: Auto-runs in the background whenever the computer wakes up from sleep/hibernation or on system login.

## Usage
*Instructions will be updated as scripts are developed.*
