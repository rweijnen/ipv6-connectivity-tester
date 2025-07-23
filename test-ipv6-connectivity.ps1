# IPv6 Connectivity Test Script
# Tests IPv6 addresses on specified interface and optionally removes failed addresses
#
# Usage examples:
#   .\test-ipv6-connectivity.ps1
#   .\test-ipv6-connectivity.ps1 -RemoveFailedAddresses
#   .\test-ipv6-connectivity.ps1 -RemoveFailedRoutes  
#   .\test-ipv6-connectivity.ps1 -RemoveFailedAddresses -RemoveFailedRoutes -Force
#   .\test-ipv6-connectivity.ps1 -InterfaceName "Wi-Fi" -TestTarget "cloudflare.com"

param(
    [string]$InterfaceName = "Ethernet 2",
    [string]$TestTarget = "google.com",
    [switch]$RemoveFailedAddresses,
    [switch]$RemoveFailedRoutes,
    [switch]$Force
)

Write-Host "Testing IPv6 connectivity for interface: $InterfaceName" -ForegroundColor Green
Write-Host "Target: $TestTarget" -ForegroundColor Green
Write-Host ""

# Get IPv6 addresses using netsh
try {
    $netshOutput = netsh interface ipv6 show address $InterfaceName 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to get IPv6 addresses from interface '$InterfaceName'. Check if interface exists."
        exit 1
    }
} catch {
    Write-Error "Error running netsh command: $_"
    exit 1
}

# Parse IPv6 addresses from netsh output
$ipv6Addresses = @()
foreach ($line in $netshOutput) {
    if ($line -match "Address\s+(\S+)\s+Parameters") {
        $address = $matches[1]
        # Filter out link-local addresses (fe80::) and loopback (::1)
        if ($address -notmatch "^fe80:" -and $address -ne "::1") {
            $ipv6Addresses += $address
        }
    }
}

if ($ipv6Addresses.Count -eq 0) {
    Write-Warning "No global IPv6 addresses found on interface '$InterfaceName'"
    Write-Host "Available addresses from netsh output:"
    $netshOutput | Where-Object { $_ -match "Address" } | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
    exit 1
}

Write-Host "Found IPv6 addresses:" -ForegroundColor Cyan
$ipv6Addresses | ForEach-Object { Write-Host "  $_" -ForegroundColor White }
Write-Host ""

# Test connectivity for each IPv6 address in parallel
Write-Host "Starting parallel connectivity tests..." -ForegroundColor Cyan
$jobs = @()

# Start background jobs for each address
foreach ($address in $ipv6Addresses) {
    $job = Start-Job -ScriptBlock {
        param($addr, $target)
        $result = @{
            Address = $addr
            Success = $false
            Output = ""
            Stats = ""
        }
        
        try {
            $pingOutput = ping -6 -S $addr -n 3 $target 2>$null
            if ($LASTEXITCODE -eq 0) {
                $result.Success = $true
                $result.Output = "SUCCESS: Ping from $addr to $target successful"
                $stats = $pingOutput | Where-Object { $_ -match "packets.*transmitted.*received" }
                if ($stats) {
                    $result.Stats = $stats
                }
            } else {
                $result.Success = $false
                $result.Output = "FAILED: Ping from $addr to $target failed"
            }
        } catch {
            $result.Success = $false
            $result.Output = "ERROR: Exception during ping test: $($_.Exception.Message)"
        }
        
        return $result
    } -ArgumentList $address, $TestTarget
    
    $jobs += @{Job = $job; Address = $address}
    Write-Host "  Started test for $address" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Waiting for all tests to complete..." -ForegroundColor Cyan

# Wait for all jobs and collect results
$successCount = 0
$failedAddresses = @()

foreach ($jobInfo in $jobs) {
    $job = $jobInfo.Job
    $address = $jobInfo.Address
    
    Write-Host "Collecting results for $address..." -ForegroundColor Yellow
    
    try {
        $result = Receive-Job -Job $job -Wait
        Remove-Job -Job $job
        
        if ($result.Success) {
            Write-Host "  $($result.Output)" -ForegroundColor Green
            if ($result.Stats) {
                Write-Host "    $($result.Stats)" -ForegroundColor Gray
            }
            $successCount++
        } else {
            Write-Host "  $($result.Output)" -ForegroundColor Red
            $failedAddresses += $address
        }
    } catch {
        Write-Host "  ERROR: Failed to get job result: $_" -ForegroundColor Red
        $failedAddresses += $address
        Remove-Job -Job $job -Force
    }
    Write-Host ""
}

# Summary
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Total IPv6 addresses tested: $($ipv6Addresses.Count)" -ForegroundColor White
Write-Host "  Successful connections: $successCount" -ForegroundColor White
Write-Host "  Failed connections: $($ipv6Addresses.Count - $successCount)" -ForegroundColor White

# Handle failed addresses removal
if ($failedAddresses.Count -gt 0 -and ($RemoveFailedAddresses -or $RemoveFailedRoutes)) {
    Write-Host ""
    Write-Host "Failed addresses to process:" -ForegroundColor Yellow
    $failedAddresses | ForEach-Object { Write-Host "  $_" -ForegroundColor White }
    
    if (-not $Force) {
        $confirmation = Read-Host "Do you want to proceed with removal? (y/N)"
        if ($confirmation -notmatch "^[Yy]") {
            Write-Host "Operation cancelled." -ForegroundColor Yellow
            exit 0
        }
    }
    
    foreach ($failedAddr in $failedAddresses) {
        Write-Host ""
        Write-Host "Processing failed address: $failedAddr" -ForegroundColor Cyan
        
        if ($RemoveFailedAddresses) {
            Write-Host "  Analyzing address details..." -ForegroundColor Yellow
            
            # Get detailed address information using PowerShell
            $addressInfo = $null
            try {
                $addressInfo = Get-NetIPAddress -IPAddress $failedAddr -ErrorAction Stop
                Write-Host "    Origin: $($addressInfo.PrefixOrigin)/$($addressInfo.SuffixOrigin)" -ForegroundColor Gray
                Write-Host "    State: $($addressInfo.AddressState)" -ForegroundColor Gray
                Write-Host "    Type: $($addressInfo.Type)" -ForegroundColor Gray
                Write-Host "    Interface: $($addressInfo.InterfaceAlias)" -ForegroundColor Gray
            } catch {
                Write-Host "    Could not get detailed address info: $($_.Exception.Message)" -ForegroundColor Gray
                # Try to find the address in the current interface addresses
                try {
                    $allAddresses = Get-NetIPAddress -InterfaceAlias $InterfaceName -AddressFamily IPv6 -ErrorAction Stop
                    $addressInfo = $allAddresses | Where-Object { $_.IPAddress -eq $failedAddr }
                    if ($addressInfo) {
                        Write-Host "    Found address in interface - Origin: $($addressInfo.PrefixOrigin)/$($addressInfo.SuffixOrigin)" -ForegroundColor Gray
                    } else {
                        Write-Host "    Address not found in current interface addresses (may have been removed already)" -ForegroundColor Yellow
                    }
                } catch {
                    Write-Host "    Could not enumerate interface addresses: $($_.Exception.Message)" -ForegroundColor Gray
                }
            }
            
            Write-Host "  Attempting address removal..." -ForegroundColor Yellow
            $removalSuccess = $false
            
            # Only attempt removal if address still exists
            if ($addressInfo) {
                try {
                    # Method 1: PowerShell Remove-NetIPAddress
                    try {
                        Remove-NetIPAddress -IPAddress $failedAddr -Confirm:$false -ErrorAction Stop
                        Write-Host "    SUCCESS: Removed using Remove-NetIPAddress" -ForegroundColor Green
                        $removalSuccess = $true
                        
                        # Verify removal
                        Start-Sleep -Seconds 1
                        try {
                            $checkAddr = Get-NetIPAddress -IPAddress $failedAddr -ErrorAction Stop
                            Write-Host "    WARNING: Address still exists after removal attempt" -ForegroundColor Yellow
                        } catch {
                            Write-Host "    CONFIRMED: Address successfully removed" -ForegroundColor Green
                        }
                    } catch {
                        Write-Host "    PowerShell method failed: $($_.Exception.Message)" -ForegroundColor Gray
                    }
                    
                    # Method 2: netsh with exact syntax if PowerShell failed
                    if (-not $removalSuccess) {
                        $result = netsh interface ipv6 delete address interface="$InterfaceName" address="$failedAddr" 2>&1
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host "    SUCCESS: Removed using netsh" -ForegroundColor Green
                            $removalSuccess = $true
                        } else {
                            Write-Host "    netsh method failed: $result" -ForegroundColor Gray
                        }
                    }
                    
                    # Method 3: Try disabling/enabling privacy extensions for temporary addresses
                    if (-not $removalSuccess -and $addressInfo -and $addressInfo.SuffixOrigin -eq "Random") {
                        Write-Host "    This is a privacy extension address - trying alternative approach..." -ForegroundColor Yellow
                        Write-Host "    Disabling IPv6 privacy extensions temporarily..." -ForegroundColor Gray
                        
                        $privacyResult = netsh interface ipv6 set privacy state=disabled 2>&1
                        if ($LASTEXITCODE -eq 0) {
                            Start-Sleep -Seconds 2
                            # Re-enable privacy extensions
                            netsh interface ipv6 set privacy state=enabled 2>&1
                            Write-Host "    Privacy extensions cycled - address should regenerate with new value" -ForegroundColor Yellow
                        }
                    }
                    
                    if (-not $removalSuccess) {
                        Write-Host "    WARNING: Could not remove address $failedAddr" -ForegroundColor Red
                        Write-Host "    This address is likely autoconfigured via SLAAC/Router Advertisement" -ForegroundColor Yellow
                        Write-Host "    It may regenerate automatically or require router configuration changes" -ForegroundColor Yellow
                    }
                    
                } catch {
                    Write-Host "    ERROR: Exception during removal: $_" -ForegroundColor Red
                }
            } else {
                Write-Host "  Address not found - may have been removed already or never existed" -ForegroundColor Yellow
                $removalSuccess = $true  # Consider it successful if address doesn't exist
            }
        }
        
        if ($RemoveFailedRoutes) {
            Write-Host "  Finding and removing associated routes..." -ForegroundColor Yellow
            try {
                # Get routes that use this address as next hop or source
                $routeOutput = netsh interface ipv6 show route 2>$null
                $routesToRemove = @()
                
                foreach ($line in $routeOutput) {
                    if ($line -match "Destination.*$failedAddr" -or $line -match "Next Hop.*$failedAddr") {
                        $routesToRemove += $line
                    }
                }
                
                if ($routesToRemove.Count -eq 0) {
                    Write-Host "    No specific routes found for this address" -ForegroundColor Gray
                } else {
                    foreach ($route in $routesToRemove) {
                        Write-Host "    Found route: $route" -ForegroundColor Gray
                        # Note: Specific route removal would need destination parsing
                        # This is a simplified approach - in practice you'd parse the route table
                    }
                }
            } catch {
                Write-Host "    ERROR: Exception finding routes: $_" -ForegroundColor Red
            }
        }
    }
}

if ($successCount -gt 0) {
    Write-Host ""
    Write-Host "IPv6 connectivity is working!" -ForegroundColor Green
    exit 0
} else {
    Write-Host ""
    Write-Host "No IPv6 addresses could reach the target" -ForegroundColor Red
    exit 1
}