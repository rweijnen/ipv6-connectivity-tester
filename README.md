# IPv6 Connectivity Tester

A PowerShell script that tests IPv6 connectivity on Windows interfaces and optionally removes failed addresses. The script uses parallel testing for improved performance and provides detailed diagnostics for address removal.

## Features

- **Parallel Testing**: Tests all IPv6 addresses simultaneously using PowerShell background jobs
- **Address Removal**: Automatically removes IPv6 addresses that fail connectivity tests
- **Route Management**: Identifies and reports routes associated with failed addresses
- **Detailed Diagnostics**: Shows address origin, state, type, and interface information
- **Multiple Removal Methods**: Uses PowerShell cmdlets, netsh, and privacy extension cycling
- **Safety Checks**: Confirmation prompts and verification of address removal

## Requirements

- Windows 10/11 or Windows Server 2016+
- PowerShell 5.1 or later
- Administrator privileges (required for address removal)
- IPv6-enabled network interface

## Usage

### Basic Testing
```powershell
.\test-ipv6-connectivity.ps1
```

### Test with Address Removal
```powershell
.\test-ipv6-connectivity.ps1 -RemoveFailedAddresses
```

### Test with Route Analysis
```powershell
.\test-ipv6-connectivity.ps1 -RemoveFailedRoutes
```

### Full Cleanup (No Confirmation)
```powershell
.\test-ipv6-connectivity.ps1 -RemoveFailedAddresses -RemoveFailedRoutes -Force
```

### Custom Interface and Target
```powershell
.\test-ipv6-connectivity.ps1 -InterfaceName "Wi-Fi" -TestTarget "cloudflare.com"
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `InterfaceName` | String | "Ethernet 2" | Network interface to test |
| `TestTarget` | String | "google.com" | Target hostname for connectivity tests |
| `RemoveFailedAddresses` | Switch | False | Remove IPv6 addresses that fail connectivity |
| `RemoveFailedRoutes` | Switch | False | Find and report routes for failed addresses |
| `Force` | Switch | False | Skip confirmation prompts |

## How It Works

### 1. Address Discovery
The script uses `netsh interface ipv6 show address` to enumerate IPv6 addresses on the specified interface. It filters out:
- Link-local addresses (fe80::)
- Loopback addresses (::1)

### 2. Parallel Connectivity Testing
For each discovered address, the script:
1. Creates a PowerShell background job
2. Executes `ping -6 -S <address> -n 3 <target>`
3. Collects results from all jobs simultaneously
4. Reports success/failure with statistics

### 3. Address Analysis
For failed addresses, the script analyzes:
- **PrefixOrigin**: How the prefix was obtained (RouterAdvertisement, Manual, etc.)
- **SuffixOrigin**: How the suffix was generated (Link, Random, Manual, etc.)
- **AddressState**: Current state (Preferred, Deprecated, etc.)
- **Interface**: Which network interface owns the address

### 4. Address Removal Process
The script attempts removal using multiple methods:

#### Method 1: PowerShell Cmdlet
```powershell
Remove-NetIPAddress -IPAddress <address> -Confirm:$false
```
This is the most reliable method for autoconfigured addresses.

#### Method 2: netsh Command
```powershell
netsh interface ipv6 delete address interface="<interface>" address="<address>"
```
Fallback method when PowerShell cmdlets fail.

#### Method 3: Privacy Extension Cycling
For addresses with `SuffixOrigin = Random` (privacy extensions):
```powershell
netsh interface ipv6 set privacy state=disabled
# Wait 2 seconds
netsh interface ipv6 set privacy state=enabled
```
This forces regeneration of privacy extension addresses.

### 5. Verification
After removal attempts, the script:
1. Waits 1 second for changes to propagate
2. Attempts to query the removed address
3. Confirms successful removal or reports warnings

## Output Example

```
Testing IPv6 connectivity for interface: Ethernet 2
Target: google.com

Found IPv6 addresses:
  2a02:a46f:a6da:1:3e3:212d:1f0d:715a
  2a02:a46f:a6da:1:846a:8045:fe01:4c88
  2a02:a46f:a6da:2:4389:1e44:8020:1b4e
  2a02:a46f:a6da:2:9953:2f80:6c45:9861

Starting parallel connectivity tests...
  Started test for 2a02:a46f:a6da:1:3e3:212d:1f0d:715a
  Started test for 2a02:a46f:a6da:1:846a:8045:fe01:4c88
  Started test for 2a02:a46f:a6da:2:4389:1e44:8020:1b4e
  Started test for 2a02:a46f:a6da:2:9953:2f80:6c45:9861

Waiting for all tests to complete...
Collecting results for 2a02:a46f:a6da:1:3e3:212d:1f0d:715a...
  SUCCESS: Ping from 2a02:a46f:a6da:1:3e3:212d:1f0d:715a to google.com successful

Collecting results for 2a02:a46f:a6da:2:4389:1e44:8020:1b4e...
  FAILED: Ping from 2a02:a46f:a6da:2:4389:1e44:8020:1b4e to google.com failed

Summary:
  Total IPv6 addresses tested: 4
  Successful connections: 2
  Failed connections: 2

Processing failed address: 2a02:a46f:a6da:2:4389:1e44:8020:1b4e
  Analyzing address details...
    Origin: RouterAdvertisement/Link
    State: Preferred
    Type: Unicast
    Interface: Ethernet 2
  Attempting address removal...
    SUCCESS: Removed using Remove-NetIPAddress
    CONFIRMED: Address successfully removed
```

## Understanding IPv6 Address Types

### Address Origins
- **RouterAdvertisement/Link**: SLAAC addresses using interface identifier
- **RouterAdvertisement/Random**: Privacy extension addresses (RFC 4941)
- **Manual**: Manually configured addresses
- **DHCP**: DHCPv6-assigned addresses

### Why Addresses Might Fail
1. **Network Configuration**: Router not forwarding certain prefixes
2. **Firewall Rules**: Blocking specific address ranges
3. **ISP Filtering**: Provider blocking certain IPv6 prefixes
4. **Deprecated Addresses**: Addresses past their preferred lifetime
5. **Routing Issues**: Missing or incorrect routes for the prefix

## Troubleshooting

### "Failed to get IPv6 addresses from interface"
- Verify the interface name: `Get-NetAdapter | Select-Object Name`
- Ensure IPv6 is enabled on the interface
- Check if the interface has IPv6 addresses: `Get-NetIPAddress -InterfaceAlias "Interface Name" -AddressFamily IPv6`

### "PowerShell method failed: Access denied"
- Run PowerShell as Administrator
- Check if address is protected by system policy

### "Address still exists after removal attempt"
- Some addresses are autoconfigured and may regenerate
- Router advertisements may reassign the same prefix
- Privacy extensions cycle automatically

### Addresses Regenerate After Removal
This is normal behavior for:
- SLAAC addresses (will regenerate from router advertisements)
- Privacy extension addresses (regenerate with new random suffixes)
- To prevent regeneration, configure the router or disable IPv6 on the interface

## Security Considerations

- The script requires administrator privileges for address modification
- Address removal may temporarily disrupt network connectivity
- Failed addresses might indicate network security policies
- Always test in a non-production environment first

## License

This project is provided as-is for educational and administrative purposes.

## Contributing

Feel free to submit issues, feature requests, or pull requests to improve the script.