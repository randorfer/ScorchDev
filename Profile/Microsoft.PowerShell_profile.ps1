Function Get-MissingFailovers()
{
    $noFailover = Get-Agent |? {!$_.GetFailoverManagementServers()}
    If ($noFailover.Count -eq $null) 
    {
      Write-Host "All agents have a failover server assigned." -ForeGroundColor Green
    } 
    else 
    {
      Write-Host "Warning! Missing failover agents for the following servers: " -ForeGroundColor Magenta;
      foreach ($agent in $noFailover) {
        Write-Host $agent.Name -ForeGroundColor Magenta
      }
    }
}

Function Set-Failover() 
{
  # Set Primary Management Server
  $Primary_MS = Get-ManagementServer | ? {$_.Name -like "SERVERNAME*"}
  # Set Failover Management Server
  $Failover_MS = Get-ManagementServer | ? {$_.Name -like "BACKUPSERVER*"}
  $noFailoverSpecified = Get-Agent | ? {(!$_.GetFailoverManagementServers())}

  ForEach ($agent in $noFailoverSpecified) 
  {
    Set-ManagementServer -PrimaryManagementServer $Primary_MS -AgentManagedComputer $agent -FailoverServer $Failover_MS | Out-Null
  }
}


Function Get-AgentNameByHSID([guid]$hsid) 
{
  (Get-MonitoringObject -id $hsid).DisplayName
}


function Get-ActiveRules ([string]$server, [string]$location) 
{
  If (!$location) { $location = "C:\$server-Rules.xml" }
  # Create the Task object
  $taskobj = Get-Task | Where-Object {$_.Name -eq "Microsoft.SystemCenter.GetAllRunningWorkflows"}
  # Make sure we have it, if not, the MP isn’t installed.
  If (!$taskobj) 
  {
    Write-Host "Unable to find required monitoring tasks – MS System Center Internal Tasks MP needs to be installed." -ForeGroundColor Magenta;
    break;
  }
  # Grab HealthService class object
  $hsobj = Get-MonitoringClass -name "Microsoft.SystemCenter.HealthService"
  # Find HealthService object defined for named server
  $monobj = Get-MonitoringObject -MonitoringClass $hsobj | Where-Object {$_.DisplayName -match $server}
  # Now actually proceed with the task. I have mine formatted like this version, but I’ve added some light
  # error checking for the ‘public’ version.
  #(Start-Task -task $taskobj -TargetMonitoringObject $monobj).Output | Out-File C:\$server-Rules.xml
  $taskOut = Start-Task -Task $taskobj -TargetMonitoringObject $monobj
  # See if it worked, if it did, export out the OutPut part and save as an XML file, then display some items.
  If ($taskOut.ErrorCode -eq 0) 
  {
    [xml]$taskXML = $taskOut.OutPut
    $ruleCount = $taskXML.DataItem.Count
    Write-Host "Succeeded in gathering rules for $server" -ForeGroundColor Green
    Write-Host "Currently $ruleCount rules active." -ForeGroundColor Green
    Write-Host "Exporting to $location" -ForeGroundColor Green
    $taskOut.OutPut | Out-File $location
  } 
  else 
  {
    Write-Host "Error gathering rules for $server" -ForeGroundColor Magenta
    Write-Host "Error Code: " + $taskOut.ErrorCode -ForeGroundColor Magenta
    Write-Host "Error Message: " + $taskOut.ErrorMessage -ForeGroundColor Magenta
  }
}


function shorten-path([string] $path) 
{ 
   $loc = $path.Replace($HOME, '~') 
   # remove prefix for UNC paths 
   $loc = $loc -replace '^[^:]+::', '' 
   # make path shorter like tabs in Vim, 
   # handle paths starting with \\ and . correctly 
   return ($loc -replace '\\(\.?)([^\\])[^\\]*(?=\\)','\$1$2') 
}

function prompt 
{ 
   # our theme 
   $cdelim = [ConsoleColor]::DarkCyan 
   $chost = [ConsoleColor]::Green 
   $cloc = [ConsoleColor]::Cyan 

   write-host "$([char]0x0A7) " -n -f $cloc 
   write-host ([net.dns]::GetHostName()) -n -f $chost 
   write-host ' {' -n -f $cdelim 
   write-host (shorten-path (pwd).Path) -n -f $cloc 
   write-host '}' -n -f $cdelim 
   return ' ' 
}

#$tabExpand = (get-item function:\tabexpansion).Definition
#if($tabExpand -match 'try {Resolve-Path.{49}(?=;)')
#{
#   $tabExpand = $tabExpand.Replace($matches[0], "if((get-location).Provider.Name -ne 'OperationsManagerMonitoring'){ $($matches[0]) }" )
#   invoke-expression "function TabExpansion{$tabExpand}"
#}

get-pssnapin -registered | add-pssnapin

