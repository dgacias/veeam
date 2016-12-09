Add-PSSnapin -Name VeeamPSSnapIn -ErrorAction SilentlyContinue
Add-PSSnapin VMware.VimAutomation.Core


#DEFINES
$hour = Get-Date -format dd-MM-yyyy-HH-mm
$vmwareuser = "vmware_backup_capable_user_here"
$vmwarepassword = "the_user_password"
$HostName = "your_hostname_FQDN_or_IP"
$Directory = "your_local_dir_like_D:\backups"
# Desired compression level (Optional; Possible values: 0 - None, 4 - Dedupe-friendly, 5 - Optimal, 6 - High, 9 - Extreme) 
$CompressionLevel = "4"
$EnableQuiescence = $False
$EnableEncryption = $False
# Retention possible values: Never , Tonight, TomorrowNight, In3days, In1Week, In2Weeks, In1Month)
$Retention = "In3days"

$ESTADOWARNING = 0
$ESTADOFAILED = 0
$ESTADOSUCCESS = 0
#Introductory message on slack:
$mensajeslack = "Daily backup report on $HostName:\n"
#Your slack webhook uri, this one is a fake one for example pourposes:
$webhookuri = 'https://hooks.slack.com/services/A28LCUYYF/N184SAAA6/dfeYEYY4pnJkKn7ZJBrkfF4m'

Connect-VIServer $HostName -User $vmwareuser -Password $vmwarepassword

#You can specify vm's names or backup all avaliable machines:
#all: $VMNames = (VMware.VimAutomation.Core\Get-VM | foreach { $_.Name })
#specific: $VMNames = "vmname1,vmname2,vmname3"

$VMNames = (VMware.VimAutomation.Core\Get-VM | foreach { $_.Name })


write-host "Starting backups..."
Asnp VeeamPSSnapin
write-host "Fetching $HostName..."
$Server = Get-VBRServer -name $HostName
$MesssagyBody = @()
write-host "Done."
foreach ($VMName in $VMNames) 
{ 
  $VM = Find-VBRViEntity -Name $VMName -Server $Server
   
    Write-host "Starting backup of $VMName..."
    $ZIPSession = Start-VBRZip -Entity $VM -Folder $Directory -Compression $CompressionLevel -DisableQuiesce:(!$EnableQuiescence) -AutoDelete $Retention
    $resultado = $ZIPSession | select-object {$_.Result} | ft -HideTableHeaders | out-string
    $resultado = $resultado -replace "\s", ""
    Write-host "Result: $resultado"


    #counters
    $boolsuccess = $resultado | select-string -pattern "Success" -Quiet
    $boolwarning = $resultado | select-string -pattern "Warning" -Quiet
    $boolfailed = $resultado | select-string -pattern "Failed" -Quiet
    
    if ($boolsuccess -eq $True) { $ESTADOSUCCESS++ }
    elseif ($boolwarning -eq $True) { $ESTADOWARNING++ }
    else { $ESTADOFAILED++ }
    
#Deduplication (fully optional)
#Write-Host "Deduplicating..."
#Start-DedupJob -Type Optimization d:
    
    #concatenate result to slack message
    $textoresultado = $VMName + ": " + $resultado + "\n"
    $mensajeslack = $mensajeslack + $textoresultado
}  

#Post to slack
Write-host "Sending message to Slack..."


$json = "{`"text`": `"$mensajeslack`",`"attachments`":[{`"color`": `"good`",`"fields`": [{`"title`": `"Success`",`"value`": `"$ESTADOSUCCESS`",`"short`": false}]},{`"color`": `"warning`",`"fields`": [{`"title`": `"Warning`",`"value`": `"$ESTADOWARNING`",`"short`": false}]},{`"color`": `"danger`",`"fields`": [{`"title`": `"Failed`",`"value`": `"$ESTADOFAILED`",`"short`": false}]}]}"

Invoke-WebRequest -Uri $webhookuri -Body $json -ContentType "application/json" -Method Post -UseBasicParsing

if ($ESTADOFAILED -gt 0 ) {Write-host "There are fails!"; exit(1)}
elseif ($ESTADOWARNING -gt 0 ) {Write-host "There are warnings!"; exit(1)}
elseif ($ESTADOSUCCESS -gt 0 ) {Write-host "Everything is OK!"; exit(0)}
else {write-host "UNKNOWN FAIL!, Check veeam's log in veeam console."; exit(1) }
