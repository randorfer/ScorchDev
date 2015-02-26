<#
.SYNOPSIS
    Gets one or credentials using Get-AutomationPSCredential.

.DESCRIPTION
    Get-BatchAutomationPSCredential takes a hashtable which maps a friendly name to
    a credential name. Each credential in the hashtable will be retrieved using
    Get-AutomationPSCredential, will be accessible by its friendly name via the
    returned object.

.PARAMETER Alias
    A hashtable mapping credential friendly names to a name passed to Get-AutomationPSCredential.

.EXAMPLE
    PS > $Creds = Get-BatchAutomationPSCredential -Alias @{'TestCred' = 'GENMILLS\M3IS052'; 'TestCred2' = 'GENMILLS\M2IS254'}

    PS > $Creds.TestCred


    PSComputerName        : localhost
    PSSourceJobInstanceId : e2d9e9dc-2740-49ef-87d6-34e3334324e4
    UserName              : GENMILLS\M3IS052
    Password              : System.Security.SecureString

    PS > $Creds.TestCred2


    PSComputerName        : localhost
    PSSourceJobInstanceId : 383da6c1-03f7-4b74-afc6-30e901972a5e
    UserName              : GENMILLS.com\M2IS254
    Password              : System.Security.SecureString
#>
workflow Get-BatchAutomationPSCredential
{
    param(
        [Parameter(Mandatory=$True)] [Hashtable] $Alias
    )
    $Creds = New-Object -TypeName 'PSObject'
    foreach($Key in $Alias.Keys)
    {
        $Cred = Get-AutomationPSCredential -Name $Alias[$Key]
        Add-Member -InputObject $Creds -Name $Key -Value $Cred -MemberType NoteProperty
        Write-Verbose -Message "Credential [$($Key)] = [$($Alias[$Key])]"
    }
    return $Creds
}