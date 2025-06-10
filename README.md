# Update-LSOAndTest

A PowerShell script to disable Large Send Offload (LSO) on active network adapters, test connectivity, and attempt remediation if the network is down.

## Overview

This script addresses network connectivity issues potentially caused by Large Send Offload (LSO) settings. It is designed for safe, non-interactive remote execution with detailed output, compatible with both Windows PowerShell and PowerShell Core (6+).

### Key Features
- Ensures execution with Administrator privileges.
- Targets physical network adapters with 'Up' status.
- Disables LSO v2 for IPv4 and IPv6.
- Exits if no changes are needed, assuming a healthy network.
- Tests connectivity after changes, with remediation steps (adapter restart, optional system reboot) if tests fail.

## Requirements
- PowerShell 5.1 or later
- Administrator privileges (`#requires -RunAsAdministrator`)

## Installation
1. Clone or download this repository:
   ```bash
   git clone https://github.com/your-username/Update-LSOAndTest.git
   ```
Navigate to the script directory:cd Update-LSOAndTest



## Usage
Run the script in an elevated PowerShell session.
Basic Execution
``` PowerShell
.\Update-LSOAndTest.ps1
```

Executes with default settings, providing detailed output.
Force Reboot on Failure
``` PowerShell
.\Update-LSOAndTest.ps1 -ForceReboot
```

Automatically restarts the computer if network remediation fails.
Parameters

-PingTargets <String[]>: IP addresses or hostnames for connectivity tests (default: 8.8.8.8, 1.1.1.1).
-InitialWaitSeconds <Int>: Seconds to wait after disabling LSO before testing (default: 45).
-ReinitializeWaitSeconds <Int>: Seconds to wait after restarting adapters (default: 30).
-ForceReboot: Forces a system restart if the second connectivity test fails.

## Script Workflow
```
Check Privileges: Ensures Administrator rights.
Find Adapters: Filters for active, physical network adapters.
Disable LSO: Sets LSO v2 (IPv4/IPv6) to 'Disabled' on each adapter.
Exit if No Changes: If LSO settings are already correct, the script exits.
Test Connectivity: After a delay, pings specified targets.
Remediation:
If the first test fails, restarts adapters and tests again.
If the second test fails, recommends a reboot (or forces it with -ForceReboot).
```


## Example Output
```
Searching for active, physical network adapters...
Found 1 active adapter(s): Ethernet
Processing property 'Large Send Offload V2 (IPv4)' for adapter 'Ethernet'
[Ethernet] Successfully set 'Large Send Offload V2 (IPv4)' to 'Disabled'.
Waiting for 45 seconds for network to stabilize after changes...
Performing first network connection test...
Pinging 8.8.8.8...
Ping to 8.8.8.8 was successful.
Network connection is ACTIVE. Script finished successfully.
```

## Notes

Author: Gemini
Date: 2025-06-09
Based on: Original script by Riley
The script uses Test-Connection for robust ping tests, adapting to PowerShell version differences (-ComputerName for 5.1, -TargetName for 6+).
Use -WhatIf to simulate actions without making changes.

## Contributing

Fork the repository.
Create a feature branch (git checkout -b feature/YourFeature).
Commit changes (git commit -m 'Add YourFeature').
Push to the branch (git push origin feature/YourFeature).
Open a Pull Request.

## License
This project is licensed under the MIT License - see the LICENSE file for details.```
