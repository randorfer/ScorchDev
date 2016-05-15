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
        [ValidateSet('Present','Absent')]
        [System.String]
        $Ensure
    )
    
    $RepositoryPath = $Repository.Split('/')[-1]
    if($RepositoryPath -like '*.git')
    {
        $RepositoryPath = $RepositoryPath.Substring(0,$RepositoryPath.Length-4)
    }
    if (Test-Path -Path "$($BaseDirectory)\$($RepositoryPath)\.git")
    {
        $Ensure = 'Present'
    }
    else
    {
        $Ensure = 'Absent'
    }

    Return @{
        'BaseDirectory' = $BaseDirectory
        'Repository' = $Repository
        'Ensure' = $Ensure
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
        [ValidateSet("Present","Absent")]
        [System.String]
        $Ensure
    )

    $ErrorActionPreference = 'Stop'

    $StartingDir = (pwd).Path
    Try
    {
        Set-Location -Path $BaseDirectory
        $EAPHolder = $ErrorActionPreference
        $ErrorActionPreference = 'SilentlyContinue'
        git clone $Repository --recursive
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]$EAPHolder
    }
    Catch { throw }
    Finally { Set-Location -Path $StartingDir }
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
        [ValidateSet("Present","Absent")]
        [System.String]
        $Ensure
    )

    $Status = Get-TargetResource -BaseDirectory $BaseDirectory -Repository $Repository -Ensure $Ensure

    Return ($Ensure -eq $Status.Ensure) -as [bool]
}
Export-ModuleMember -Function Test-TargetResource -Verbose:$false

