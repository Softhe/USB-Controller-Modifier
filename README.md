# USB-Controller-Modifier

Overview
This PowerShell script is designed to modify the behavior of USB controllers, specifically targeting the disabling of Interrupt Moderation (IMOD) for XHCI (USB 3.0) controllers and Interrupt Threshold Control for EHCI (USB 2.0) controllers. This can potentially improve USB performance by reducing latency at the cost of higher CPU usage.

Overview

This PowerShell script is designed to modify the behavior of USB controllers by disabling Interrupt Moderation (IMOD) for XHCI (eXtensible Host Controller Interface) or Interrupt Threshold Control for EHCI (Enhanced Host Controller Interface) USB controllers. The script can selectively apply these changes based on a configuration file specifying the device IDs of the USB controllers to be modified.
Features

    Administrator Check: Ensures the script is run with administrative privileges.
    Tool Viability Check: Verifies if the necessary kernel driver can be loaded, and if not, adjusts the system settings to disable Microsoft's Vulnerable Driver Blocklist.
    Logging: Logs detailed information about the process and results to log.txt.
    USB Controller Detection: Identifies all USB controllers on the system and filters them based on the configuration file.
    IMOD and Threshold Control Disabling: Modifies the specified USB controllers to disable Interrupt Moderation or Threshold Control.
    Utility Functions: Includes various utility functions for hex and binary conversions, memory reading, and configuration management.

Prerequisites

    Administrative Privileges: The script must be run as an administrator.
    PowerShell Execution Policy: Ensure the execution policy allows running unsigned scripts (-ExecutionPolicy Bypass).
    To be able to use this script/program you are required to turn off Memory Integrity & Disable Microsoft Vulnerable Driver Blocklist, in the downloaded .zip file i've included one script in a folder named "Disable Microsoft Vulnerable Driver Blocklist".
    You can use that script to turn off the security features in a quick easy way, run the "Disable Memory Integrity.cmd" as administrator and then restart your pc and then you should be able to use this script.

Configuration

    Configuration File (usb_controller_config.txt):
        This file should be located in the same directory as the script.
        Each line should contain a Device ID for a USB controller. Lines starting with # are treated as comments.
    Tool (KX.exe):
        The script expects KX.exe to be located either in the script's directory or the tools directory (C:\_\Programs\_exe\) for people that have my custom windows version.
        Adjust the $ToolsKX variable if the tool is stored in a different location (C:\_\Programs\_exe\) > (C:\MyFolder\).

Usage

    Run the Script:
        Navigate to the directory containing the script.
        Right-click on XHCI-IMOD-Disable.ps1 and select Run with powershell.
    Process:
        The script checks for tool viability.
        Reads the usb_controller_config.txt for specified USB controller Device IDs.
        Identifies and logs all USB controllers.
        Disables IMOD or Interrupt Threshold Control on the specified USB controllers.

Logging

    Logs are written to log.txt in the script's directory.
    Includes timestamps and detailed information about each step and action taken.

Notes

    Disabling Interrupt Moderation or Threshold Control may affect system performance and stability. Use with caution and at your own risk.
    The script modifies system registry settings to allow certain kernel drivers to function. Ensure you understand these changes before proceeding.
