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
"@
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

 .Description

 .Parameter query

 .Example
   
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
Export-ModuleMember -Function * -Verbose:$false