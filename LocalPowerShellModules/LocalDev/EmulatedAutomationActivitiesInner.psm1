$SmaWebServiceDetails = @{
    'WebServiceEndpoint' = 'https://scorchsma01.scorchdev.com'
    'Port'             = 9090
    'AuthenticationType' = 'Windows'
}


# Uncomment this section and fill in $CredUsername and $CredPassword values
# to talk to SMA using Basic Auth instead of Windows Auth

# username / password of an account with access to the SMA Web Service
$CredUsername = 'scorchdev\sma'
$CredPassword = 'TechEd_2014'
    
$SecurePassword = $CredPassword | ConvertTo-SecureString -AsPlainText -Force
   
$SmaWebServiceDetails.AuthenticationType = 'Basic'
$SmaWebServiceDetails.Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ($CredUsername, $SecurePassword)


function Get-AutomationAsset 
{
    param(
        [Parameter(Mandatory = $True)]
        [ValidateSet('Variable', 'Certificate', 'PSCredential', 'Connection')]
        [string] $Type,

        [Parameter(Mandatory = $True)]
        [string]$Name
    )

    $MaxSecondsToWaitOnJobCompletion = 600
    $SleepTime = 5
    $DoneJobStatuses = @('Completed', 'Failed', 'Stopped', 'Blocked', 'Suspended')

    # Call Get-AutomationAsset runbook in SMA to get the asset value in serialized form
    $Params = @{
        'Type' = $Type
        'Name' = $Name
    }

    $Job = Start-SmaRunbook -Name 'Get-AutomationAsset' -Parameters $Params @SmaWebServiceDetails

    if(!$Job) 
    {
        Write-Error -Message "Unable to start the 'Get-AutomationAsset' runbook. Make sure it exists and is published in SMA."
    }
    else 
    {
        # Wait for Get-AutomationAsset completion
        $TotalSeconds = 0
        $JobInfo = $null

        do 
        {
            Start-Sleep -Seconds $SleepTime
            $TotalSeconds += $SleepTime

            $JobInfo = Get-SmaJob -Id $Job @SmaWebServiceDetails
        }
        while((!$DoneJobStatuses.Contains($JobInfo.JobStatus)) -and ($TotalSeconds -lt $MaxSecondsToWaitOnJobCompletion))

        if($TotalSeconds -ge $MaxSecondsToWaitOnJobCompletion) 
        {
            Write-Error -Message "Timeout exceeded. 'Get-AutomationAsset' job $Job did not complete in $MaxSecondsToWaitOnJobCompletion seconds."
        }
        elseif($JobInfo.JobException) 
        {
            Write-Error ("'Get-AutomationAsset' job $Job threw exception: `n" + $JobInfo.JobException)
        }
        else 
        {
            $SerializedOutput = Get-SmaJobOutput -Id $Job -Stream Output @SmaWebServiceDetails
            
            $Output = [System.Management.Automation.PSSerializer]::Deserialize($SerializedOutput.StreamText)  

            $Output
        }
    }
}

function Get-AutomationConnection 
{
    param(
        [Parameter(Mandatory = $True)]
        [string] $Name
    )

    Get-AutomationAsset -Type Connection -Name $Name
}

function Set-AutomationVariable 
{
    param(
        [Parameter(Mandatory = $True)]
        [string] $Name,

        [Parameter(Mandatory = $True)]
        [object] $Value
    )

    $Variable = Get-SmaVariable -Name $Name @SmaWebServiceDetails

    if($Variable) 
    {
        if($Variable.IsEncrypted) 
        {
            $Output = Set-SmaVariable -Name $Name -Value $Value -Encrypted @SmaWebServiceDetails
        }
        else 
        {
            $Output = Set-SmaVariable -Name $Name -Value $Value -Force @SmaWebServiceDetails
        }
    }
}

function Get-AutomationCertificate 
{
    param(
        [Parameter(Mandatory = $True)]
        [string] $Name
    )

    $Thumbprint = Get-AutomationAsset -Type Certificate -Name $Name
    
    if($Thumbprint) 
    {
        $Cert = Get-Item -Path "Cert:\CurrentUser\My\$Thumbprint"

        $Cert
    }
}
