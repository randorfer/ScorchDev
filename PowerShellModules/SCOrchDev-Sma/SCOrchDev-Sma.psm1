$LocalAutomationVariableEndpoints = @('https://localhost', 'http://localhost', 'localhost')
Add-Type -TypeDefinition @"
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
"@ -Verbose:$False -Debug:$False
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
        [Parameter(Mandatory = $True)]  [String[]] $Name,
        [Parameter(Mandatory = $True)]  [String]   $WebServiceEndpoint,
        [Parameter(Mandatory = $False)] [AllowNull()] [String] $Prefix = $Null
    )
    $Variables = @{}
    $VarCommand = (Get-Command -Name 'Get-SMAVariable')
    $VarParams = @{
        'WebServiceEndpoint' = $WebServiceEndpoint
    }
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
        [Parameter(Mandatory = $True)]  $Name,
        [Parameter(Mandatory = $False)] $Prefix = $Null
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
    if($LocalDevModule -ne $Null)
    {
        return $True
    }
    return $False
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
    Param(  [Parameter(Mandatory = $True) ] [String]$WebServiceEndpoint,
        [Parameter(Mandatory = $False)] [String]$Port = '9090',
        [Parameter(Mandatory = $False)] [String]$tenantID = '00000000-0000-0000-0000-000000000000',
        [Parameter(Mandatory = $True) ] [String]$JobStatus,
    [Parameter(Mandatory = $False)] [PSCredential]$Credential)

    $BaseUri = "$WebServiceEndpoint`:$Port/$tenantID"
    
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
    Param( [Parameter(Mandatory = $True) ] [String]$JobsUri,
    [Parameter(Mandatory = $False)] [PSCredential]$Credential )

    [System.Net.ServicePointManager]::CertificatePolicy = New-Object -TypeName IDontCarePolicy

    $Null = $(
        if ($Credential) 
        {
            $jobs = Invoke-RestMethod -Uri $JobsUri -Credential $Credential 
        }
        else             
        {
            $jobs = Invoke-RestMethod -Uri $JobsUri -UseDefaultCredentials 
        }

        $addedToBox = $False

        $box = New-Object -TypeName System.Collections.ArrayList
        foreach ($j in $jobs) 
        {
            $Null = $box.Add((Format-SMAObject $j))
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
    Param(
        [Parameter(Mandatory = $True)]
        [string]
        $Name,
        
        [Parameter(Mandatory = $False)]
        [System.Collections.IDictionary]
        $Parameters = @{},

        [Parameter(Mandatory = $False)]
        [string]$WebServiceEndpoint = 'https://localhost',

        [Parameter(Mandatory = $False)]
        [int]
        $Timeout = 900,
    
        [Parameter(Mandatory = $False)]
        [pscredential]
        $Credential
    )
    
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object -TypeName IDontCarePolicy
    $SleepTime = 5
    $startTime = Get-Date
    $RunningStates = @('New', 
        'Activating', 
    'Running')

    $Null = $(
        $jobId = Start-SmaRunbook -Name $Name `
                                  -Parameters $Parameters `
                                  -WebServiceEndpoint $WebServiceEndpoint `
                                  -Credential $Credential
        
        if(-not $jobId)
        {
            Throw-Exception -Type 'Failed to start runbook' `
                            -Message 'The target runbook did not start properly' `
                            -Property @{
                                           'Name' = $Name
                                            'Parameters' = $Parameters
                                            'WebserviceEnpoint' = $WebServiceEndpoint
                                            'Timeout' = $Timeout
                                            'CredentialName' = $Credential.UserName
                                        }
        }
        while($startTime.AddSeconds($Timeout) -gt (Get-Date) -and 
        (Get-SmaJob -Id $jobId -WebServiceEndpoint $WebServiceEndpoint -Credential $Credential).JobStatus -in $RunningStates)
        {
            Start-Sleep -Seconds 5
        }
        $JobStatus = (Get-SmaJob -Id $jobId -WebServiceEndpoint $WebServiceEndpoint -Credential $Credential).JobStatus

        if($JobStatus -ne 'Completed')
        {
            Throw-Exception -Type 'Job did not complete successfully' `
            -Message 'The job encountered an error and did not complete' `
            -Property @{
                'Input Parameters' = @{
                    'Name'             = $Name
                    'Parameters'       = $Parameters
                    'WebserviceEndpoint' = $WebServiceEndpoint
                    'Timeout'          = $Timeout
                    'CredentialName'   = $Credential.UserName
                }
                'Timeout'        = (-not ($startTime.AddSeconds($Timeout) -gt (Get-Date)))
                'Job'            = (Get-SmaJob -Id $jobId -WebServiceEndpoint $WebServiceEndpoint -Credential $Credential)
            }
        }
        
        $SerializedOutput = (Get-SmaJobOutput -Id $jobId -WebServiceEndpoint $WebServiceEndpoint -Stream Output -Credential $Credential)
        if($SerializedOutput)
        {
            $jobOutput = ($SerializedOutput.StreamText -as [string]).Trim()
        }
    )
    return $jobOutput
}
<#
    .Synopsis
    Returns all SMA runbooks. Correctly pages through all pages of runbooks  
#>
Function Get-SMARunbookPaged
{
    Param( 
        [Parameter(Mandatory = $True)] [String]       $WebServiceEndpoint,
        [Parameter(Mandatory = $False)][PSCredential] $Credential,
        [Parameter(Mandatory = $False)][String]       $tenantID = '00000000-0000-0000-0000-000000000000',
        [Parameter(Mandatory = $False)][String]       $Port = '9090'
    )
    
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object -TypeName IDontCarePolicy

    Write-Verbose -Message 'Starting'
    $RunbookUri = "$($WebServiceEndpoint):$($Port)/$($tenantID)/Runbooks"
    $Null = $(
        if ($Credential) 
        {
            $Runbooks = Invoke-RestMethod -Uri $RunbookUri -Credential $Credential 
        }
        else             
        {
            $Runbooks = Invoke-RestMethod -Uri $RunbookUri -UseDefaultCredentials 
        }

        $box = New-Object -TypeName System.Collections.ArrayList
        do
        {
            $addedToBox = $False

            foreach ($Runbook in $Runbooks) 
            { 
                $Null = $box.Add((Format-SMAObject -Object $Runbook))
                $addedToBox = $True
            }
            if($addedToBox)
            {
                $SkipURL = "$($RunbookUri)?$`skiptoken=guid'$($box[-1].RunbookID)'"
                Write-Verbose -Message "`$SkipURL [$SkipURL]"
                if ($Credential) 
                {
                    $Runbooks = Invoke-RestMethod -Uri $SkipURL -Credential $Credential 
                }
                else             
                {
                    $Runbooks = Invoke-RestMethod -Uri $SkipURL -UseDefaultCredentials 
                }
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
    Param([Parameter(Mandatory = $True)] $object)
    
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

    (ConvertFrom-Json -InputObject (ConvertTo-Json $PropertyHT))
}
<#
    .Synopsis
    Sets the tag line on runbooks
#>
Function Set-SmaRunbookTags
{
    Param(
        [Parameter(Mandatory = $True)][string]$RunbookID, 
        [Parameter(Mandatory = $False)][string]$Tags = $Null,
        [Parameter(Mandatory = $True)][string]$WebServiceEndpoint = $Null,
        [Parameter(Mandatory = $False)][string]$tenantID = '00000000-0000-0000-0000-000000000000',
        [Parameter(Mandatory = $False)][string]$Port = '9090',
        [Parameter(Mandatory = $False)][pscredential]$Credential
    )

    $Null = $(
        Write-Verbose -Message "Starting Set-SmaRunbookTags for [$RunbookID] Tags [$Tags]" 
        $RunbookUri = "$($WebServiceEndpoint):$($Port)/$($tenantID)/Runbooks(guid'$($RunbookID)')"
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
        $baseXML.Entry.id                      = $RunbookUri
        $baseXML.Entry.Content.Properties.Tags = [string]$Tags

        $MergeParameters = @{
            'Method' = 'Merge' ;
            'Uri' = $RunbookUri ;
            'Body' = $baseXML ;
            'Credential' = $Credential ;
            'ContentType' = 'application/atom+xml' ;
        }

        if($Credential)
        {
            $MergeParameters.Add('Credential', $Credential) | Out-Null
        }
        else
        {
            $MergeParameters.Add('UseDefaultCredentials', $True) | Out-Null
        }
        $output = Invoke-RestMethod @MergeParameters
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
    Param(
        [Parameter(Mandatory = $True)]
        [string]
        $SqlServer,

        [Parameter(Mandatory = $True)]
        [string]
        $RunbookWorker,

        [Parameter(Mandatory = $False)]
        [DateTime]
        $startTime = (Get-Date).AddHours(-1),

        [Parameter(Mandatory = $False)]
        [AllowNull()]
        $EndTime = $Null,

        [Parameter(Mandatory = $False)]
        [ValidateSet('New', 'Activating', 'Running', 'Completed', 'Failed', 'Stopped',
                     'Blocked', 'Suspended', 'Disconnected', 'Suspending', 'Stopping',
                     'Resuming', 'Removing', 'All')]
        $JobStatus = 'All'
    )

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
                 and StartTime >  @StartTime'
    $Parameters = @{
        'StartTime' = $startTime
        'RunbookWorker' = $RunbookWorker
    }
    if($EndTime) 
    { 
        $SqlQuery = "$($SqlQuery)`r`nand StartTime < @EndTime" 
        $Null = $Parameters.Add('EndTime',$EndTime)
    }
    if($JobStatus -ne 'All')
    {
        $SqlQuery = "$($SqlQuery)`r`nand j.JobStatus = @JobStatus" 
        $Null = $Parameters.Add('JobStatus',$JobStatus)
    }
    Invoke-SqlQuery -query $SqlQuery `
                    -parameters $Parameters `
                    -connectionString "Data Source=$SqlServer;Initial Catalog=SMA;Integrated Security=True;"
}
<#
.Synopsis
    Starts a SMA runbook. Uses invoke-restmethod instead of Start-SMARunbook.
    
.Parameter RunbookId
    The GUID of the runbook to start

.Parameter WebserviceEndpoint
    The url for the SMA webservice

.Parameter WebservicePort
    The port that the SMA webservice is running on.

.Parameter TenantID
    The ID of the target tenant

.Parameter Credential
    A credential object to use for the request. If not passed this method will use
    the default credential
#>
Function Start-SmaRunbookREST
{
    Param(
        [Parameter(Mandatory = $True)] [string]  $RunbookID,
        [Parameter(Mandatory = $False)]          $Parameters = $Null,
        [Parameter(Mandatory = $False)][string]  $WebServiceEndpoint = 'https://localhost',
        [Parameter(Mandatory = $False)][string]  $WebservicePort = '9090',
        [Parameter(Mandatory = $False)][string]  $tenantID = '00000000-0000-0000-0000-000000000000',
        [Parameter(Mandatory = $False)][pscredential] $Credential
    )
    
    $Null = $(
        [System.Net.ServicePointManager]::CertificatePolicy = New-Object -TypeName IDontCarePolicy
        $RestMethodParameters = @{
            'URI'       = "$($WebServiceEndpoint):$($WebservicePort)/$($tenantID)/Runbooks(guid'$($RunbookID)')/Start"
            'Method'    = 'Post'
            'ContentType' = 'application/json;odata=verbose'
        }
        if(-not $Parameters) 
        {
            $_Parameters = @{
                'parameters' = $Null
            }
        }
        else
        {
            $_Parameters = @{
                'parameters' = @()
            }
            foreach($key in $Parameters.Keys)
            {
                $Parameter = @{
                    '__metadata' = @{
                        'type' = 'Orchestrator.ResourceModel.NameValuePair'
                    }
                    'Name'     = $key
                    'Value'    = $Parameters."$key"
                }
                $_Parameters.Parameters += ($Parameter)
            }
        }
        $RestMethodParameters.Add('Body', (ConvertTo-Json -Depth 3 -InputObject $_Parameters -Compress))                      
        if($Credential) 
        {
            $RestMethodParameters.Add('Credential',$Credential) 
        }
        else 
        {
            $RestMethodParameters.Add('UseDefaultCredentials', $True) 
        }

        $Result = Invoke-RestMethod @RestMethodParameters
    )
    return $Result
}
<#
.Synopsis
    Returns modules from a target SMA environment
    
.Parameter WebserviceEndpoint
    The url for the SMA webservice

.Parameter WebservicePort
    The port that the SMA webservice is running on.

.Parameter TenantID
    The ID of the target tenant

.Parameter Credential
    A credential object to use for the request. If not passed this method will use
    the default credential
#>
Function Get-SmaModuleREST
{
    Param(
        [Parameter(Mandatory = $False)][string]  $WebServiceEndpoint = 'https://localhost',
        [Parameter(Mandatory = $False)][string]  $WebservicePort = '9090',
        [Parameter(Mandatory = $False)][string]  $tenantID = '00000000-0000-0000-0000-000000000000',
        [Parameter(Mandatory = $False)][pscredential] $Credential
    )
    
    $Null = $(
        [System.Net.ServicePointManager]::CertificatePolicy = New-Object IDontCarePolicy
        $RestMethodParameters = @{
            'URI'       = "$($WebServiceEndpoint):$($WebservicePort)/$($tenantID)/Modules"
            'Method'    = 'Get'
            'ContentType' = 'application/json;odata=verbose'
        }
       
        if($Credential) 
        {
            $RestMethodParameters.Add('Credential',$Credential) 
        }
        else 
        {
            $RestMethodParameters.Add('UseDefaultCredentials', $True) 
        }

        $Result = Invoke-RestMethod @RestMethodParameters
        $outputArray = @()
        foreach($object in $Result)
        {
            $o = @{
                'ModuleId'       = $object.properties.ModuleID.'#text' -as [guid]
                'CreationTime'   = $object.properties.CreationTime.'#text' -as [datetime]
                'Version'        = $object.properties.Version.'#text' -as [int32]
                'LastModifiedTime' = $object.properties.LastModifiedTime.'#text' -as [datetime]
                'ModuleName'     = $object.properties.ModuleName -as [string]
            }
            $outputArray += $o
        }
    )
    return $outputArray
}
<#
.Synopsis
    Imports a PowerShell module into SMA. Module must be deployed locally
    and a part of the PSModulePath
    
.Parameter ModuleName
    The name of the module

.Parameter WebservicePort
    The port that the SMA webservice is running on.

.Parameter Credential
    A credential object to use for the request. If not passed this method will use
    the default credential
#>
Function Import-SmaPowerShellModule
{
    Param(
        [Parameter(Mandatory = $True) ][string]  $ModuleName,
        [Parameter(Mandatory = $False)][string]  $WebServiceEndpoint = 'https://localhost',
        [Parameter(Mandatory = $False)][string]  $WebservicePort = '9090',
        [Parameter(Mandatory = $False)][pscredential] $Credential
    )
    
    $Module = Get-Module -ListAvailable -Name $ModuleName -Refresh
    $ModuleFolderPath = (Get-Item -Path $Module.Path).Directory.FullName

    $TempDirectory = New-TempDirectory
    try
    {
        $ZipFile = "$TempDirectory\$($ModuleName).zip"
        New-ZipFile -SourceDir $ModuleFolderPath `
                    -ZipFilePath $ZipFile `
                    -OverwriteExisting $True
        Import-SmaModule -Path $ZipFile `
                         -WebServiceEndpoint $WebServiceEndpoint `
                         -Port $WebservicePort `
                         -Credential $Credential
    }
    finally
    {
        Remove-Item $TempDirectory -Force -Recurse
    }
}

<#
    .Synopsis
    returns the default webservice endpoint  
#>
Function Get-WebserviceEndpoint
{
    [OutputType([string])]
    Param()
    Return 'https://localhost'
}
<#
    .Synopsis
    returns the default webservice port  
#>
Function Get-WebservicePort
{
    [OutputType([int])]
    Param()
    Return 9090
}
s
Export-ModuleMember -Function * -Verbose:$False -Debug:$False
# SIG # Begin signature block
# MIIOfQYJKoZIhvcNAQcCoIIObjCCDmoCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUHMC4wQMSIyQwmZX7lhR1pVln
# 01CgggqQMIIB8zCCAVygAwIBAgIQEdV66iePd65C1wmJ28XdGTANBgkqhkiG9w0B
# AQUFADAUMRIwEAYDVQQDDAlTQ09yY2hEZXYwHhcNMTUwMzA5MTQxOTIxWhcNMTkw
# MzA5MDAwMDAwWjAUMRIwEAYDVQQDDAlTQ09yY2hEZXYwgZ8wDQYJKoZIhvcNAQEB
# BQADgY0AMIGJAoGBANbZ1OGvnyPKFcCw7nDfRgAxgMXt4YPxpX/3rNVR9++v9rAi
# pY8Btj4pW9uavnDgHdBckD6HBmFCLA90TefpKYWarmlwHHMZsNKiCqiNvazhBm6T
# XyB9oyPVXLDSdid4Bcp9Z6fZIjqyHpDV2vas11hMdURzyMJZj+ibqBWc3dAZAgMB
# AAGjRjBEMBMGA1UdJQQMMAoGCCsGAQUFBwMDMB0GA1UdDgQWBBQ75WLz6WgzJ8GD
# ty2pMj8+MRAFTTAOBgNVHQ8BAf8EBAMCB4AwDQYJKoZIhvcNAQEFBQADgYEAoK7K
# SmNLQ++VkzdvS8Vp5JcpUi0GsfEX2AGWZ/NTxnMpyYmwEkzxAveH1jVHgk7zqglS
# OfwX2eiu0gvxz3mz9Vh55XuVJbODMfxYXuwjMjBV89jL0vE/YgbRAcU05HaWQu2z
# nkvaq1yD5SJIRBooP7KkC/zCfCWRTnXKWVTw7hwwggPuMIIDV6ADAgECAhB+k+v7
# fMZOWepLmnfUBvw7MA0GCSqGSIb3DQEBBQUAMIGLMQswCQYDVQQGEwJaQTEVMBMG
# A1UECBMMV2VzdGVybiBDYXBlMRQwEgYDVQQHEwtEdXJiYW52aWxsZTEPMA0GA1UE
# ChMGVGhhd3RlMR0wGwYDVQQLExRUaGF3dGUgQ2VydGlmaWNhdGlvbjEfMB0GA1UE
# AxMWVGhhd3RlIFRpbWVzdGFtcGluZyBDQTAeFw0xMjEyMjEwMDAwMDBaFw0yMDEy
# MzAyMzU5NTlaMF4xCzAJBgNVBAYTAlVTMR0wGwYDVQQKExRTeW1hbnRlYyBDb3Jw
# b3JhdGlvbjEwMC4GA1UEAxMnU3ltYW50ZWMgVGltZSBTdGFtcGluZyBTZXJ2aWNl
# cyBDQSAtIEcyMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAsayzSVRL
# lxwSCtgleZEiVypv3LgmxENza8K/LlBa+xTCdo5DASVDtKHiRfTot3vDdMwi17SU
# AAL3Te2/tLdEJGvNX0U70UTOQxJzF4KLabQry5kerHIbJk1xH7Ex3ftRYQJTpqr1
# SSwFeEWlL4nO55nn/oziVz89xpLcSvh7M+R5CvvwdYhBnP/FA1GZqtdsn5Nph2Up
# g4XCYBTEyMk7FNrAgfAfDXTekiKryvf7dHwn5vdKG3+nw54trorqpuaqJxZ9YfeY
# cRG84lChS+Vd+uUOpyyfqmUg09iW6Mh8pU5IRP8Z4kQHkgvXaISAXWp4ZEXNYEZ+
# VMETfMV58cnBcQIDAQABo4H6MIH3MB0GA1UdDgQWBBRfmvVuXMzMdJrU3X3vP9vs
# TIAu3TAyBggrBgEFBQcBAQQmMCQwIgYIKwYBBQUHMAGGFmh0dHA6Ly9vY3NwLnRo
# YXd0ZS5jb20wEgYDVR0TAQH/BAgwBgEB/wIBADA/BgNVHR8EODA2MDSgMqAwhi5o
# dHRwOi8vY3JsLnRoYXd0ZS5jb20vVGhhd3RlVGltZXN0YW1waW5nQ0EuY3JsMBMG
# A1UdJQQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIBBjAoBgNVHREEITAfpB0w
# GzEZMBcGA1UEAxMQVGltZVN0YW1wLTIwNDgtMTANBgkqhkiG9w0BAQUFAAOBgQAD
# CZuPee9/WTCq72i1+uMJHbtPggZdN1+mUp8WjeockglEbvVt61h8MOj5aY0jcwsS
# b0eprjkR+Cqxm7Aaw47rWZYArc4MTbLQMaYIXCp6/OJ6HVdMqGUY6XlAYiWWbsfH
# N2qDIQiOQerd2Vc/HXdJhyoWBl6mOGoiEqNRGYN+tjCCBKMwggOLoAMCAQICEA7P
# 9DjI/r81bgTYapgbGlAwDQYJKoZIhvcNAQEFBQAwXjELMAkGA1UEBhMCVVMxHTAb
# BgNVBAoTFFN5bWFudGVjIENvcnBvcmF0aW9uMTAwLgYDVQQDEydTeW1hbnRlYyBU
# aW1lIFN0YW1waW5nIFNlcnZpY2VzIENBIC0gRzIwHhcNMTIxMDE4MDAwMDAwWhcN
# MjAxMjI5MjM1OTU5WjBiMQswCQYDVQQGEwJVUzEdMBsGA1UEChMUU3ltYW50ZWMg
# Q29ycG9yYXRpb24xNDAyBgNVBAMTK1N5bWFudGVjIFRpbWUgU3RhbXBpbmcgU2Vy
# dmljZXMgU2lnbmVyIC0gRzQwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQCiYws5RLi7I6dESbsO/6HwYQpTk7CY260sD0rFbv+GPFNVDxXOBD8r/amWltm+
# YXkLW8lMhnbl4ENLIpXuwitDwZ/YaLSOQE/uhTi5EcUj8mRY8BUyb05Xoa6IpALX
# Kh7NS+HdY9UXiTJbsF6ZWqidKFAOF+6W22E7RVEdzxJWC5JH/Kuu9mY9R6xwcueS
# 51/NELnEg2SUGb0lgOHo0iKl0LoCeqF3k1tlw+4XdLxBhircCEyMkoyRLZ53RB9o
# 1qh0d9sOWzKLVoszvdljyEmdOsXF6jML0vGjG/SLvtmzV4s73gSneiKyJK4ux3DF
# vk6DJgj7C72pT5kI4RAocqrNAgMBAAGjggFXMIIBUzAMBgNVHRMBAf8EAjAAMBYG
# A1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDBzBggrBgEFBQcB
# AQRnMGUwKgYIKwYBBQUHMAGGHmh0dHA6Ly90cy1vY3NwLndzLnN5bWFudGVjLmNv
# bTA3BggrBgEFBQcwAoYraHR0cDovL3RzLWFpYS53cy5zeW1hbnRlYy5jb20vdHNz
# LWNhLWcyLmNlcjA8BgNVHR8ENTAzMDGgL6AthitodHRwOi8vdHMtY3JsLndzLnN5
# bWFudGVjLmNvbS90c3MtY2EtZzIuY3JsMCgGA1UdEQQhMB+kHTAbMRkwFwYDVQQD
# ExBUaW1lU3RhbXAtMjA0OC0yMB0GA1UdDgQWBBRGxmmjDkoUHtVM2lJjFz9eNrwN
# 5jAfBgNVHSMEGDAWgBRfmvVuXMzMdJrU3X3vP9vsTIAu3TANBgkqhkiG9w0BAQUF
# AAOCAQEAeDu0kSoATPCPYjA3eKOEJwdvGLLeJdyg1JQDqoZOJZ+aQAMc3c7jecsh
# aAbatjK0bb/0LCZjM+RJZG0N5sNnDvcFpDVsfIkWxumy37Lp3SDGcQ/NlXTctlze
# vTcfQ3jmeLXNKAQgo6rxS8SIKZEOgNER/N1cdm5PXg5FRkFuDbDqOJqxOtoJcRD8
# HHm0gHusafT9nLYMFivxf1sJPZtb4hbKE4FtAC44DagpjyzhsvRaqQGvFZwsL0kb
# 2yK7w/54lFHDhrGCiF3wPbRRoXkzKy57udwgCRNx62oZW8/opTBXLIlJP7nPf8m/
# PiJoY1OavWl0rMUdPH+S4MO8HNgEdTGCA1cwggNTAgEBMCgwFDESMBAGA1UEAwwJ
# U0NPcmNoRGV2AhAR1XrqJ493rkLXCYnbxd0ZMAkGBSsOAwIaBQCgeDAYBgorBgEE
# AYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEEMBwG
# CisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEWBBTgq4eR
# 0o7FQLF12TTM2CkIj1UfTDANBgkqhkiG9w0BAQEFAASBgDUc+NtrpZTx7FBg+5SB
# tkIJA+Mw8WPncimH2kQdHTzOpA0eRo+WWoB50cOtaHlbuCyqtN5q2I7BHKzUvdrm
# 7OcdFYhPcBpTsa6FXcP6NIY+s7//av88LIXFHrLYjX0H6viLz34bPLlzKOMsTyvL
# WNl7Xzby2DleWh+eRhKbWC7QoYICCzCCAgcGCSqGSIb3DQEJBjGCAfgwggH0AgEB
# MHIwXjELMAkGA1UEBhMCVVMxHTAbBgNVBAoTFFN5bWFudGVjIENvcnBvcmF0aW9u
# MTAwLgYDVQQDEydTeW1hbnRlYyBUaW1lIFN0YW1waW5nIFNlcnZpY2VzIENBIC0g
# RzICEA7P9DjI/r81bgTYapgbGlAwCQYFKw4DAhoFAKBdMBgGCSqGSIb3DQEJAzEL
# BgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTE1MDMxNjIyMTM0OFowIwYJKoZI
# hvcNAQkEMRYEFKKCRi5LV79bkLHQGYYvlm+x+DgbMA0GCSqGSIb3DQEBAQUABIIB
# AJxdtjtkPq4lfsCBzKGVuLHFh/a25L2KOeMP6so6USFRAWYC333wSvW1wG0lWgxD
# 6LvzHzNKVHT8DLD8Qiy423dxSGe//AuTsK2nxtirYN1k92lX7FiLbWvqbEgxQH9G
# y8P5RLUNv5TRV4/lb3iBDBr2Y7cNxZVPVAplKybBVFXu4k6Zsfp+/94DguBu78Yc
# SlOnyT2S0+PrLIB/ln+CcEXc9wDXwWX2cVZyce56IkAljii8KwdKRUL7JYsmLABE
# zzEWfEyvn9o/kkU3OBLUXFK8lOiPLBWIBCj0rHoWvtLsVScLI7hJTaT85C6Zlaff
# FELZnmlBEgR8ezZQLVeJYqc=
# SIG # End signature block
