$LocalAutomationVariableEndpoints = @('https://localhost', 'http://localhost', 'localhost')
add-type @"
        using System.Net;
        using System.Security.Cryptography.X509Certificates;

            public class IDontCarePolicy : ICertificatePolicy {
            public IDontCarePolicy() {}
            public bool CheckValidationResult(
                ServicePoint sPoint, X509Certificate cert,
                WebRequest wRequest, int certProb) {
                return true;
            }
        }
"@ -Verbose:$False -Debug:$false
<#
    .SYNOPSIS
        Gets one or more SMA variable values from the given web service endpoint.

    .DESCRIPTION
        Get-BatchSMAVariable gets the value of each SMA variable given in $Name.
        If $Prefix is set, "$Prefix-$Name" is looked up in SMA (helps keep the
        list of variables in $Name concise).

    .PARAMETER Name
        A list of variable values to get from SMA.

    .PARAMETER WebServiceEndpoint
        The SMA web service endpoint to query for variables.

    .PARAMETER Prefix
        A prefix to be applied to each variable name when performing the lookup
        in SMA. A '-' is added to the end of $Prefix automatically.
#>
Function Get-BatchSMAVariable
{
    Param(
        [Parameter(Mandatory=$True)]  [String[]] $Name,
        [Parameter(Mandatory=$True)]  [String]   $WebServiceEndpoint,
        [Parameter(Mandatory=$False)] [AllowNull()] [String] $Prefix = $Null
    )
    $Variables = @{}
    $VarCommand = (Get-Command -Name 'Get-SMAVariable')
    $VarParams = @{'WebServiceEndpoint' = $WebServiceEndpoint}
    # We can't call Get-AutomationVariable in SMA from a function, so we have to determine if we
    # are developing locally. If we are, we can call Get-AutomationVariable. If not, we'll call
    # Get-SMAVariable and pass it an endpoint representing localhost.
    If((Test-LocalDevelopment) -and ($WebServiceEndpoint -in (Get-LocalAutomationVariableEndpoint)))
    {
        # Note that even though it looks like we should be getting variables from the local development
        # system, there is a chance we won't be.
        #
        # Get-AutomationVariable contains logic that may call Get-SMAVariable - this allows for getting
        # variables from real SMA during local testing or troubleshooting scenarios.
        $VarCommand = (Get-Command -Name 'Get-AutomationVariable')
        $VarParams = @{}
    }
    ForEach($VarName in $Name)
    {
        If(-not [String]::IsNullOrEmpty($Prefix))
        {
            $SMAVarName = "$Prefix-$VarName"
        }
        Else
        {
            $SMAVarName = $VarName
        }
        $Variables[$VarName] = (& $VarCommand -Name "$SMAVarName" @VarParams).Value
        Write-Verbose -Message "Variable [$VarName / $SMAVarName] = [$($Variables[$VarName])]"
    }
    Return (New-Object -TypeName 'PSObject' -Property $Variables)
}

Function Get-BatchAutomationVariable
{
    Param(
        [Parameter(Mandatory=$True)]  $Name,
        [Parameter(Mandatory=$False)] $Prefix = $Null
    )

    Return (Get-BatchSMAVariable -Prefix $Prefix -Name $Name -WebServiceEndpoint (Get-LocalAutomationVariableEndpoint)[0])
}

<#
    .SYNOPSIS
        Returns $true if working in a development environment outside SMA, $false otherwise.
#>
function Test-LocalDevelopment
{
    $LocalDevModule = Get-Module -ListAvailable -Name 'LocalDev' -Verbose:$False -ErrorAction 'SilentlyContinue' -WarningAction 'SilentlyContinue'
    if($LocalDevModule -ne $null)
    {
        return $true
    }
    return $false
}

<#
    .SYNOPSIS
        Returns a list of web service endpoints which represent the local system.
#>
function Get-LocalAutomationVariableEndpoint
{
    # We need this function to expose the list of endpoints to the LocalDev module.
    return $LocalAutomationVariableEndpoints
}
<# 
    .Synopsis
        Returns a filtered list off all jobs in a target status
#>
Function Get-SMAJobInStatus
{
    Param(  [Parameter(Mandatory=$true) ] [String]$WebserviceEndpoint,
            [Parameter(Mandatory=$false)] [String]$Port="9090",
            [Parameter(Mandatory=$false)] [String]$tenantID = "00000000-0000-0000-0000-000000000000",
            [Parameter(Mandatory=$true) ] [String]$JobStatus,
            [Parameter(Mandatory=$false)] [PSCredential]$Credential)

    $BaseUri = "$WebserviceEndpoint`:$Port/$tenantID"
    
    $JobsUri = "$BaseUri/Jobs?`$filter=JobStatus eq '$JobStatus'"

    $box = Get-SMAJobsInStatusInternal -JobsUri $JobsUri -Credential $Credential

    return $box
}
<# 
    .Synopsis
        Called internally by Get-SMAJobInStatus
#>
Function Get-SMAJobsInStatusInternal
{
    Param( [Parameter(Mandatory=$true) ] [String]$JobsUri,
           [Parameter(Mandatory=$false)] [PSCredential]$Credential )

    [System.Net.ServicePointManager]::CertificatePolicy = new-object IDontCarePolicy

    $null = $(
        if ($Credential) { $jobs = Invoke-RestMethod -Uri $JobsUri -Credential $Credential }
        else             { $jobs = Invoke-RestMethod -Uri $JobsUri -UseDefaultCredentials }

        $addedToBox = $false

        $box = New-Object System.Collections.ArrayList
        foreach ($j in $jobs) 
        {
            $box.Add((Format-SMAObject $j)) | Out-Null
        }
    )
    return $box
}

<# 
 .Synopsis
    Runs an SMA runbook using Start-SMARunbook. Waits for completion and returns all output  
#>
Function Start-SmaRunbookSync
{
    Param([Parameter(Mandatory=$True) ][string]                         $Name,
          [Parameter(Mandatory=$False)][System.Collections.IDictionary] $Parameters = @{},
          [Parameter(Mandatory=$False)][string]                         $WebserviceEndpoint = 'https://localhost',
          [Parameter(Mandatory=$False)][int]                            $Timeout = 900,
          [Parameter(Mandatory=$False)][pscredential]                   $Credential)
    
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
	[System.Net.ServicePointManager]::CertificatePolicy = new-object IDontCarePolicy
    $SleepTime = 5
    $startTime = Get-Date
    $RunningStates = @('New',
                       'Activating',
                       'Running')

    $null = $(
        $jobId = Start-SmaRunbook -Name $Name `
                                  -Parameters $Parameters `
                                  -WebServiceEndpoint $WebserviceEndpoint `
                                  -Credential $Credential
        
        if(-not $jobId)
        {
            Throw-Exception -Type "Failed to start runbook" `
                            -Message "The target runbook did not start properly" `
                            -Property @{ 'Name' = $Name ;
                                         'Parameters' = $Parameters ;
                                         'WebserviceEnpoint' = $WebserviceEndpoint ;
                                         'Timeout' = $Timeout ;
                                         'CredentialName' = $Credential.UserName  }
        }
        while($startTime.AddSeconds($Timeout) -gt (Get-Date) -and 
             (Get-SmaJob -Id $jobId -WebServiceEndpoint $WebserviceEndpoint -Credential $Credential).JobStatus -in $RunningStates)
        {
            Start-Sleep -Seconds 5
        }
        $jobStatus = (Get-SmaJob -Id $jobId -WebServiceEndpoint $WebserviceEndpoint -Credential $Credential).JobStatus

        if($JobStatus -ne 'Completed')
        {
            Throw-Exception -Type "Job did not complete successfully" `
                            -Message "The job encountered an error and did not complete" `
                            -Property @{ 'Input Parameters' = @{ 'Name' = $Name ;
                                                                 'Parameters' = $Parameters ;
                                                                 'WebserviceEndpoint' = $WebserviceEndpoint ;
                                                                 'Timeout' = $Timeout ;
                                                                 'CredentialName' = $Credential.UserName } ;
                                         'Timeout' = (-not ($startTime.AddSeconds($Timeout) -gt (Get-Date))) ;
                                         'Job' = (Get-SmaJob -Id $jobId -WebServiceEndpoint $WebserviceEndpoint -Credential $Credential) }
        }
        
        $SerializedOutput = (Get-SmaJobOutput -Id $jobId -WebServiceEndpoint $WebserviceEndpoint -Stream Output -Credential $Credential)
        $jobOutput = [System.Management.Automation.PSSerializer]::Deserialize($SerializedOutput.StreamText)
        if(Test-IsNullOrEmpty $jobOutput) { $jobOutput = $jobOutput.StreamText.Trim() }
    )
    return $jobOutput
}
<#
    .Synopsis
        Returns all SMA runbooks. Correctly pages through all pages of runbooks  
#>
Function Get-SMARunbookPaged
{
    Param( [Parameter(Mandatory=$True)] [String]       $WebserviceEndpoint,
           [Parameter(Mandatory=$False)][PSCredential] $Credential,
           [Parameter(Mandatory=$false)][String]       $tenantID = "00000000-0000-0000-0000-000000000000",
           [Parameter(Mandatory=$False)][String]       $Port = '9090')
    
    [System.Net.ServicePointManager]::CertificatePolicy = new-object IDontCarePolicy

    Write-Verbose -Message "Starting"
    $RunbookUri = "$($webserviceendpoint):$($Port)/$($tenantID)/Runbooks"
    $null = $(
        if ($Credential) { $Runbooks = Invoke-RestMethod -Uri $RunbookUri -Credential $Credential }
        else             { $Runbooks = Invoke-RestMethod -Uri $RunbookUri -UseDefaultCredentials }

		$box = New-Object System.Collections.ArrayList
        do
        {
            $addedToBox = $false

            foreach ($Runbook in $Runbooks) 
            { 
                $box.Add((Format-SMAObject -Object $Runbook)) | Out-Null
                $addedToBox = $true
            }
            if($addedToBox)
            {
                $SkipURL = "$($RunbookUri)?$`skiptoken=guid'$($box[-1].RunbookID)'"
                Write-Verbose -Message "`$SkipURL [$SkipURL]"
                if ($Credential) { $Runbooks = Invoke-RestMethod -Uri $SkipURL -Credential $Credential }
                else             { $Runbooks = Invoke-RestMethod -Uri $SkipURL -UseDefaultCredentials }
            }
        }
        while($addedToBox)
    )
    return $box
}
<#
    .Synopsis
        Used to make SMA objects more friendly
#>
Function Format-SMAObject
{
    Param([Parameter(Mandatory=$true)] $object)
    
    $PropertyHT = @{}
    $PropertyHT.Add('Id', $object.id)
    foreach($Property in $object.content.properties.ChildNodes)
    {
        $PropertyHT.Add($Property.LocalName, $Property.FirstChild.Value)
    }
    foreach($Property in $object.properties.ChildNodes)
    {
        $PropertyHT.Add($Property.LocalName, $Property.FirstChild.Value)
    }

    (ConvertFrom-JSON (ConvertTo-Json $PropertyHT))
}
<#
    .Synopsis
        Sets the tag line on runbooks
#>
Function Set-SmaRunbookTags
{
    Param([Parameter(Mandatory=$true)][string]$RunbookID, 
          [Parameter(Mandatory=$false)][string]$Tags=$null,
          [Parameter(Mandatory=$true)][string]$WebserviceEndpoint=$null,
          [Parameter(Mandatory=$false)][string]$TenantId='00000000-0000-0000-0000-000000000000',
          [Parameter(Mandatory=$false)][string]$port = "9090",
          [Parameter(Mandatory=$false)][pscredential]$Credential)

    $null = $(
        Write-Verbose -Message "Starting Set-SmaRunbookTags for [$RunbookID] Tags [$Tags]" 
        $RunbookURI = "$($WebserviceEndpoint):$($port)/$($TenantId)/Runbooks(guid'$($RunbookID)')"
        [xml]$baseXML = @'
<?xml version="1.0" encoding="utf-8"?>
<entry xmlns="http://www.w3.org/2005/Atom" xmlns:d="http://schemas.microsoft.com/ado/2007/08/dataservices" xmlns:m="http://schemas.microsoft.com/ado/2007/08/dataservices/metadata">
    <id></id>
    <category term="Orchestrator.ResourceModel.Runbook" scheme="http://schemas.microsoft.com/ado/2007/08/dataservices/scheme" />
    <title />
    <updated></updated>
    <author>
        <name />
    </author>
    <content type="application/xml">
        <m:properties>
            <d:Tags></d:Tags>
        </m:properties>
    </content>
</entry>
'@
        $baseXML.Entry.id                      = $RunbookURI
        $baseXML.Entry.Content.Properties.Tags = [string]$Tags

        if($Credential)
        {
            $output = Invoke-RestMethod -Method Merge `
                                        -Uri $RunbookURI `
                                        -Body $baseXML `
                                        -Credential $Credential `
                                        -ContentType 'application/atom+xml'
        }
        else
        {
            $output = Invoke-RestMethod -Method Merge `
                                        -Uri $RunbookURI `
                                        -Body $baseXML `
                                        -UseDefaultCredentials `
                                        -ContentType 'application/atom+xml'
        }
        Write-Verbose -Message "Finished Set-SmaRunbookTags for $RunbookID"
    )
}
<#
    .Synopsis
        Returns all runbook workers in FQDN format. Expects that all runbook
        workers are in the same domain as the worker that this command is run
        from. If local development defaults to 'localhost'
#>
Function Get-SMARunbookWorker
{
    if(Test-LocalDevelopment)
    {
        return 'localhost'
    }
    else
    {
        if(([System.Net.Dns]::GetHostByName(($env:computerName))).HostName -match '^([^.]+)\.(.*)$')
        {
            $domain = $Matches[2]
        }

        $Workers = Get-SmaRunbookWorkerDeployment -WebServiceEndpoint (Get-LocalAutomationVariableEndpoint)[0]
        foreach($Worker in $Workers.ComputerName)
        {
            if(-not $Worker.Contains($domain))
            {
                $Worker = "$($Worker).$($domain)"
                Write-Output -InputObject $Worker
            }
        }
    }
}
<#
    .Synopsis
        Returns job data about a runbook worker for a given time window. Default time
        window is the last hour
    
    .Parameter SqlServer
        The name of the SQL server hosting the SMA database
    
    .Parameter Host
        The Name of the runbook worker to return information for

    .Parameter StartTime
        The Start Time for the window of logs

    .Parameter EndTime
        The End Time for the window of logs
#>
Function Get-SmaRunbookWorkerJob
{
    Param([Parameter(Mandatory=$true) ][string]   $SqlServer,
          [Parameter(Mandatory=$true) ][string]   $RunbookWorker,
          [Parameter(Mandatory=$false)][DateTime] $StartTime = (Get-Date).AddHours(-1),
          [Parameter(Mandatory=$false)][AllowNull()] $EndTime = $null,
          [Parameter(Mandatory=$false)][AllowNull()] $JobStatus = $null)

    $SqlQuery = 'DECLARE @low INT, @high INT
                            SELECT @low = LowKey, @high = HighKey 
                            FROM [SMA].[Queues].[Deployment]
                            WHERE ComputerName = @RunbookWorker
 
                            select r.*, 
	                               j.*
                            from sma.core.vwJobs as j
                            inner join [SMA].[Core].[RunbookVersions] as v
                            on j.RunbookVersionId = v.RunbookVersionId
                            inner join [SMA].[Core].[Runbooks] as r 
                            on v.RunbookKey = r.RunbookKey
                            where PartitionId > @low and PartitionId < @high
                            and StartTime >  @start'
    $Parameters = @{'start' = $StartTime ;
                    'RunbookWorker' = $RunbookWorker}
    if($EndTime) 
    { 
        $SqlQuery = "$($SqlQuery)`r`nand StartTime < @end" 
        $Parameters.Add('end',$EndTime) | Out-Null

    }
    if($JobStatus)
    {
        $SqlQuery = "$($SqlQuery)`r`nand j.JobStatus = @JobStatus" 
        $Parameters.Add('JobStatus',$JobStatus) | Out-Null
    }
    Invoke-SqlQuery -query $SqlQuery `
                    -parameters $Parameters `
                    -connectionString "Data Source=$SqlServer;Initial Catalog=SMA;Integrated Security=True;"
}
Export-ModuleMember -Function * -Verbose:$false -Debug:$False