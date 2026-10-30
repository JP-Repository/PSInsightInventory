#requires -Version 5.1
<# Offline regression checks. No AD module, network, Pester or infrastructure access required. #>
[CmdletBinding()]
param([string]$ScriptPath=(Join-Path (Split-Path -Parent $PSScriptRoot) 'Private/Invoke-PSIInventoryEngine.ps1'),[string]$OutputPath=(Join-Path ([IO.Path]::GetTempPath()) ('DCInventoryTests_'+[guid]::NewGuid().ToString('N').Substring(0,8))))
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$checks=New-Object System.Collections.ArrayList
function Assert-Check([bool]$Condition,[string]$Name){if(-not $Condition){throw "FAILED: $Name"};[void]$checks.Add($Name);Write-Host "PASS $Name"}
$null=New-Item -ItemType Directory -Path $OutputPath -Force
$tokens=$null;$parseErrors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($ScriptPath,[ref]$tokens,[ref]$parseErrors)
Assert-Check ($parseErrors.Count -eq 0) 'PowerShell parser'
# Sample mode must not execute any infrastructure/job/module commands.
function Invoke-SampleIsolated {
    function Start-Job { throw 'Sample mode attempted a worker job.' }
    function Import-Module { throw 'Sample mode attempted a module import.' }
    function Invoke-Command { throw 'Sample mode attempted remoting.' }
    function Get-CimInstance { throw 'Sample mode attempted CIM.' }
    & $ScriptPath -SampleData -OutputPath $OutputPath
}
$one=Invoke-SampleIsolated;$two=Invoke-SampleIsolated
Assert-Check ($one.OutputFolder -ne $two.OutputFolder) 'Unique output folders on repeated runs'
Assert-Check ((Test-Path -LiteralPath $one.HtmlReport) -and (Test-Path -LiteralPath $two.HtmlReport)) 'Previous run preserved'
Assert-Check ($one.DomainControllers -eq 12 -and $one.CompleteInventory -eq 10 -and $one.PartialInventory -eq 2) 'Sample mode makes no infrastructure calls and yields correct coverage'
$snapshot=Get-Content -LiteralPath $one.JsonSnapshot -Raw | ConvertFrom-Json
$expectedKeys=@($snapshot.sections.PSObject.Properties.Name)
Assert-Check ($expectedKeys.Count -eq 16) 'Sixteen datasets plus overview provide seventeen sections'
Assert-Check ($snapshot.data.collection.Count -eq 180) 'Fifteen category operations per DC'
foreach($key in $expectedKeys){
    $rows=@($snapshot.data.$key);$csv=@(Import-Csv -LiteralPath (Join-Path $one.CsvFolder ($key+'.csv')))
    Assert-Check ($rows.Count -eq $csv.Count) ('CSV agrees with JSON: '+$key)
}
foreach($dc in $snapshot.data.dcs){
    $ledger=@($snapshot.data.collection | Where-Object{$_.Name -eq $dc.Name})
    $unavailable=@($ledger | Where-Object{$_.Status -notin @('Succeeded','NotApplicable')})
    Assert-Check ($ledger.Count -eq 15 -and (($dc.Inventory -eq 'Complete') -eq ($unavailable.Count -eq 0))) ('Coverage ledger: '+$dc.Name)
}
Assert-Check (@($snapshot.data.dcs.Domain | Select-Object -Unique).Count -eq 1) 'Sample illustrates single-domain scope'
$html=Get-Content -LiteralPath $one.HtmlReport -Raw
Assert-Check (-not $html.Contains('/*DATA*/') -and -not $html.Contains('<!--FALLBACK-->')) 'HTML placeholders resolved'
Assert-Check (-not [regex]::IsMatch($html,'<(?:script|img)\b[^>]*\bsrc=|<link\b[^>]*\bhref=','IgnoreCase')) 'Report has no external assets'
Assert-Check ([regex]::Matches($html,'<noscript>').Count -eq 1) 'Static no-JavaScript fallback present'

# Load only reusable function definitions for isolated contract tests.
$functionNames=@('Get-DCInvValue','ConvertTo-DCInvFlat','Write-DCInvLog','Add-DCInvSection','Select-DCInvTargets','Invoke-DCInvWorkers','Export-DCInvCsv','Get-DCInvFallback')
foreach($name in $functionNames){
    $definition=$ast.Find({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    Invoke-Expression $definition.Extent.Text
}
$script:DCInvRunId='offline-tests';$script:DCInvLogPath=Join-Path $OutputPath ('contract-tests_'+[guid]::NewGuid().ToString('N').Substring(0,8)+'.jsonl')
$script:DCInvSections=[ordered]@{};foreach($p in $snapshot.sections.PSObject.Properties){$script:DCInvSections[$p.Name]=@($p.Value[0],@($p.Value[1]))}
function Reset-Fixture {
    $script:DCInvData=[ordered]@{};$script:DCInvSeen=@{}
    foreach($key in $script:DCInvSections.Keys){$script:DCInvData[$key]=New-Object System.Collections.ArrayList}
}
Reset-Fixture
$dcA=[pscustomobject]@{Name='DC01';HostName='dc01.example.test';Domain='example.test'}
$dcB=[pscustomobject]@{Name='DC02';HostName='dc02.child.example.test';Domain='child.example.test'}
$outsideRejected=$false;try{$null=Select-DCInvTargets @($dcA,$dcB) 'example.test' @()}catch{$outsideRejected=$true}
Assert-Check $outsideRejected 'Out-of-domain discovery is rejected'
Assert-Check (@(Select-DCInvTargets @($dcA) 'example.test' @()).Count -eq 1) 'Empty optional target list selects discovered domain controllers'
Assert-Check (@(Select-DCInvTargets @($dcA) 'example.test' @('DC01','dc01.example.test')).Count -eq 1) 'Short name/FQDN target selection deduplicates'
$wildcardRejected=$false;try{$null=Select-DCInvTargets @($dcA) 'example.test' @('DC*')}catch{$wildcardRejected=$true}
Assert-Check $wildcardRejected 'Wildcard targets are rejected'
function Envelope($Key,$Status,$Records=@(),$Message=''){
    [pscustomobject]@{Kind='Section';Target='dc01.example.test';Key=$Key;Status=$Status;Method='Offline test';StartedAt=[datetimeoffset]::Now.ToString('o');CollectedAt=[datetimeoffset]::Now.ToString('o');DurationMs=1;Records=$Records;ErrorId='OfflineTest';ErrorMessage=$Message}
}
Add-DCInvSection (Envelope 'roles' 'Succeeded')
Add-DCInvSection (Envelope 'system' 'Failed' @([pscustomobject]@{Name='bad';CPU=4}) 'Access denied')
Add-DCInvSection (Envelope 'forwarders' 'NotApplicable' @() 'DNS service absent')
Add-DCInvSection (Envelope 'shares' 'NotAttempted' @() 'Excluded by scope')
Assert-Check ($script:DCInvData.roles.Count -eq 0 -and $script:DCInvData.collection[0].Status -eq 'Succeeded') 'Successful empty collection stays distinct from failure'
Assert-Check ($script:DCInvData.system.Count -eq 0 -and $script:DCInvData.collection[1].Status -eq 'Failed') 'Failed category cannot contribute trusted inventory'
Assert-Check ($script:DCInvData.collection[2].Status -eq 'NotApplicable' -and $script:DCInvData.collection[3].Status -eq 'NotAttempted') 'Not applicable and not attempted remain distinct'
$duplicateRejected=$false;try{Add-DCInvSection (Envelope 'roles' 'Succeeded')}catch{$duplicateRejected=$true}
Assert-Check $duplicateRejected 'Duplicate target/category envelopes are rejected'
Assert-Check ($null -eq (ConvertTo-DCInvFlat $null)) 'Unknown remains null'
Assert-Check ((ConvertTo-DCInvFlat @('one','two')) -eq 'one; two') 'Array values flatten explicitly'
$emptyCsv=Join-Path $OutputPath 'empty.csv';Export-DCInvCsv 'roles' $emptyCsv
Assert-Check ((Get-Content -LiteralPath $emptyCsv -Raw).Contains('"Name","Role","Scope"')) 'Empty CSV contains stable headers'
Reset-Fixture
$hostile='=SUM(1,2) & <tag> "quoted" </script> Unicode: '+[char]0x03A9
Add-DCInvSection (Envelope 'shares' 'Succeeded' @([pscustomobject]@{Name='dc01.example.test';Share='test';Path=$hostile;Description=$hostile;Type=0}))
$safeCsv=Join-Path $OutputPath 'safe.csv';Export-DCInvCsv 'shares' $safeCsv
$safe=Import-Csv -LiteralPath $safeCsv
Assert-Check ($safe.Path -eq ("'"+$hostile)) 'Spreadsheet-facing CSV neutralizes formula-leading strings'
Assert-Check ($script:DCInvData.shares[0].Path -eq $hostile) 'Raw normalized data retains original evidence'
$fallback=Get-DCInvFallback ([pscustomobject]@{meta=[pscustomobject]@{notice=$hostile;generatedDisplay='test'}})
Assert-Check (-not $fallback.Contains('</script>') -and $fallback.Contains('&lt;/script&gt;')) 'Static fallback encodes hostile markup'
$rawJson=@{Text=$hostile}|ConvertTo-Json
$embedded=$rawJson.Replace('&','\u0026').Replace('<','\u003c').Replace('>','\u003e')
Assert-Check (-not $embedded.Contains('</script>') -and (($embedded|ConvertFrom-Json).Text -eq $hostile)) 'Embedded JSON escapes script-closing payload and round-trips'

# Validate controller worker routing with entirely mocked directory commands.
$workerAst=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path (Split-Path -Parent $ScriptPath) 'Collectors/TargetWorker.ps1'),[ref]$null,[ref]$null)
$workerAssignment=$workerAst.Find({param($n)$n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$script:DCInvTargetWorker'},$true)
Invoke-Expression $workerAssignment.Extent.Text
function Invoke-WorkerFixture {
    function Import-Module {param($Name)}
    function Get-ADReplicationSite {param($Identity,$Server,$Credential,$ErrorAction) [pscustomobject]@{DistinguishedName='CN=SiteA,CN=Sites,CN=Configuration,DC=example,DC=test'}}
    function Get-ADReplicationSubnet {param($Filter,$Properties,$Server,$Credential,$ErrorAction)
        if($Server -ne 'dc01.example.test'){throw 'Wrong AD server'}
        [pscustomobject]@{Name='192.1.0.0/24';Site='CN=SiteA,CN=Sites,CN=Configuration,DC=example,DC=test';Description='Fixture';Location='Test'}
        [pscustomobject]@{Name='198.51.100.0/24';Site='CN=Other,CN=Sites,CN=Configuration,DC=example,DC=test';Description='Other';Location='Test'}
    }
    function Get-ADReplicationPartnerMetadata {param($Target,$EnumerationServer,$Partition,$PartnerType,$Credential,$ErrorAction)
        if($Target -ne 'dc01.example.test' -or $EnumerationServer -ne $Target -or $Partition -ne '*' -or $PartnerType -ne 'Inbound'){throw 'Unexpected replication scope'}
        [pscustomobject]@{Partner='CN=NTDS Settings,CN=DC02';Partition='DC=example,DC=test';IntersiteTransport='IP';LastReplicationSuccess=[datetime]::Now;LastReplicationAttempt=[datetime]::Now;LastReplicationResult=0;ConsecutiveReplicationFailures=0}
    }
    function Get-ADObject {param($SearchBase,$SearchScope,$LDAPFilter,$Properties,$Server,$Credential,$ErrorAction)
        if($SearchBase -ne 'CN=NTDS Settings,CN=DC01' -or $SearchScope -ne 'OneLevel' -or $LDAPFilter -ne '(objectClass=nTDSConnection)'){throw 'Unexpected connection scope'}
        [pscustomobject]@{Name='Connection01';fromServer='CN=NTDS Settings,CN=DC02';enabledConnection=$true;options=1;transportType=$null;DistinguishedName='CN=Connection01,CN=NTDS Settings,CN=DC01'}
    }
    function Invoke-Command {throw '-SkipRemote attempted remoting'}
    $dc=[pscustomobject]@{HostName='dc01.example.test';Domain='example.test';Site='SiteA';NTDSSettingsObjectDN='CN=NTDS Settings,CN=DC01';OperationMasterRoles=@('SchemaMaster','PDCEmulator')}
    & $script:DCInvTargetWorker $dc $null ([pscustomobject]@{SkipRemote=$true}) ''
}
$workerRows=@(Invoke-WorkerFixture)
Assert-Check ($workerRows.Count -eq 14 -and @($workerRows | Where-Object{$_.Status -eq 'Succeeded'}).Count -eq 4) 'Mocked directory worker emits four successful directory categories'
Assert-Check (@($workerRows | Where-Object{$_.Status -eq 'NotAttempted'}).Count -eq 10) 'SkipRemote records all ten excluded categories without remoting'
Assert-Check (@(($workerRows | Where-Object{$_.Key -eq 'subnets'}).Records).Count -eq 1) 'Subnet inventory includes only the assigned AD site'
Assert-Check (($workerRows | Where-Object{$_.Key -eq 'connections'}).Records[0].'Generated by' -eq 'KCC') 'KCC flag is decoded for connection inventory'

$remoteAst=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path (Split-Path -Parent $ScriptPath) 'Collectors/RemoteCollector.ps1'),[ref]$null,[ref]$null)
$remoteAssignment=$remoteAst.Find({param($n)$n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$script:DCInvRemoteCollector'},$true)
Invoke-Expression $remoteAssignment.Extent.Text
function Invoke-RemoteFixture([string]$Scenario){
    function Import-Module {param($Name,$ErrorAction) if($Scenario -eq 'MissingDnsModule'){throw 'Synthetic module missing'}}
    function Get-CimInstance {param($ClassName,$Filter,$ErrorAction)
        switch($ClassName){
            'Win32_ComputerSystem'{if($Scenario -eq 'SystemDenied'){throw 'Synthetic access denied'};[pscustomobject]@{Manufacturer='Example';Model='Virtual';NumberOfLogicalProcessors=8;TotalPhysicalMemory=16GB}}
            'Win32_OperatingSystem'{[pscustomobject]@{BuildNumber='20348';LastBootUpTime=[datetime]::Now.AddDays(-5);Caption='Windows Server 2022';Version='10.0'}}
            'Win32_LogicalDisk'{[pscustomobject]@{DeviceID='C:';VolumeName='System';Size=100GB;FreeSpace=35GB;FileSystem='NTFS'}}
            'Win32_NetworkAdapterConfiguration'{[pscustomobject]@{Description='Ethernet';DNSServerSearchOrder=@('192.0.2.10','192.0.2.11','192.0.2.12');IPAddress=@('192.0.2.10','2001:db8::10');IPSubnet=@('255.255.255.0','64');DefaultIPGateway=@('192.0.2.1');InterfaceIndex=12;MACAddress='00-00-5E-00-53-01';DHCPEnabled=$false}}
            'Win32_Share'{[pscustomobject]@{Name='SYSVOL';Path='C:\Windows\SYSVOL';Description='Fixture';Type=0}}
            default{throw "Unexpected CIM class $ClassName"}
        }
    }
    function Get-ItemProperty {param($LiteralPath,$ErrorAction)
        if($LiteralPath -like '*W32Time*'){throw 'Synthetic time provider unavailable; native executable must not run in this test'}
        if($LiteralPath -like '*NTDS*'){[pscustomobject]@{'DSA Database file'='D:\NTDS\ntds.dit';'Database log files path'='D:\NTDS'}}
        else{[pscustomobject]@{SysVol='C:\Windows\SYSVOL\sysvol'}}
    }
    function Get-Service {param($Name,$ErrorAction)
        if($Scenario -eq 'NoDnsRole'){Write-Error 'Synthetic role absent' -ErrorId 'NoServiceFoundForGivenName' -Category ObjectNotFound -ErrorAction Stop}
        if($Scenario -eq 'ServiceDenied'){throw 'Synthetic service manager access denied'}
        [pscustomobject]@{Status='Running'}
    }
    function Get-DnsServerForwarder {param($ErrorAction) [pscustomobject]@{IPAddress=@('198.51.100.10','198.51.100.11');Timeout=3;UseRootHint=$true}}
    function Get-DnsServerZone {param($ErrorAction)
        [pscustomobject]@{ZoneName='example.test';ZoneType='Primary';IsDsIntegrated=$true;DirectoryPartitionName='DomainDnsZones.example.test';DynamicUpdate='Secure';IsReverseLookupZone=$false;ZoneFile=$null}
        [pscustomobject]@{ZoneName='partner.test';ZoneType='Forwarder';IsDsIntegrated=$true;DirectoryPartitionName='ForestDnsZones.example.test';MasterServers=@('203.0.113.10');ForwarderTimeout=3;UseRecursion=$false}
    }
    function Get-ChildItem {param($LiteralPath,$ErrorAction)
        if($LiteralPath -ne 'Cert:\LocalMachine\My'){throw 'Unexpected certificate path'}
        [pscustomobject]@{Extensions=@();Subject='CN=dc01.example.test';Issuer='CN=Fixture CA';NotAfter=[datetime]::Now.AddYears(1);NotBefore=[datetime]::Now.AddDays(-1);Thumbprint='0000000000000000000000000000000000000001';HasPrivateKey=$true}
    }
    & $script:DCInvRemoteCollector 'dc01.example.test'
}
$remoteRows=@(Invoke-RemoteFixture 'Normal')
Assert-Check ($remoteRows.Count -eq 10) 'Mocked remote collector emits ten independent category envelopes'
Assert-Check (@($remoteRows | Where-Object{$_.Status -eq 'Succeeded'}).Count -eq 9) 'Remote provider failure remains isolated to its category'
Assert-Check (($remoteRows | Where-Object{$_.Key -eq 'network'}).Records[0].'Additional DNS' -eq '192.0.2.12') 'Third and later DNS resolvers are retained separately'
Assert-Check (($remoteRows | Where-Object{$_.Key -eq 'network'}).Records[0].IPv6 -eq '2001:db8::10') 'IPv6 inventory is retained'
Assert-Check (@(($remoteRows | Where-Object{$_.Key -eq 'forwarders'}).Records).Count -eq 2) 'Every configured server forwarder is retained'
Assert-Check (($remoteRows | Where-Object{$_.Key -eq 'zones'}).Records[0].Zone -eq 'example.test') 'Primary DNS zones remain separate from conditional forwarders'
Assert-Check (($remoteRows | Where-Object{$_.Key -eq 'conditional'}).Records[0].'Master servers' -eq '203.0.113.10') 'Conditional forwarder master servers are retained'
Assert-Check (($remoteRows | Where-Object{$_.Key -eq 'certificates'}).Records[0].Thumbprint -eq '0000000000000000000000000000000000000001') 'Certificate inventory exports public metadata'
$roleAbsent=@(Invoke-RemoteFixture 'NoDnsRole')
Assert-Check (@($roleAbsent | Where-Object{$_.Status -eq 'NotApplicable'}).Count -eq 3) 'Absent DNS role is explicitly not applicable'
$serviceDenied=@(Invoke-RemoteFixture 'ServiceDenied')
Assert-Check (@($serviceDenied | Where-Object{$_.Key -in @('forwarders','zones','conditional') -and $_.Status -eq 'Failed'}).Count -eq 3) 'DNS service detection access denial is a failure, not role absence'
$systemDenied=@(Invoke-RemoteFixture 'SystemDenied')
Assert-Check (($systemDenied | Where-Object{$_.Key -eq 'system'}).Status -eq 'Failed' -and ($systemDenied | Where-Object{$_.Key -eq 'disks'}).Status -eq 'Succeeded') 'System access denial does not discard later disk inventory'
$missingModule=@(Invoke-RemoteFixture 'MissingDnsModule')
Assert-Check (@($missingModule | Where-Object{$_.Key -in @('forwarders','zones','conditional') -and $_.Status -eq 'Failed'}).Count -eq 3) 'Missing DNS module is visible in each DNS collection outcome'

# Run the actual scheduler against a harmless local job that streams one section then stalls.
Reset-Fixture
$fakeWorker={param($Controller,$Credential,$Settings,$RemoteText)
    [pscustomobject]@{Kind='Section';Target=$Controller.HostName;Key='roles';Status='Succeeded';Method='Offline scheduler test';StartedAt=[datetimeoffset]::Now.ToString('o');CollectedAt=[datetimeoffset]::Now.ToString('o');DurationMs=1;Records=@();ErrorId=$null;ErrorMessage=$null}
    Start-Sleep -Seconds 30
}
$settings=[pscustomobject]@{ThrottleLimit=1;TargetTimeoutSeconds=5}
Invoke-DCInvWorkers @($dcA) $fakeWorker '' $settings $null
Assert-Check ($script:DCInvData.collection.Count -eq 14) 'Timeout finalizes every worker category'
Assert-Check (@($script:DCInvData.collection | Where-Object{$_.Status -eq 'Succeeded'}).Count -eq 1) 'Completed streamed category survives later timeout'
Assert-Check (@($script:DCInvData.collection | Where-Object{$_.Status -eq 'TimedOut'}).Count -eq 13) 'Only missing categories become timed out'
Assert-Check (@(Get-Job | Where-Object{$_.State -eq 'Running'}).Count -eq 0) 'Scheduler removes its worker jobs'

$logRecords=@(Get-Content -LiteralPath $script:DCInvLogPath | ForEach-Object{$_|ConvertFrom-Json})
Assert-Check (@($logRecords | Where-Object{$_.Outcome -eq 'TimedOut'}).Count -eq 13) 'Structured logs retain timeout context'
$result=[pscustomobject]@{Status='Passed';Checks=$checks.Count;Runtime=$PSVersionTable.PSVersion.ToString();OutputPath=$OutputPath;SampleReport=$one.HtmlReport;WindowsPowerShell51Tested=($PSVersionTable.PSVersion.Major -eq 5)}
$result|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $OutputPath 'TestResults.json') -Encoding UTF8
$result
