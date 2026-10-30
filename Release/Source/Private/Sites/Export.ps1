function Write-PSISitesLog([string]$Path,[string]$RunId,[string]$Phase,[string]$Operation,[string]$Outcome,[string]$Target,[string]$Message,[long]$DurationMs=0,[string]$ErrorId=''){
    [pscustomobject][ordered]@{Timestamp=[datetimeoffset]::Now.ToString('o');Level=if($Outcome -in @('Failed','TimedOut')){'Warning'}else{'Information'};RunId=$RunId;Phase=$Phase;Target=$Target;Operation=$Operation;Outcome=$Outcome;DurationMs=$DurationMs;Message=$Message;ErrorId=$ErrorId}|
        ConvertTo-Json -Compress|Add-Content -LiteralPath $Path -Encoding UTF8
}
function Export-PSISitesReport($Model,$Meta,[string]$ModuleRoot,[string]$ReportFolder,[string]$TemplateName='SitesAndServices.html',[string]$ReportBaseName='Sites-And-Services'){
    $schema=$Model.Schema;$data=$Model.Data
    $csvFolder=Join-Path $ReportFolder 'CSV';$null=New-Item -ItemType Directory -Path $csvFolder -Force
    $payload=[ordered]@{meta=$Meta;sections=$schema;data=$data;coverage=$Model.Coverage;raw=$Model.Raw}
    $json=$payload|ConvertTo-Json -Depth 30
    $html=[IO.File]::ReadAllText((Join-Path $ModuleRoot ('Templates/'+$TemplateName)))
    $html=$html.Replace('/*JP_BRAND_CSS*/',[IO.File]::ReadAllText((Join-Path $ModuleRoot 'Assets/JP.brand.css')))
    $about=[IO.File]::ReadAllText((Join-Path $ModuleRoot 'Assets/HelpAbout.html')).Replace('{{MODULE_VERSION}}',[net.webutility]::HtmlEncode([string]$Meta.version))
    $html=$html.Replace('</body>',$about+'</body>')
    $fallback=New-Object text.StringBuilder
    [void]$fallback.Append('<h1>JP | PSInsightInventory - '+[net.webutility]::HtmlEncode($Meta.title)+'</h1><p>'+[net.webutility]::HtmlEncode($Meta.notice)+'</p><p>Scope: '+[net.webutility]::HtmlEncode($Meta.scope)+'</p>')
    foreach($key in $schema.Keys){
        $cols=@($schema[$key][1]);$rows=@($data[$key]);$path=Join-Path $csvFolder ($key+'.csv')
        if($rows.Count){
            $rows | ForEach-Object{
                $safe=[ordered]@{};foreach($c in $cols){$v=Get-PSISiteValue $_ $c;if($v -is [string] -and $v -match '^[=+@\-\t\r\n]'){$v="'"+$v};$safe[$c]=$v};[pscustomobject]$safe
            }|Select-Object -Property $cols|Export-Csv -LiteralPath $path -Encoding UTF8 -NoTypeInformation
        }else{('"'+($cols -join '","')+'"'+[environment]::NewLine)|Set-Content -LiteralPath $path -Encoding UTF8 -NoNewline}
        [void]$fallback.Append('<h2>'+[net.webutility]::HtmlEncode($schema[$key][0])+'</h2><div style="overflow:auto"><table><thead><tr>')
        foreach($c in $cols){[void]$fallback.Append('<th>'+[net.webutility]::HtmlEncode($c)+'</th>')};[void]$fallback.Append('</tr></thead><tbody>')
        foreach($row in $rows){[void]$fallback.Append('<tr>');foreach($c in $cols){[void]$fallback.Append('<td>'+[net.webutility]::HtmlEncode([string](Get-PSISiteValue $row $c))+'</td>')};[void]$fallback.Append('</tr>')}
        [void]$fallback.Append('</tbody></table></div>')
    }
    $html=$html.Replace('/*DATA*/',(ConvertTo-PSISafeJson $payload)).Replace('<!--FALLBACK-->',$fallback.ToString())
    foreach($placeholder in @('/*DATA*/','/*JP_BRAND_CSS*/','<!--FALLBACK-->','{{MODULE_VERSION}}')){if($html.Contains($placeholder)){throw "Unresolved report placeholder: $placeholder"}}
    $htmlPath=Join-Path $ReportFolder ($ReportBaseName+'.html');$jsonPath=Join-Path $ReportFolder ($ReportBaseName+'.json')
    $utf8=New-Object text.UTF8Encoding($true)
    [IO.File]::WriteAllText($htmlPath,$html,$utf8);[IO.File]::WriteAllText($jsonPath,$json,$utf8)
    [pscustomobject]@{HtmlReport=$htmlPath;JsonSnapshot=$jsonPath;CsvFolder=$csvFolder}
}
