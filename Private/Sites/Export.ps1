function Write-PSISitesLog([string]$Path,[string]$RunId,[string]$Phase,[string]$Operation,[string]$Outcome,[string]$Target,[string]$Message,[long]$DurationMs=0,[string]$ErrorId=''){
    [pscustomobject][ordered]@{Timestamp=[datetimeoffset]::Now.ToString('o');Level=if($Outcome -in @('Failed','TimedOut')){'Warning'}else{'Information'};RunId=$RunId;Phase=$Phase;Target=$Target;Operation=$Operation;Outcome=$Outcome;DurationMs=$DurationMs;Message=$Message;ErrorId=$ErrorId}|
        ConvertTo-Json -Compress|Add-Content -LiteralPath $Path -Encoding UTF8
}
function New-PSIInventoryDashboard($Meta,$Sections,$Data,$Coverage,[string]$ModuleRoot,[string]$ReportBaseName){
    $html=[IO.File]::ReadAllText((Join-Path $ModuleRoot 'Templates/Dashboard.html'))
    $html=$html.Replace('/*DASHBOARD_CSS*/',[IO.File]::ReadAllText((Join-Path $ModuleRoot 'Assets/Dashboard.css')))
    $html=$html.Replace('/*JP_BRAND_CSS*/',[IO.File]::ReadAllText((Join-Path $ModuleRoot 'Assets/JP.brand.css')))
    $html=$html.Replace('/*DASHBOARD_JS*/',[IO.File]::ReadAllText((Join-Path $ModuleRoot 'Assets/Dashboard.js')))
    $fallback=New-Object text.StringBuilder
    [void]$fallback.Append('<h1>JP | PSInsightInventory - '+[net.webutility]::HtmlEncode($Meta.title)+'</h1><p>'+[net.webutility]::HtmlEncode($Meta.notice)+'</p>')
    $details='Scope: '+$Meta.scope+' | Version: '+$Meta.version+' | Run: '+$Meta.run+' | Generated: '+$Meta.generatedDisplay
    [void]$fallback.Append('<p>'+[net.webutility]::HtmlEncode($details)+'</p><p>Open in a browser with JavaScript to explore the inventory. The CSV and JSON files beside this report contain the full export.</p>')
    foreach($key in $Sections.Keys){
        $columns=@($Sections[$key][1]);$records=@($Data[$key])
        [void]$fallback.Append('<h2>'+[net.webutility]::HtmlEncode($Sections[$key][0])+' ('+$records.Count+' observed)</h2>')
        if(-not $records.Count){continue}
        [void]$fallback.Append('<div class="tablewrap"><table><thead><tr>')
        foreach($column in $columns){[void]$fallback.Append('<th scope="col">'+[net.webutility]::HtmlEncode($column)+'</th>')}
        [void]$fallback.Append('</tr></thead><tbody>')
        foreach($record in ($records | Select-Object -First 5)){
            [void]$fallback.Append('<tr>')
            foreach($column in $columns){[void]$fallback.Append('<td>'+[net.webutility]::HtmlEncode([string](Get-PSISiteValue $record $column))+'</td>')}
            [void]$fallback.Append('</tr>')
        }
        [void]$fallback.Append('</tbody></table></div>')
    }
    $browserPayload=[ordered]@{meta=$Meta;sections=$Sections;data=$Data;coverage=$Coverage;reportBaseName=$ReportBaseName}
    $html=$html.Replace('<!--FALLBACK-->',$fallback.ToString())
    if($html -notmatch '/\*DATA\*/' -or $html -match '/\*(?:DASHBOARD_CSS|DASHBOARD_JS|JP_BRAND_CSS)\*/'){throw 'Dashboard template placeholders are invalid.'}
    $html.Replace('/*DATA*/',(ConvertTo-PSISafeJson $browserPayload))
}
function New-PSIInventoryRunFolder([string]$OutputPath,[string]$FolderName){
    $null = New-Item -ItemType Directory -Path $OutputPath -Force -ErrorAction Stop
    for($number = 1; ; $number++){
        $name = if($number -eq 1){$FolderName}else{'{0}_{1:00}' -f $FolderName,$number}
        $path = Join-Path $OutputPath $name
        try{
            $null = New-Item -ItemType Directory -Path $path -ErrorAction Stop
            return $path
        }catch{
            if(-not (Test-Path -LiteralPath $path)){throw}
        }
    }
}

function Export-PSISitesReport($Model,$Meta,[string]$ModuleRoot,[string]$ReportFolder,[string]$TemplateName='SitesAndServices.html',[string]$ReportBaseName='Sites-And-Services'){
    $schema=$Model.Schema;$data=$Model.Data
    $csvFolder=Join-Path $ReportFolder 'CSV';$null=New-Item -ItemType Directory -Path $csvFolder -Force
    $payload=[ordered]@{meta=$Meta;sections=$schema;data=$data;coverage=$Model.Coverage;raw=$Model.Raw}
    $json=$payload|ConvertTo-Json -Depth 30 -Compress
    $html=New-PSIInventoryDashboard $Meta $schema $data $Model.Coverage $ModuleRoot $ReportBaseName
    foreach($key in $schema.Keys){
        $cols=@($schema[$key][1]);$rows=@($data[$key]);$path=Join-Path $csvFolder ($key+'.csv')
        if($rows.Count){
            $rows | ForEach-Object{
                $safe=[ordered]@{};foreach($c in $cols){$v=Get-PSISiteValue $_ $c;if($v -is [string] -and $v -match '^[=+@\-\t\r\n]'){$v="'"+$v};$safe[$c]=$v};[pscustomobject]$safe
            }|Select-Object -Property $cols|Export-Csv -LiteralPath $path -Encoding UTF8 -NoTypeInformation
        }else{('"'+($cols -join '","')+'"'+[environment]::NewLine)|Set-Content -LiteralPath $path -Encoding UTF8 -NoNewline}
    }
    $htmlPath=Join-Path $ReportFolder ($ReportBaseName+'.html');$jsonPath=Join-Path $ReportFolder ($ReportBaseName+'.json')
    $utf8=New-Object text.UTF8Encoding($true)
    [IO.File]::WriteAllText($htmlPath,$html,$utf8);[IO.File]::WriteAllText($jsonPath,$json,$utf8)
    [pscustomobject]@{HtmlReport=$htmlPath;JsonSnapshot=$jsonPath;CsvFolder=$csvFolder}
}
