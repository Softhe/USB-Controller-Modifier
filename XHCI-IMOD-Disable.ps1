<#
Script: USB Controller Modifier
Author: Softhe
#>

# Start as administrator
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs; exit
}

# Change the folder location in the last part of the following line if you wish to have the KX.exe in a diffrent location
$ToolsKX = "$(Split-Path -Path $PSScriptRoot -Parent)\C:\_\Programs\_exe\KX.exe"
$LocalKX = "$PSScriptRoot\KX.exe"

function Log-Output {
    param([string]$message)
    $logPath = "$PSScriptRoot\log.txt"
    # Write to log file
    "$([DateTime]::Now) - $message" | Out-File -Append -FilePath $logPath
    # Write to console
    Write-Host $message
}

function KX-Exists {
    $ToolsKXExists = Test-Path -Path $ToolsKX -PathType Leaf
    $LocalKXExists = Test-Path -Path $LocalKX -PathType Leaf
    return @{LocalKXExists = $LocalKXExists; ToolsKXExists = $ToolsKXExists}
}

function Get-KX {
    $KXExists = KX-Exists
    if ($KXExists.ToolsKXExists) { return $ToolsKX } else { return $LocalKX }
}

function Check-For-Tool-Viability {
    $Value = & "$(Get-KX)" /RdMem32 "0x0"
    if ($Value -match 'Kernel Driver can not be loaded') {
        New-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\CI\Config\" -Name VulnerableDriverBlocklistEnable -PropertyType Dword -Value 0 -Force | Out-Null
        Log-Output "Kernel Driver can not be loaded. A certificate was explicitly revoked by its issuer."
        Log-Output "In some cases, you might need to disable Microsoft Vulnerable Driver Blocklist for the tool to work."
        Log-Output "It will be done automatically, but it can also be done through the UI, in the Core Isolation section. If it doesn't work immediately, it may require a restart."
        Log-Output "If you are getting this message, it means you need to do this, otherwise you cannot run any type of tool that does this kind of change. Therefore, doing this would not be possible if you undo this change; the next reboot, it would stop working again. Enable or Disable at your own risk."
        exit 0
    }
}

function Get-Config {
    $configFilePath = Join-Path -Path $PSScriptRoot -ChildPath "usb_controller_config.txt"
    if (Test-Path -Path $configFilePath) {
        return Get-Content -Path $configFilePath | Where-Object { $_ -notmatch '^\s*#' -and $_ -notmatch '^\s*$' }
    } else {
        Log-Output "Configuration file not found. Please create 'usb_controller_config.txt' with Device IDs."
        exit 1
    }
}

function Get-All-USB-Controllers {
    [PsObject[]]$USBControllers = @()

    $allUSBControllers = Get-CimInstance -ClassName Win32_USBController | Select-Object -Property Name, DeviceID
    foreach ($usbController in $allUSBControllers) {
        $allocatedResource = Get-CimInstance -ClassName Win32_PNPAllocatedResource | Where-Object { $_.Dependent.DeviceID -like "*$($usbController.DeviceID)*" } | Select @{N="StartingAddress";E={$_.Antecedent.StartingAddress}}
        $deviceMemory = Get-CimInstance -ClassName Win32_DeviceMemoryAddress | Where-Object { $_.StartingAddress -eq "$($allocatedResource.StartingAddress)" }

        $deviceProperties = Get-PnpDeviceProperty -InstanceId $usbController.DeviceID
        $locationInfo = $deviceProperties | Where KeyName -eq 'DEVPKEY_Device_LocationInfo' | Select -ExpandProperty Data
        $PDOName = $deviceProperties | Where KeyName -eq 'DEVPKEY_Device_PDOName' | Select -ExpandProperty Data

        $moreControllerData = Get-CimInstance -ClassName Win32_PnPEntity | Where-Object { $_.DeviceID -eq "$($usbController.DeviceID)" } | Select-Object Service
        $Type = if ($moreControllerData.Service -ieq 'USBXHCI') {'XHCI'} elseif ($moreControllerData.Service -ieq 'USBEHCI') {'EHCI'} else {'Unknown'}

        if ([string]::IsNullOrWhiteSpace($deviceMemory.Name)) {
            continue
        }

        $USBControllers += [PsObject]@{
            Name = $usbController.Name
            DeviceId = $usbController.DeviceID
            MemoryRange = $deviceMemory.Name
            LocationInfo = $locationInfo
            PDOName = $PDOName
            Type = $Type
        }
    }
    return $USBControllers
}

function Get-Type-From-Service {
    param ([string] $value)
    if ($value -ieq 'USBXHCI') {
        return 'XHCI'
    }
    if ($value -ieq 'USBEHCI') {
        return 'EHCI'
    }
    return 'Unknown'
}

function Convert-Decimal-To-Hex {
    param ([int64] $value)
    if ([string]::IsNullOrWhiteSpace($value)) { $value = "0" }
    return '0x' + [System.Convert]::ToString($value, 16).ToUpper()
}

function Convert-Hex-To-Decimal {
    param ([string] $value)
    if ([string]::IsNullOrWhiteSpace($value)) { $value = "0x0" }
    return [convert]::ToInt64($value, 16)
}

function Convert-Hex-To-Binary {
    param ([string] $value)
    $ConvertedValue = [Convert]::ToString($value, 2)
    return $ConvertedValue.PadLeft(32, '0')
}

function Convert-Binary-To-Hex {
    param ([string] $value)
    $convertedValue = [Convert]::ToInt64($value, 2)
    return Convert-Decimal-To-Hex -value $convertedValue
}

function Get-Hex-Value-From-Tool-Result {
    param ([string] $value)
    return $value.Split(" ")[19].Trim()
}

function Get-R32-Hex-From-Address {
    param ([string] $address)
    $Value = & "$(Get-KX)" /RdMem32 $address
    while ([string]::IsNullOrWhiteSpace($Value)) { Start-Sleep -Seconds 1 }
    return Get-Hex-Value-From-Tool-Result -value $Value
}

function Get-Left-Side-From-MemoryRange {
    param ([string] $memoryRange)
    return $memoryRange.Split("-")[0]
}

function Get-BitRange-From-Binary {
    param ([string] $binaryValue, [int] $from, [int] $to)
    $backwardsFrom = $to
    $backwardsTo = $from
    return $binaryValue.SubString($binaryValue.Length - $backwardsFrom, $backwardsFrom - $backwardsTo)
}

function Find-First-Interrupter-Data {
    param ([string] $memoryRange)
    $LeftSideMemoryRange = Get-Left-Side-From-MemoryRange -memoryRange $memoryRange
    $CapabilityBaseAddressInDecimal = Convert-Hex-To-Decimal -value $LeftSideMemoryRange
    $RuntimeRegisterSpaceOffsetInDecimal = Convert-Hex-To-Decimal -value "0x18"
    $SumCapabilityPlusRuntime = Convert-Decimal-To-Hex -value ($CapabilityBaseAddressInDecimal + $RuntimeRegisterSpaceOffsetInDecimal)
    $Value = Get-R32-Hex-From-Address -address $SumCapabilityPlusRuntime
    $ValueInDecimal = Convert-Hex-To-Decimal -value $Value
    $TwentyFourInDecimal = Convert-Hex-To-Decimal -value "0x24"
    $Interrupter0PreAddressInDecimal = $CapabilityBaseAddressInDecimal + $ValueInDecimal + $TwentyFourInDecimal

    $FourInDecimal = Convert-Hex-To-Decimal -value "0x4"
    $HCSPARAMS1InHex = Convert-Decimal-To-Hex -value ($CapabilityBaseAddressInDecimal + $FourInDecimal)

    return @{ Interrupter0PreAddressInDecimal = $Interrupter0PreAddressInDecimal; HCSPARAMS1 = $HCSPARAMS1InHex }
}

function Build-Interrupt-Threshold-Control-Data {
    param ([string] $memoryRange)
    $LeftSideMemoryRange = Get-Left-Side-From-MemoryRange -memoryRange $memoryRange
    $LeftSideMemoryRangeInDecimal = Convert-Hex-To-Decimal -value $LeftSideMemoryRange
    $TwentyInDecimal = Convert-Hex-To-Decimal -value "0x20"
    $MemoryBase = Convert-Decimal-To-Hex -value ($LeftSideMemoryRangeInDecimal + $TwentyInDecimal)
    $MemoryBaseValue = Get-R32-Hex-From-Address -address $MemoryBase
    $ValueInBinary = Convert-Hex-To-Binary -value $MemoryBaseValue
    $ReplaceValue = '00000000'
    $BackwardsFrom = 16
    $BackwardsTo = 23
    $ValueInBinaryLeftSide = $ValueInBinary.Substring(0, $ValueInBinary.Length - $BackwardsTo)
    $ValueInBinaryRightSide = $ValueInBinary.Substring($ValueInBinary.Length - $BackwardsTo + $ReplaceValue.Length, ($ValueInBinary.Length - 1) - $BackwardsFrom)
    $ValueAddress = Convert-Binary-To-Hex -value ($ValueInBinaryLeftSide + $ReplaceValue + $ValueInBinaryRightSide)
    return [PsObject]@{ValueAddress = $ValueAddress; InterruptAddress = $MemoryBase}
}

function Find-Interrupters-Amount {
    param ([string] $hcsParams1)
    $Value = Get-R32-Hex-From-Address -address $hcsParams1
    $ValueInBinary = Convert-Hex-To-Binary -value $Value
    $MaxIntrsInBinary = Get-BitRange-From-Binary -binaryValue $ValueInBinary -from 8 -to 18
    $InterruptersAmount = Convert-Hex-To-Decimal -value (Convert-Binary-To-Hex -value $MaxIntrsInBinary)
    return $InterruptersAmount
}

function Disable-IMOD {
    param ([string] $address, [string] $value)
    $ValueData = "0x00000000"
    if (![string]::IsNullOrWhiteSpace($value)) { $ValueData = $value }
    $Value = & "$(Get-KX)" /WrMem32 $address $ValueData
    while ([string]::IsNullOrWhiteSpace($Value)) { Start-Sleep -Seconds 1 }
    return $Value
}

function Get-All-Interrupters {
    param ([int64] $preAddressInDecimal, [int32] $interruptersAmount)
    [PsObject[]]$Data = @()
    if ($interruptersAmount -lt 1 -or $interruptersAmount -gt 1024) {
        Log-Output "Device interrupters amount is different than specified MIN (1) and MAX (1024) - FOUND $interruptersAmount - No address from this device will be IMOD disabled"
        return $Data
    }
    for ($i=0; $i -lt $interruptersAmount; $i++) {
        $AddressInDecimal = $preAddressInDecimal + (32 * $i)
        $InterrupterAddress = Convert-Decimal-To-Hex -value $AddressInDecimal
        $Address = Get-R32-Hex-From-Address -address $InterrupterAddress
        $Data += [PsObject]@{ValueAddress = $Address; InterrupterAddress = $InterrupterAddress; Interrupter = $i}
    }
    return $Data
}

function Execute-IMOD-Process {
    Log-Output "Started disabling Interrupt Moderation (XHCI) or Interrupt Threshold Control (EHCI) in USB controllers"

    # Get all USB controllers
    $USBControllers = Get-All-USB-Controllers
    Log-Output "Retrieved $($USBControllers.Length) USB controllers."

    if ($USBControllers.Length -eq 0) {
        Log-Output "Script didn't find any valid USB controllers to disable. Please check your system."
        return
    } else {
        Log-Output "Available USB Controllers:"
        $USBControllers | ForEach-Object { 
            Log-Output "$($_.Name) - Type: $($_.Type) - Device ID: $($_.DeviceId)" 
        }
    }

    # Check for configuration file
    $configuredDeviceIds = Get-Config

    # Filter USB controllers based on the config file
    $USBControllers = $USBControllers | Where-Object { $configuredDeviceIds -contains $_.DeviceId }

    if ($USBControllers.Length -eq 0) {
        Log-Output "No USB controllers match the configured Device IDs."
        return
    }

    Log-Output "Processing $($USBControllers.Length) controllers based on configuration."

    # Process the selected controllers (or all if none selected)
    foreach ($item in $USBControllers) {
        $InterruptersAmount = 'None'

        if ($item.Type -eq 'XHCI') {
            Log-Output "Processing XHCI controller: $($item.Name) - Device ID: $($item.DeviceId)"

            # Fetch the interrupter data and disable IMOD
            $FirstInterrupterData = Find-First-Interrupter-Data -memoryRange $item.MemoryRange
            $InterruptersAmount = Find-Interrupters-Amount -hcsParams1 $FirstInterrupterData.HCSPARAMS1
            $AllInterrupters = Get-All-Interrupters -preAddressInDecimal $FirstInterrupterData.Interrupter0PreAddressInDecimal -interruptersAmount $InterruptersAmount

            foreach ($interrupterItem in $AllInterrupters) {
                $DisableResult = Disable-IMOD -address $interrupterItem.InterrupterAddress
                Log-Output "Disabled IMOD - Interrupter $($interrupterItem.Interrupter) - Interrupter Address: $($interrupterItem.InterrupterAddress) - Value Address: $($interrupterItem.ValueAddress) - Result: $DisableResult"
            }
        }

        if ($item.Type -eq 'EHCI') {
            Log-Output "Processing EHCI controller: $($item.Name) - Device ID: $($item.DeviceId)"
            # For EHCI, build interrupt threshold control data
            $InterruptData = Build-Interrupt-Threshold-Control-Data -memoryRange $item.MemoryRange
            $DisableResult = Disable-IMOD -address $InterruptData.InterruptAddress -value $InterruptData.ValueAddress
            Log-Output "Disabled Interrupt Threshold Control - Interrupt Address: $($InterruptData.InterruptAddress) - Value Address: $($InterruptData.ValueAddress) - Result: $DisableResult"
        }

        Log-Output "Device Details:"
        Log-Output " - Name: $($item.Name)"
        Log-Output " - Device ID: $($item.DeviceId)"
        Log-Output " - Location Info: $($item.LocationInfo)"
        Log-Output " - PDO Name: $($item.PDOName)"
        Log-Output " - Device Type: $($item.Type)"
        Log-Output " - Memory Range: $($item.MemoryRange)"
        Log-Output " - Interrupters Count: $InterruptersAmount"
        Log-Output "------------------------------------------------------------------"
    }
}

# --------------------------------------------------------------------------------------------

Check-For-Tool-Viability

Execute-IMOD-Process
