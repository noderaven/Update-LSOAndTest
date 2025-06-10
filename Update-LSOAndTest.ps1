<#
MIT License

Copyright (c) 2025 noderaven

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

.SYNOPSIS
    Disables Large Send Offload (LSO) on active network adapters, tests connectivity,
    and attempts remediation steps if the network is down.

.DESCRIPTION
    This script performs a comprehensive check and remediation for network connectivity issues
    potentially caused by Large Send Offload (LSO) settings. It is designed for safe,
    non-interactive remote execution with detailed output by default.

    It gracefully handles differences between Windows PowerShell and PowerShell Core (6+)
    to ensure broad compatibility.

    1.  Ensures it is run with Administrator privileges.
    2.  Filters for physical network adapters that are currently 'Up'.
    3.  Disables LSO v2 for both IPv4 and IPv6 on these adapters.
    4.  If no changes are made, the script exits, assuming the network is healthy.
    5.  If a change was made, it waits and then tests internet connectivity.
    6.  If the test fails, it restarts the network adapters and tests again.
    7.  If the second test fails, it recommends a system restart. If the -ForceReboot
        switch is used, it will automatically restart the computer.

.PARAMETER PingTargets
    An array of IP addresses or hostnames to use for network connectivity tests.
    Defaults to Google's and Cloudflare's public DNS servers.

.PARAMETER InitialWaitSeconds
    The number of seconds to wait after disabling LSO before the first network test.
    Defaults to 45 seconds.

.PARAMETER ReinitializeWaitSeconds
    The number of seconds to wait after restarting adapters before the second network test.
    Defaults to 30 seconds.

.PARAMETER ForceReboot
    A switch parameter. If present, the script will force a computer restart if the
    second network connectivity test fails. Otherwise, it will only write a warning.

.EXAMPLE
    PS C:\> .\Update-LSOAndTest.ps1
    Executes the script with detailed output.

.EXAMPLE
    PS C:\> .\Update-LSOAndTest.ps1 -ForceReboot
    Executes the script and will force a restart if network remediation fails. This is non-interactive.
#>

#requires -RunAsAdministrator
#requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string[]]$PingTargets = @('8.8.8.8', '1.1.1.1'),
    [int]$InitialWaitSeconds = 45,
    [int]$ReinitializeWaitSeconds = 30,
    [switch]$ForceReboot
)

# --- Helper Functions ---

function Set-LSOState {
    <#
    .SYNOPSIS
        A helper function to enable or disable a specific LSO property on an adapter.
    .DESCRIPTION
        This function encapsulates the logic for getting and setting an advanced property
        on a network adapter, reducing code duplication.
    .OUTPUTS
        [boolean] Returns $true if a change was made, $false otherwise.
    #>
    [CmdletBinding()]
    [OutputType([boolean])]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Adapter,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName,

        [Parameter(Mandatory = $true)]
        [string]$PropertyValue
    )

    Write-Host "Processing property '$($PropertyName)' for adapter '$($Adapter.Name)'"
    
    $getParams = @{ Name = $Adapter.Name; DisplayName = $PropertyName; ErrorAction = 'SilentlyContinue' }
    $advancedProperty = Get-NetAdapterAdvancedProperty @getParams

    if ($null -ne $advancedProperty) {
        if ($advancedProperty.DisplayValue -eq $PropertyValue) {
            Write-Host "[$($Adapter.Name)] '$($PropertyName)' is already set to '$($PropertyValue)'."
            return $false # No change made
        }

        try {
            $setParams = @{
                Name          = $Adapter.Name
                DisplayName   = $PropertyName
                DisplayValue  = $PropertyValue
                ErrorAction   = 'Stop'
                Confirm       = $false
            }
            
            if ($PSCmdlet.ShouldProcess("adapter '$($Adapter.Name)'", "Set advanced property '$($PropertyName)' to '$($PropertyValue)'")) {
                 Set-NetAdapterAdvancedProperty @setParams
                 Write-Host "[$($Adapter.Name)] Successfully set '$($PropertyName)' to '$($PropertyValue)'."
                 return $true # Change was made
            }
        }
        catch {
            Write-Warning "[$($Adapter.Name)] Failed to set '$($PropertyName)'. Error: $_"
        }
    }
    else {
        Write-Host "[$($Adapter.Name)] Advanced property '$($PropertyName)' not found. Skipping."
    }

    # Default return if no other path was taken (e.g., property not found, error, -WhatIf)
    return $false
}

function Test-RobustNetworkConnection {
    <#
    .SYNOPSIS
        Tests network connectivity by pinging one or more targets.
    .DESCRIPTION
        Uses Test-Connection, the PowerShell-native way to ping. It is more robust
        as it will return $true if ANY of the targets respond successfully.
        It automatically uses the correct parameter name (-ComputerName or -TargetName)
        based on the running PowerShell version.
    #>
    [CmdletBinding()]
    [OutputType([boolean])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Targets
    )

    foreach ($target in $Targets) {
        Write-Host "Pinging $target..."
        
        # Use a splatting table to hold the parameters for Test-Connection
        $testConnectionParams = @{
            Count       = 1
            ErrorAction = 'SilentlyContinue'
            Quiet       = $true
        }

        # Add the correct parameter name based on the PowerShell version.
        # Windows PowerShell (e.g., v5.1) uses -ComputerName.
        # PowerShell Core (v6+) uses -TargetName.
        if ($PSVersionTable.PSVersion.Major -lt 6) {
            $testConnectionParams['ComputerName'] = $target
        }
        else {
            $testConnectionParams['TargetName'] = $target
        }
        
        if (Test-Connection @testConnectionParams) {
            Write-Host "Ping to $target was successful."
            return $true
        }
        Write-Host "Ping to $target failed."
    }

    return $false
}


# --- Main Script Logic ---

Write-Host "Searching for active, physical network adapters..."
$adapters = Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' }

if ($null -eq $adapters) {
    Write-Warning "No active, physical network adapters found. Exiting script."
    exit 1
}

Write-Host "Found $($adapters.Count) active adapter(s): $($adapters.Name -join ', ')"

$anyChangesMade = $false
foreach ($adapter in $adapters) {
    if (Set-LSOState -Adapter $adapter -PropertyName "Large Send Offload V2 (IPv4)" -PropertyValue "Disabled") {
        $anyChangesMade = $true
    }
    if (Set-LSOState -Adapter $adapter -PropertyName "Large Send Offload V2 (IPv6)" -PropertyValue "Disabled") {
        $anyChangesMade = $true
    }
}

# --- Conditional Logic based on changes ---
if (-not $anyChangesMade) {
    Write-Host "No LSO changes were necessary. Assuming network is in a healthy state. Exiting."
    exit 0
}

# --- Proceed with testing only if changes were made ---
Write-Host "Waiting for $InitialWaitSeconds seconds for network to stabilize after changes..."
Start-Sleep -Seconds $InitialWaitSeconds

Write-Host "Performing first network connection test..."
if (Test-RobustNetworkConnection -Targets $PingTargets) {
    Write-Host "Network connection is ACTIVE. Script finished successfully."
    exit 0
}

# --- Remediation Steps ---

Write-Warning "First network test FAILED. Attempting to restart network adapters."

foreach ($adapter in $adapters) {
    try {
        if ($PSCmdlet.ShouldProcess($adapter.Name, "Restart-NetAdapter")) {
            Restart-NetAdapter -Name $adapter.Name -ErrorAction Stop -Confirm:$false
            Write-Host "Successfully restarted adapter: $($adapter.Name)"
        }
    }
    catch {
        Write-Warning "Failed to restart adapter '$($adapter.Name)'. Error: $_"
    }
}

Write-Host "Waiting $ReinitializeWaitSeconds seconds for adapters to reinitialize."
Start-Sleep -Seconds $ReinitializeWaitSeconds

Write-Host "Performing second network connection test..."
if (Test-RobustNetworkConnection -Targets $PingTargets) {
    Write-Host "Network connection is ACTIVE after restarting adapters. Script finished successfully."
    exit 0
}

# --- Final Step ---

Write-Warning "Second network test FAILED. Further manual intervention may be required."
if ($ForceReboot) {
    if ($PSCmdlet.ShouldProcess("the local computer", "Restart-Computer -Force")) {
        Write-Warning "Restarting the computer in 10 seconds due to -ForceReboot switch..."
        Start-Sleep -Seconds 10
        Restart-Computer -Force
    }
}
else {
    Write-Host "To automatically restart, run this script again with the -ForceReboot switch."
}
