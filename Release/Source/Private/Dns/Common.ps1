function Get-DCInvValue($Object,[string]$Property){
    if($null -eq $Object){return $null}
    if($Object -is [System.Collections.IDictionary]){if($Object.Contains($Property)){return $Object[$Property]}else{return $null}}
    if($null -ne $Object.PSObject.Properties[$Property]){return $Object.$Property}
    return $null
}

function ConvertTo-DCInvFlat($Value){
    if($null -eq $Value){return $null}
    if($Value -is [datetime] -or $Value -is [datetimeoffset]){return ([datetimeoffset]$Value).ToString('o')}
    if($Value -is [string] -or $Value -is [bool] -or $Value -is [ValueType]){return $Value}
    if($Value -is [System.Collections.IEnumerable]){return (@($Value | ForEach-Object{[string]$_}) -join '; ')}
    return [string]$Value
}

function Write-DCInvLog([string]$Level,[string]$Phase,[string]$Target,[string]$Operation,[string]$Outcome,[string]$Message,[long]$DurationMs=0,[string]$ErrorId='', [string]$ErrorMessage=''){
    [pscustomobject][ordered]@{
        Timestamp=[datetimeoffset]::Now.ToString('o');Level=$Level;RunId=$script:DCInvRunId;Phase=$Phase
        Target=$Target;Operation=$Operation;Outcome=$Outcome;DurationMs=$DurationMs;Message=$Message;ErrorId=$ErrorId;ErrorMessage=$ErrorMessage
    } | ConvertTo-Json -Compress -Depth 5 | Add-Content -LiteralPath $script:DCInvLogPath -Encoding UTF8
}

function Add-DCInvSection($Envelope){
    if(Get-Command Receive-PSIInventoryDisplay -ErrorAction SilentlyContinue){Receive-PSIInventoryDisplay -Items @($Envelope)}
    $key=[string]$Envelope.Key;$target=[string]$Envelope.Target
    if(-not $script:DCInvSections.Contains($key) -or $key -eq 'collection'){throw "Unknown category envelope: $key"}
    $identity=$target+'|'+$key
    if($script:DCInvSeen.ContainsKey($identity)){throw "Duplicate category envelope: $identity"}
    $allowed=@('Succeeded','Partial','Failed','TimedOut','NotAttempted','NotApplicable')
    if([string]$Envelope.Status -notin $allowed){throw "Invalid collection status for $identity"}
    $rows=@($Envelope.Records | Where-Object{$null -ne $_})
    # Failed/timeout categories have no trusted records; completed categories are separate envelopes.
    if([string]$Envelope.Status -notin @('Succeeded','Partial','NotApplicable')){$rows=@()}
    foreach($row in $rows){
        $record=[ordered]@{}
        foreach($column in $script:DCInvSections[$key][1]){$record[$column]=ConvertTo-DCInvFlat (Get-DCInvValue $row $column)}
        $record.Name=$target
        [void]$script:DCInvData[$key].Add([pscustomobject]$record)
    }
    $outcome=switch([string]$Envelope.Status){'Succeeded'{'Collected'}'Partial'{'Partial'}'NotApplicable'{'Not applicable'}'NotAttempted'{'Not attempted'}'TimedOut'{'Timed out'}default{'Failed'}}
    $message=[string](Get-DCInvValue $Envelope 'ErrorMessage')
    if($Envelope.Status -eq 'Succeeded'){$message='Collection succeeded; zero records is a valid empty result.'}
    $ledger=[pscustomobject][ordered]@{
        Name=$target;Section=$script:DCInvSections[$key][0];Outcome=$outcome;Method=$Envelope.Method
        'Collected at'=$Envelope.CollectedAt;Message=$message;'Check ID'=$key;Status=$Envelope.Status
        'Duration ms'=$Envelope.DurationMs;'Record count'=$rows.Count;'Error ID'=Get-DCInvValue $Envelope 'ErrorId'
        'Started at'=Get-DCInvValue $Envelope 'StartedAt'
    }
    [void]$script:DCInvData.collection.Add($ledger);$script:DCInvSeen[$identity]=$true
    $level=if($Envelope.Status -in @('Succeeded','NotApplicable')){'Information'}else{'Warning'}
    Write-DCInvLog $level 'Collection' $target $key $Envelope.Status $message $Envelope.DurationMs ([string](Get-DCInvValue $Envelope 'ErrorId')) ([string](Get-DCInvValue $Envelope 'ErrorMessage'))
}

function Select-DCInvTargets([object[]]$Discovered,[string]$SelectedDomain,[string[]]$Names){
    $domainTargets=@($Discovered | Where-Object{[string]$_.Domain -ieq $SelectedDomain} | Sort-Object HostName -Unique)
    if($domainTargets.Count -ne $Discovered.Count){throw 'Discovery returned a DC outside the requested domain. Collection stopped.'}
    if(-not $domainTargets.Count){throw "No domain controllers discovered in $SelectedDomain"}
    if(@($Names | Where-Object{$_}).Count -eq 0){return $domainTargets}
    $selected=New-Object System.Collections.ArrayList
    foreach($name in $Names){
        if($name -match '[*?\[\]]'){throw 'ComputerName accepts exact short names or FQDNs, not wildcard patterns.'}
        $matches=@($domainTargets | Where-Object{[string]$_.Name -ieq $name -or [string]$_.HostName -ieq $name})
        if($matches.Count -ne 1){throw "ComputerName '$name' is not a unique DC discovered in $SelectedDomain"}
        if(@($selected | Where-Object{$_.HostName -ieq $matches[0].HostName}).Count -eq 0){[void]$selected.Add($matches[0])}
    }
    $selected.ToArray()
}

function Invoke-DCInvDiscovery([string]$RequestedDomain,[pscredential]$DiscoveryCredential,[int]$TimeoutSeconds){
    $job=$null
    try{
        $job=Start-Job -ScriptBlock {
            param($RequestedDomain,$DiscoveryCredential)
            $ErrorActionPreference='Stop'
            Import-Module ActiveDirectory -ErrorAction Stop
            $params=@{Server=$RequestedDomain;ErrorAction='Stop'}
            if($null -ne $DiscoveryCredential){$params.Credential=$DiscoveryCredential}
            $domainInfo=Get-ADDomain @params
            if($domainInfo.DNSRoot -ine $RequestedDomain){throw 'Requested domain does not match discovered DNS domain.'}
            Get-ADDomainController -Filter * @params | ForEach-Object{
                [pscustomobject]@{
                    Name=$_.Name;HostName=$_.HostName;Domain=$_.Domain;Site=$_.Site;IPv4Address=$_.IPv4Address;IPv6Address=$_.IPv6Address
                    OperatingSystem=$_.OperatingSystem;OperatingSystemVersion=$_.OperatingSystemVersion;IsGlobalCatalog=$_.IsGlobalCatalog
                    IsReadOnly=$_.IsReadOnly;NTDSSettingsObjectDN=$_.NTDSSettingsObjectDN;OperationMasterRoles=@($_.OperationMasterRoles | ForEach-Object{[string]$_})
                }
            }
        } -ArgumentList $RequestedDomain,$DiscoveryCredential -ErrorAction Stop
        $discoveryClock=[diagnostics.stopwatch]::StartNew();$finished=$null
        while($discoveryClock.Elapsed.TotalSeconds -lt $TimeoutSeconds){
            if(Get-Command Update-PSIInventoryDisplay -ErrorAction SilentlyContinue){Update-PSIInventoryDisplay -Stage 'Discovering domain controllers'}
            if($job.State -in @('Completed','Failed','Stopped')){$finished=$job;break}
            Start-Sleep -Milliseconds 200
        }
        if($null -eq $finished){throw "Domain discovery exceeded $TimeoutSeconds seconds. No DC collection started."}
        $results=@(Receive-Job -Job $job -ErrorAction Stop)
        if($job.State -ne 'Completed'){throw "Domain discovery ended with state $($job.State)"}
        return $results
    }
    finally{if($null -ne $job){if($job.State -in @('Running','NotStarted','Blocked')){Stop-Job -Job $job -ErrorAction SilentlyContinue};Remove-Job -Job $job -Force -ErrorAction SilentlyContinue}}
}


function Invoke-DCInvWorkers([object[]]$Controllers,[scriptblock]$Worker,[string]$RemoteText,$Settings,[pscredential]$WorkerCredential){
    if(Get-Command Update-PSIInventoryDisplay -ErrorAction SilentlyContinue){Update-PSIInventoryDisplay -Total ($Controllers.Count*@($script:DCInvSections.Keys|Where-Object{$_ -ne 'collection'}).Count)}
    $pending=New-Object 'System.Collections.Generic.Queue[object]'
    foreach($controller in $Controllers){$pending.Enqueue($controller)}
    $active=New-Object System.Collections.ArrayList;$finishedCount=0
    $required=@($script:DCInvSections.Keys | Where-Object{$_ -ne 'collection' -and $_ -ne 'dcs'})
    try{
        while($pending.Count -gt 0 -or $active.Count -gt 0){
            while($pending.Count -gt 0 -and $active.Count -lt $Settings.ThrottleLimit){
                $dc=$pending.Dequeue();$target=[string]$dc.HostName
                Write-DCInvLog 'Information' 'Collection' $target 'Worker' 'Started' 'Starting read-only target worker.'
                $job=Start-Job -ScriptBlock $Worker -ArgumentList $dc,$WorkerCredential,$Settings,$RemoteText -ErrorAction Stop
                [void]$active.Add([pscustomobject]@{Job=$job;Controller=$dc;Clock=[diagnostics.stopwatch]::StartNew();ErrorMessage=''})
            }
            foreach($item in @($active.ToArray())){
                $receiveErrors=@()
                $envelopes=@(Receive-Job -Job $item.Job -ErrorAction SilentlyContinue -ErrorVariable receiveErrors)
                foreach($envelope in $envelopes){
                    if([string](Get-DCInvValue $envelope 'Kind') -eq 'Section'){Add-DCInvSection $envelope}
                    else{throw "Unexpected worker output from $($item.Controller.HostName). Expected category envelope."}
                }
                if($receiveErrors.Count){$item.ErrorMessage=($receiveErrors | ForEach-Object{$_.Exception.Message}) -join '; '}
                $timedOut=$item.Clock.Elapsed.TotalSeconds -ge $Settings.TargetTimeoutSeconds
                $terminal=$item.Job.State -in @('Completed','Failed','Stopped')
                if($timedOut -or $terminal){
                    if($timedOut -and -not $terminal){Stop-Job -Job $item.Job -ErrorAction SilentlyContinue}
                    # Drain any envelopes produced between the earlier receive and completion/cancellation.
                    $lastErrors=@();$last=@(Receive-Job -Job $item.Job -ErrorAction SilentlyContinue -ErrorVariable lastErrors)
                    foreach($envelope in $last){if([string](Get-DCInvValue $envelope 'Kind') -eq 'Section'){Add-DCInvSection $envelope}}
                    if($lastErrors.Count){$item.ErrorMessage=($lastErrors | ForEach-Object{$_.Exception.Message}) -join '; '}
                    foreach($key in $required){
                        if(-not $script:DCInvSeen.ContainsKey($item.Controller.HostName+'|'+$key)){
                            $status=if($timedOut -and -not $terminal){'TimedOut'}else{'Failed'}
                            $message=if($status -eq 'TimedOut'){"Target worker exceeded $($Settings.TargetTimeoutSeconds) seconds; this category did not complete."}elseif($item.ErrorMessage){$item.ErrorMessage}else{'Worker did not return this category.'}
                            Add-DCInvSection ([pscustomobject]@{Target=$item.Controller.HostName;Key=$key;Status=$status;Method='Worker / incomplete category';StartedAt=$null;CollectedAt=[datetimeoffset]::Now.ToString('o');DurationMs=[long]$item.Clock.ElapsedMilliseconds;Records=@();ErrorId='DCInventory.WorkerIncomplete';ErrorMessage=$message})
                        }
                    }
                    Remove-Job -Job $item.Job -Force -ErrorAction SilentlyContinue
                    [void]$active.Remove($item);$finishedCount++
                    if(-not (Get-Command Test-PSIInventoryQuiet -ErrorAction SilentlyContinue) -or -not (Test-PSIInventoryQuiet)){Write-Information "[$finishedCount/$($Controllers.Count)] Inventory collection finished: $($item.Controller.HostName)" -InformationAction Continue}
                }
            }
            if(Get-Command Update-PSIInventoryDisplay -ErrorAction SilentlyContinue){Update-PSIInventoryDisplay}else{Write-Progress -Activity 'Read-only DC inventory' -Status "$finishedCount of $($Controllers.Count) controllers finished; $($active.Count) active" -PercentComplete (100*$finishedCount/$Controllers.Count)}
            if($active.Count -gt 0){Start-Sleep -Milliseconds 200}
        }
    }
    finally{
        foreach($item in @($active.ToArray())){Stop-Job -Job $item.Job -ErrorAction SilentlyContinue;Remove-Job -Job $item.Job -Force -ErrorAction SilentlyContinue}
            if(Get-Command Update-PSIInventoryDisplay -ErrorAction SilentlyContinue){Update-PSIInventoryDisplay}else{Write-Progress -Activity 'Read-only DC inventory' -Completed}
    }
}

