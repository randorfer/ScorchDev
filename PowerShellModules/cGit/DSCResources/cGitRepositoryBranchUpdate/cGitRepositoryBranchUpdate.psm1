function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param (
        [parameter(Mandatory = $true)]
        [System.String]
        $BaseDirectory,

        [parameter(Mandatory = $true)]
        [System.String]
        $Repository,

        [parameter(Mandatory = $true)]
        [System.String]
        $Branch
    )
    
    Return @{
        'BaseDirectory' = $BaseDirectory
        'Repository' = $Repository
        'Branch' = $Branch
    }
}
Export-ModuleMember -Function Get-TargetResource -Verbose:$false


function Set-TargetResource
{
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true)]
        [System.String]
        $BaseDirectory,

        [parameter(Mandatory = $true)]
        [System.String]
        $Repository,

        [parameter(Mandatory = $true)]
        [System.String]
        $Branch
    )
}
Export-ModuleMember -Function Set-TargetResource -Verbose:$false


function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param (
        [parameter(Mandatory = $true)]
        [System.String]
        $BaseDirectory,

        [parameter(Mandatory = $true)]
        [System.String]
        $Repository,

        [parameter(Mandatory = $true)]
        [System.String]
        $Branch
    )
    
    $RepositoryPath = $Repository.Split('/')[-1]
    if($RepositoryPath -like '*.git')
    {
        $RepositoryPath = $RepositoryPath.Substring(0,$RepositoryPath.Length-4)
    }
    $StartingDir = (pwd).Path
    Try
    {
        Set-Location -Path "$($BaseDirectory)\$($RepositoryPath)"
        $EAPHolder = $ErrorActionPreference
        $ErrorActionPreference = 'SilentlyContinue'
        $Null = git fetch
        $Null = git reset --hard origin/$Branch
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]$EAPHolder
    }
    Catch { throw }
    Finally { Set-Location -Path $StartingDir }

    Return $True
}
Export-ModuleMember -Function Test-TargetResource -Verbose:$false

