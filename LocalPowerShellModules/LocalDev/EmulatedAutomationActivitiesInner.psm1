$SmaWebServiceDetails = @{
    "WebServiceEndpoint" = "https://mgoapsmad1";
    "Port" = 9090;
    "AuthenticationType" = "Windows";
}

<#
    # Uncomment this section and fill in $CredUsername and $CredPassword values
    # to talk to SMA using Basic Auth instead of Windows Auth

    # username / password of an account with access to the SMA Web Service
    $CredUsername = "FILL ME IN"
    $CredPassword = "FILL ME IN"
    
    $SecurePassword = $CredPassword | ConvertTo-SecureString -asPlainText -Force
   
    $SmaWebServiceDetails.AuthenticationType = "Basic"
    $SmaWebServiceDetails.Credential = New-Object System.Management.Automation.PSCredential($CredUsername,$SecurePassword)
#>

function Get-AutomationAsset {
    param(
        [Parameter(Mandatory=$True)]
        [ValidateSet('Variable', 'Certificate', 'PSCredential', 'Connection')]
        [string] $Type,

        [Parameter(Mandatory=$True)]
        [string]$Name
    )

    $MaxSecondsToWaitOnJobCompletion = 600
    $SleepTime = 5
    $DoneJobStatuses = @("Completed", "Failed", "Stopped", "Blocked", "Suspended")

    # Call Get-AutomationAsset runbook in SMA to get the asset value in serialized form
    $Params = @{
        "Type" = $Type;
        "Name" = $Name
    }

    $Job = Start-SmaRunbook -Name "Get-AutomationAsset" -Parameters $Params @SmaWebServiceDetails

    if(!$Job) {
        Write-Error "Unable to start the 'Get-AutomationAsset' runbook. Make sure it exists and is published in SMA."
    }
    else {
        # Wait for Get-AutomationAsset completion
        $TotalSeconds = 0
        $JobInfo = $null

        do {
            Start-Sleep -Seconds $SleepTime
            $TotalSeconds += $SleepTime

            $JobInfo = Get-SmaJob -Id $Job @SmaWebServiceDetails
        } while((!$DoneJobStatuses.Contains($JobInfo.JobStatus)) -and ($TotalSeconds -lt $MaxSecondsToWaitOnJobCompletion))

        if($TotalSeconds -ge $MaxSecondsToWaitOnJobCompletion) {
            Write-Error "Timeout exceeded. 'Get-AutomationAsset' job $Job did not complete in $MaxSecondsToWaitOnJobCompletion seconds."
        }
        elseif($JobInfo.JobException) {
            Write-Error ("'Get-AutomationAsset' job $Job threw exception: `n" + $JobInfo.JobException)
        }
        else {
            $SerializedOutput = Get-SmaJobOutput -Id $Job -Stream Output @SmaWebServiceDetails
            
            $Output = [System.Management.Automation.PSSerializer]::Deserialize($SerializedOutput.StreamText)  

            $Output
        }
    }
}

function Get-AutomationConnection {
    param(
        [Parameter(Mandatory=$true)]
        [string] $Name
    )

    Get-AutomationAsset -Type Connection -Name $Name
}

function Set-AutomationVariable {
    param(
        [Parameter(Mandatory=$true)]
        [string] $Name,

        [Parameter(Mandatory=$true)]
        [object] $Value
    )

    $Variable = Get-SmaVariable -Name $Name @SmaWebServiceDetails

     if($Variable) {
        if($Variable.IsEncrypted) {
            $output = Set-SmaVariable -Name $Name -Value $Value -Encrypted @SmaWebServiceDetails
        }
        else {
            $output = Set-SmaVariable -Name $Name -Value $Value -Force @SmaWebServiceDetails
        }
     }

}

function Get-AutomationCertificate {
    param(
        [Parameter(Mandatory=$true)]
        [string] $Name
    )

    $Thumbprint = Get-AutomationAsset -Type Certificate -Name $Name
    
    if($Thumbprint) {
        $Cert = Get-Item "Cert:\CurrentUser\My\$Thumbprint"

        $Cert
    }
}