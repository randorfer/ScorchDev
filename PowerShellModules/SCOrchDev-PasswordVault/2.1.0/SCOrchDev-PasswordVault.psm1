<#
.Synopsis
    Returns credential objects from the local password vault

.Parameter UserName
    The name of the credential to return. Case sensative

.Parameter Resource
    The resource store this credential is stored in

.Parameter AsPSCredential
    Use this flag if you would like to retrieve a PSCredential Type object

.Example
    Get-PasswordVaultCredential

.Example
    Get-PasswordVaultCredential -Name 'SCOrchDev\SMA'

.Example
    Get-PasswordVaultCredential -Name 'SCOrchDev\SMA' -Resource 'LocalDev'

.Example
    Get-PasswordVaultCredential -Name 'SCOrchDev\SMA' -Resource 'LocalDev' -WithPassword
#>
Function Get-PasswordVaultCredential
{
    Param(
        [Parameter(
            Mandatory = $False,
            ValueFromPipeline = $True,
            Position = 0)]
        [AllowNull()]
        [string]
        $UserName = $null,

        [Parameter(
            Mandatory = $False,
            ValueFromPipeline = $True,
            Position = 1
        )]
        [AllowNull()]
        [string]
        $Resource = $null,

        [Parameter(
            Mandatory = $False,
            ValueFromPipeline = $True,
            Position= 2
        )]
        [Switch]
        $AsPSCredential
    )
    try
    {
        [void][Windows.Security.Credentials.PasswordVault,Windows.Security.Credentials,ContentType=WindowsRuntime]
        $PasswordVault = New-Object -TypeName Windows.Security.Credentials.PasswordVault
        if($UserName -and $Resource)
        {
            $Credential = $PasswordVault.Retrieve($Resource,$UserName)
        }
        elseif($UserName)
        {
            $Credential = $PasswordVault.FindAllByUserName($UserName)
        }
        elseif($Resource)
        {
            $Credential = $PasswordVault.FindAllByResource($Resource)
        }
        else
        {
            $Credential = $PasswordVault.RetrieveAll()
        }

        if($AsPSCredential.IsPresent)
        {
            $Credential | ForEach-Object { 
                $_.RetrievePassword(); 
                $SecurePassword = $_.Password | ConvertTo-SecureString -AsPlainText -Force
                New-Object -TypeName pscredential -ArgumentList $_.UserName, $SecurePassword
            }
        }
        else
        {
            $Credential
        }
    }
    catch
    {
        $ExceptionInfo = Get-ExceptionInfo -Exception $_
        $ExceptionProperties = @{
            'ErrorMessage' = (Convert-ExceptionToString -Exception $_) ;
            'UserName' = $UserName ;
            'Resource' = $Resource ;
            'AsPSCredential' = $AsPSCredential.IsPresent
        }
        Switch -CaseSensitive ($ExceptionInfo.Type)
        {
            'System.Management.Automation.RuntimeException'
            {
                $Type = 'TypeNotFound'
                $Message = 'Could not load Password Vault libraries.'
            }
            'System.Management.Automation.MethodInvocationException'
            {
                $Type = 'CredentialNotFound'
                $Message = 'Could not find Credential in Password Vault.'
            }
            default
            {
                $Type = 'UnknownPasswordVaultException'
                $Message = 'Encountered an unexpected error'
            }
        }
        Throw-Exception -Type $Type `
                        -Message $Message `
                        -Property $ExceptionProperties
    }
}
<#
.Synopsis
    Sets or Creates a new Password Vault Credential

.Parameter UserName
    The username to store

.Parameter Resource
    The Resouce store to place the credential in

.Parameter Password
    Password of the credential

.Example
    Set-PasswordVaultCredential -Name 'SCOrchDev\SMA' -Resource 'LocalDev' -Password 'P@55W0Rd'
#>
Function Set-PasswordVaultCredential
{
    Param(
        [Parameter(
            Mandatory = $True,
            ValueFromPipeline = $True,
            Position = 0
        )]
        [pscredential]
        $Credential,

        [Parameter(
            Mandatory = $False,
            ValueFromPipeline = $True,
            Position = 1
        )]
        [string]
        $Resource = ([guid]::NewGuid()) -as [string]
    )
    try
    {
        [void][Windows.Security.Credentials.PasswordVault,Windows.Security.Credentials,ContentType=WindowsRuntime]
        $PasswordVault = New-Object -TypeName Windows.Security.Credentials.PasswordVault
    
        $VaultCredential = New-Object -TypeName Windows.Security.Credentials.PasswordCredential
        $VaultCredential.UserName = $Credential.UserName
        $VaultCredential.Resource = $Resource
        $VaultCredential.Password = $Credential.GetNetworkCredential().Password

        $PasswordVault.Add($VaultCredential)
    }
    catch
    {
        $ExceptionInfo = Get-ExceptionInfo -Exception $_
        $ExceptionProperties = @{
            'ErrorMessage' = (Convert-ExceptionToString -Exception $_) ;
            'UserName' = $UserName ;
            'Resource' = $Resource ;
        }
        Switch -CaseSensitive ($ExceptionInfo.Type)
        {
            'System.Management.Automation.RuntimeException'
            {
                $Type = 'TypeNotFound'
                $Message = 'Could not load Password Vault libraries.'
            }
            default
            {
                $Type = 'UnknownPasswordVaultException'
                $Message = 'Encountered an unexpected error'
            }
        }
        Throw-Exception -Type $Type `
                        -Message $Message `
                        -Property $ExceptionProperties
    }
}
<#
.Synopsis
    Removes a credental from the password vault

.Parameter UserName
    The username to to remove

.Parameter Resource
    The resource container to remove from

.Example
    # Remove all Password Vault Credentials
    Remove-PasswordVaultCredential

.Example
    # Remove all Password Vault Credentials Named SCOrchDev\SMA
    Remove-PasswordVaultCredential -UserName 'SCOrchDev\SMA'

.Example
    # Remove all Password Vault Credentials from LocalDev resource
    Remove-PasswordVaultCredential -Resource 'LocalDev'

.Example
    # Remove all Password Vault Credentials from LocalDev resource named SCOrchDev\SMA
    Remove-PasswordVaultCredential -Resource 'LocalDev' -UserName 'SCOrchDev\SMA'
#>
Function Remove-PasswordVaultCredential
{
    Param(
        [Parameter(
            Mandatory = $False, 
            ValueFromPipeline = $True,
            Position = 0
        )]
        [AllowNull()]
        [string]
        $UserName = $null,

        [Parameter(
            Mandatory = $False, 
            ValueFromPipelineByPropertyName = $True,
            Position = 1
        )]
        [AllowNull()]
        [string]
        $Resource = $null
    )
    try
    {
        [void][Windows.Security.Credentials.PasswordVault,Windows.Security.Credentials,ContentType=WindowsRuntime]
        $PasswordVault = New-Object -TypeName Windows.Security.Credentials.PasswordVault
        $Parameters = @{ 
            'UserName' = $UserName ;
            'Resource' = $Resource ;
        }              
        Get-PasswordVaultCredential @Parameters | ForEach-Object { $PasswordVault.Remove($_) }
    }
    catch
    {
        $ExceptionInfo = Get-ExceptionInfo -Exception $_
        $ExceptionProperties = @{
            'ErrorMessage' = (Convert-ExceptionToString -Exception $_) ;
            'UserName' = $UserName ;
            'Resource' = $Resource ;
        }
        Switch -CaseSensitive ($ExceptionInfo.Type)
        {
            'System.Management.Automation.RuntimeException'
            {
                $Type = 'TypeNotFound'
                $Message = 'Could not load Password Vault libraries.'
            }
            default
            {
                $Type = 'UnknownPasswordVaultException'
                $Message = 'Encountered an unexpected error'
            }
        }
        Throw-Exception -Type $Type `
                        -Message $Message `
                        -Property $ExceptionProperties
    }
}
