# This script block runs inside each target DC's existing PowerShell endpoint.
# It reads local providers only. It never authenticates onward to a second host.
$script:DCInvRemoteCollector = {
    param([string]$TargetName)
    $ErrorActionPreference = 'Stop'
    function Read-Value($Object, [string]$Property) {
        if ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Property]) { $Object.$Property }
    }
    function Join-Values($Values) { (@($Values | Where-Object { $null -ne $_ }) | ForEach-Object { [string]$_ }) -join '; ' }
    function Iso-Date($Value) {
        if ($null -ne $Value) { ([datetimeoffset]$Value).ToString('o') }
    }
    function Emit-Section([string]$Key, [string]$Method, [scriptblock]$Action) {
        $started = [datetimeoffset]::Now
        $clock = [diagnostics.stopwatch]::StartNew()
        $status = 'Succeeded'; $errorId = $null; $message = $null; $records = @()
        try { $records = @(& $Action) }
        catch { $status = 'Failed'; $errorId = $_.FullyQualifiedErrorId; $message = $_.Exception.Message }
        $clock.Stop()
        [pscustomobject]@{
            Kind = 'Section'; Target = $TargetName; Key = $Key; Status = $status; Method = $Method
            StartedAt = $started.ToString('o'); CollectedAt = [datetimeoffset]::Now.ToString('o')
            DurationMs = $clock.ElapsedMilliseconds; Records = $records; ErrorId = $errorId; ErrorMessage = $message
        }
    }
    Emit-Section 'system' 'WinRM / local CIM (Win32_ComputerSystem, Win32_OperatingSystem)' {
        $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        [pscustomobject][ordered]@{
            Name = $TargetName; Manufacturer = $computer.Manufacturer; Model = $computer.Model
            CPU = $computer.NumberOfLogicalProcessors; 'Memory GB' = [math]::Round($computer.TotalPhysicalMemory / 1GB, 2)
            'OS build' = $os.BuildNumber; 'Last boot' = Iso-Date $os.LastBootUpTime
            'OS caption' = $os.Caption; 'OS version' = $os.Version
            'Uptime days' = [math]::Round(([datetime]::Now - [datetime]$os.LastBootUpTime).TotalDays, 2)
        }
    }
    Emit-Section 'disks' 'WinRM / local CIM (fixed logical disks)' {
        Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop | ForEach-Object {
            [pscustomobject][ordered]@{
                Name = $TargetName; Drive = $_.DeviceID; Label = $_.VolumeName
                'Capacity GB' = if ($null -ne $_.Size) { [math]::Round($_.Size / 1GB, 2) } else { $null }
                'Free GB' = if ($null -ne $_.FreeSpace) { [math]::Round($_.FreeSpace / 1GB, 2) } else { $null }
                'File system' = $_.FileSystem
            }
        }
    }
    Emit-Section 'paths' 'WinRM / local NTDS and Netlogon registry (read only)' {
        $ntds = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters' -ErrorAction Stop
        $netlogon = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters' -ErrorAction Stop
        [pscustomobject][ordered]@{
            Name = $TargetName; Database = Read-Value $ntds 'DSA Database file'
            'Log directory' = Read-Value $ntds 'Database log files path'; SYSVOL = Read-Value $netlogon 'SysVol'
        }
    }
    Emit-Section 'network' 'WinRM / local CIM (IP-enabled adapters)' {
        Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=TRUE' -ErrorAction Stop | ForEach-Object {
            $dns = @($_.DNSServerSearchOrder | Where-Object { $_ })
            $v4 = @($_.IPAddress | Where-Object { $_ -notmatch ':' })
            $v6 = @($_.IPAddress | Where-Object { $_ -match ':' })
            [pscustomobject][ordered]@{
                Name = $TargetName; Adapter = $_.Description; IPv4 = Join-Values $v4; IPv6 = Join-Values $v6
                'Subnet masks / prefixes' = Join-Values $_.IPSubnet; Gateway = Join-Values $_.DefaultIPGateway
                'Preferred DNS' = if ($dns.Count -gt 0) { $dns[0] } else { $null }
                'Alternate DNS' = if ($dns.Count -gt 1) { $dns[1] } else { $null }
                'Additional DNS' = if ($dns.Count -gt 2) { Join-Values $dns[2..($dns.Count-1)] } else { $null }
                'DNS search order' = Join-Values $dns; 'Interface index' = $_.InterfaceIndex
                'MAC address' = $_.MACAddress; DHCP = $_.DHCPEnabled
            }
        }
    }
    # Missing DNS service means this role is not installed, not a failed DNS query.
    $dnsService = @(); $dnsDetectionError = $null; $dnsAbsent = $false
    try { $dnsService = @(Get-Service -Name DNS -ErrorAction Stop) }
    catch {
        if ($_.FullyQualifiedErrorId -like 'NoServiceFoundForGivenName*') { $dnsAbsent = $true }
        else { $dnsDetectionError = $_ }
    }
    if ($null -ne $dnsDetectionError) {
        foreach ($key in @('forwarders', 'zones', 'conditional')) {
            [pscustomobject]@{
                Kind='Section'; Target=$TargetName; Key=$key; Status='Failed'; Method='WinRM / local DNS role detection'
                StartedAt=[datetimeoffset]::Now.ToString('o'); CollectedAt=[datetimeoffset]::Now.ToString('o')
                DurationMs=0; Records=@(); ErrorId=$dnsDetectionError.FullyQualifiedErrorId; ErrorMessage=$dnsDetectionError.Exception.Message
            }
        }
    }
    elseif ($dnsAbsent) {
        foreach ($key in @('forwarders', 'zones', 'conditional')) {
            [pscustomobject]@{
                Kind='Section'; Target=$TargetName; Key=$key; Status='NotApplicable'; Method='WinRM / local DNS role detection'
                StartedAt=[datetimeoffset]::Now.ToString('o'); CollectedAt=[datetimeoffset]::Now.ToString('o')
                DurationMs=0; Records=@(); ErrorId=$null; ErrorMessage='DNS Server service is not installed.'
            }
        }
    }
    else {
        Emit-Section 'forwarders' 'WinRM / local DnsServer module (Get-DnsServerForwarder)' {
            Import-Module DnsServer -ErrorAction Stop
            $configuration = Get-DnsServerForwarder -ErrorAction Stop
            $addresses = @($configuration.IPAddress | Where-Object { $null -ne $_ })
            if ($addresses.Count -eq 0) { $addresses = @('(none configured)') }
            $order = 0
            foreach ($address in $addresses) {
                $order++
                [pscustomobject][ordered]@{
                    Name=$TargetName; Forwarder=[string]$address; Order=$order
                    'Timeout seconds'=Read-Value $configuration 'Timeout'; 'Use root hints'=Read-Value $configuration 'UseRootHint'
                    'Service state'=[string]$dnsService[0].Status
                }
            }
        }
        Emit-Section 'zones' 'WinRM / local DnsServer module (non-forwarder zones)' {
            Import-Module DnsServer -ErrorAction Stop
            Get-DnsServerZone -ErrorAction Stop | Where-Object { [string]$_.ZoneType -ne 'Forwarder' } | ForEach-Object {
                [pscustomobject][ordered]@{
                    Name=$TargetName; Zone=$_.ZoneName; Type=[string]$_.ZoneType
                    'AD integrated'=$_.IsDsIntegrated; 'Directory partition'=Read-Value $_ 'DirectoryPartitionName'
                    'Dynamic updates'=[string]$_.DynamicUpdate; 'Reverse lookup'=$_.IsReverseLookupZone
                    'Zone file'=Read-Value $_ 'ZoneFile'
                }
            }
        }
        Emit-Section 'conditional' 'WinRM / local Get-DnsServerZone (ZoneType Forwarder)' {
            Import-Module DnsServer -ErrorAction Stop
            Get-DnsServerZone -ErrorAction Stop | Where-Object { [string]$_.ZoneType -eq 'Forwarder' } | ForEach-Object {
                [pscustomobject][ordered]@{
                    Name=$TargetName; 'DNS namespace'=$_.ZoneName; 'Master servers'=Join-Values (Read-Value $_ 'MasterServers')
                    'AD integrated'=$_.IsDsIntegrated; 'Directory partition'=Read-Value $_ 'DirectoryPartitionName'
                    'Timeout seconds'=Read-Value $_ 'ForwarderTimeout'; 'Use recursion'=Read-Value $_ 'UseRecursion'
                }
            }
        }
    }
    Emit-Section 'time' 'WinRM / local W32Time registry and w32tm /query /source' {
        $parameters=Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters' -ErrorAction Stop
        $config=Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config' -ErrorAction Stop
        $source = & "$env:SystemRoot\System32\w32tm.exe" /query /source 2>&1
        if ($LASTEXITCODE -ne 0) { throw "w32tm /query /source exited $LASTEXITCODE : $($source -join ' ')" }
        [pscustomobject][ordered]@{
            Name=$TargetName; Source=($source -join ' ').Trim(); Type=Read-Value $parameters 'Type'
            'NTP server setting'=Read-Value $parameters 'NtpServer'; 'Announce flags'=Read-Value $config 'AnnounceFlags'
        }
    }
    Emit-Section 'certificates' 'WinRM / certificate provider (LocalMachine\My, public metadata only)' {
        Get-ChildItem -LiteralPath Cert:\LocalMachine\My -ErrorAction Stop | ForEach-Object {
            $templates=@($_.Extensions | Where-Object { $_.Oid.Value -in @('1.3.6.1.4.1.311.20.2','1.3.6.1.4.1.311.21.7') } | ForEach-Object { $_.Format($false) })
            $eku=@($_.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.37' } | ForEach-Object { $_.Format($false) })
            [pscustomobject][ordered]@{
                Name=$TargetName; Subject=$_.Subject; Issuer=$_.Issuer; Template=Join-Values $templates
                'Not after'=Iso-Date $_.NotAfter; 'Not before'=Iso-Date $_.NotBefore
                Store='LocalMachine\My'; Thumbprint=$_.Thumbprint; 'Has private key'=$_.HasPrivateKey; EKU=Join-Values $eku
            }
        }
    }
    Emit-Section 'shares' 'WinRM / local CIM (Win32_Share)' {
        Get-CimInstance -ClassName Win32_Share -ErrorAction Stop | ForEach-Object {
            [pscustomobject][ordered]@{ Name=$TargetName; Share=$_.Name; Path=$_.Path; Description=$_.Description; Type=$_.Type }
        }
    }
}
