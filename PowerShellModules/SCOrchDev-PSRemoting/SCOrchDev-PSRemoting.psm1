<#
.SYNOPSIS
    Enables PowerShell Remoting on a remote computer. Requires that the machine
    responds to WMI requests, and that its operating system is Windows Vista or
    later.

    Adapted from http://www.davidaiken.com/2011/01/12/enable-powershell-remoting-on-windows-azure/
    From Windows PowerShell Cookbook (O'Reilly)
    by Lee Holmes (http://www.leeholmes.com/guide)

.Parameter Computername
    The name of the computer to enable PSRemoting on

.Parameter Credential
    The Credential to use when connecting to the remote computer
          
.EXAMPLE
    Enable-RemotePsRemoting -ComputerName <Computer> -Credential <Credential>
#>
Function Enable-RemotePsRemoting
{
    Param(
        [Parameter(Mandatory = $True)]
        [String]
        $Computername,
    
        [Parameter(Mandatory = $True)]
        [PSCredential]
        $Credential
    )

    Set-StrictMode -Version Latest
    $VerbosePreference = [System.Management.Automation.ActionPreference]::Continue

    $username = $Credential.Username
    $password = $Credential.GetNetworkCredential().Password
    $script = @"
`$log = Join-Path `$env:TEMP Enable-RemotePsRemoting.output.txt
Remove-Item -Force `$log -ErrorAction SilentlyContinue
Start-Transcript -Path `$log

## Create a task that will run with full network privileges.
## In this task, we call Enable-PsRemoting

schtasks /CREATE /TN 'Enable Remoting' /SC WEEKLY /RL HIGHEST ``
         /RU $username /RP $password ``
         /TR "powershell -noprofile -command Enable-PsRemoting -Force" /F |
         Out-String

schtasks /RUN /TN 'Enable Remoting' | Out-String
`$securePass = ConvertTo-SecureString $password -AsPlainText -Force
`$credential = New-Object Management.Automation.PsCredential $username,`$securepass

## Wait for the remoting changes to come into effect
for(`$count = 1; `$count -le 10; `$count++)
{
    `$output = Invoke-Command localhost { 1 } -Cred `$credential ``
                              -ErrorAction SilentlyContinue
    if(`$output -eq 1) { break; }

    "Attempt `$count : Not ready yet."
    Sleep 5
}

## Delete the temporary task
schtasks /DELETE /TN 'Enable Remoting' /F | Out-String
Stop-Transcript
"@

    $commandBytes = [System.Text.Encoding]::Unicode.GetBytes($script)
    $encoded = [Convert]::ToBase64String($commandBytes)

    Write-Verbose -Message "Configuring $Computername"
    $command = "powershell -NoProfile -EncodedCommand $encoded"
    $Null = Invoke-WmiMethod -ComputerName $Computername -Credential $Credential `
    Win32_Process Create -Args $command
    Write-Verbose -Message 'Testing connection'

    $attempts = 0
    do
    {
        try 
        {
            $output = Invoke-Command $Computername {
                Get-WmiObject -Class Win32_ComputerSystem 
            } -Credential $Credential
            $status = 'Success'
        }
        catch
        {
            if($attempts -ge 10)
            {
                Throw-Exception -Type 'FailedToConfigurePSRemoting' `
                                -Message 'Failed to configure PS remoting on the target box' `
                                -Property @{
                    'ComputerName' = $Computername
                    'Credential' = $Credential.UserName
                    'ErrorMessage' = Convert-ExceptionToString -Exception $_
                }
            }
            else
            {
                Write-Verbose -Message 'Not yet configured'
                $attempts = $attempts + 1
                Start-Sleep -Seconds 5
            }
            $status = 'Failure'
        }
    }
    while($status -ne 'Success')
    Write-Verbose -Message 'Success'
}
<#
.SYNOPSIS
    Returns a hashtable containing parameters to be passed it Invoke-Command if you
    want to optionally perform remoting.

.DESCRIPTION
    Returns parameters suitable for passing to Invoke-Command that will optionally
    perform PowerShell remoting.

    If $ComputerName and $Credential are $null, no remoting will be performed. If
    only $ComputerName is $null, Get-RemotingComputer will be be called to retrieve
    an acceptable computer to use for "local" remoting.

.PARAMETER ComputerName
    The name of the computer to remote to.

.PARAMETER Credential
    The credential to use for remoting.

.PARAMETER Authentication
    The authentication mechanism to use with the credential.
#>
Function Get-OptionalRemotingParameter
{
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $False)]
        [String] 
        $Computername,

        [Parameter(Mandatory = $False)]
        [PSCredential]
        $Credential,

        [Parameter(Mandatory = $False)]
        [ValidateSet('Basic','Credssp', 'Default', 'Digest', 'Kerberos', 'Negotiate', 'NegotiateWithImplicitCredential')]
        [String]
        $Authentication = 'CredSSP'
    )

    $InvokeCommandParameters = @{}
    if(-not (Test-IsNullOrEmpty -String $Computername))
    {
        $InvokeCommandParameters['ComputerName'] = $Computername
    }
    if($Credential -ne $Null)
    {
        $InvokeCommandParameters['Credential'] = $Credential
        $InvokeCommandParameters['Authentication'] = $Authentication
        # If a credential is provided, we must specify a computer name.
        if($InvokeCommandParameters['ComputerName'] -eq $Null)
        {
            $InvokeCommandParameters['ComputerName'] = 'localhost'
        }
    }
    return $InvokeCommandParameters
}