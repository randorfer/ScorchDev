<#
.SYNOPSIS
    Examines paths for old files that match the specified criteria. The list of
    files discovered is returned.

.PARAMETER Path
    The paths that should be examined for old files.

.PARAMETER MaxAgeInDays
    The maximum age of files to keep, in days. Files that have not been modified
    at least this recently will be returned.

.PARAMETER Filter
    A file name filter that limits what files are returned. For example,
    specifying "*.ps1" would list only files whose extension is ps1.
    By default, there is no filter - all old files will be returned.

.PARAMETER Recurse
    If $True, recurse into subdirectories of the provided paths. By default,
    recursion is disabled.

.PARAMETER ComputerName
    The name of the computer to remote to in order to examine the paths. If local
    paths are specified (e.g. C:\Temp), this parameter is mandatory. May also be
    useful to limit bandwidth consumption over WAN links.

.PARAMETER CredentialName
    The name of the SMA credential to use for when searching for old files.
#>
workflow Get-OldFile
{
    param(
        [Parameter(Mandatory = $True)]  [String[]] $Path,
        [Parameter(Mandatory = $True)]  [Int] $MaxAgeInDays,
        [Parameter(Mandatory = $False)] [String] $Filter,
        [Parameter(Mandatory = $False)] [Switch] $Recurse,
        [Parameter(Mandatory = $False)] [String] $ComputerName,
        [Parameter(Mandatory = $False)] [String] $CredentialName
    )

    if(-not (Test-IsNullOrEmpty -String $CredentialName))
    {
        $Credential = Get-AutomationPSCredential -Name $CredentialName
    }
    else
    {
        $Credential = $null
    }
    $GroomableFiles = InlineScript
    {
        $Path = $Using:Path
        $Filter = $Using:Filter
        $MaxAgeInDays = $Using:MaxAgeInDays
        $Recurse = $Using:Recurse
        $ComputerName = $Using:ComputerName
        $Credential = $Using:Credential

        if($ComputerName -eq $null)
        {
            foreach($_Path in $Path)
            {
                if(-not (Test-UncPath -String $Path))
                {
                    Throw-Exception -Type 'NonUNCPathWithNullComputerName' `
                    -Message 'If a local path is provided, you must also specify a computer name' `
                    -Property @{
                        'Path' = $_Path
                    }
                }
            }
        }
        $GetChildItemParameters = @{
            'Path'  = $Path
            'File'  = $True
            'Force' = $True
            'Recurse' = $Recurse
        }
        if($Filter)
        {
            $GetChildItemParameters['Filter'] = $Filter
        }
        $InvokeCommandParameters = Get-OptionalRemotingParameter -ComputerName $ComputerName -Credential $Credential
        Invoke-Command @InvokeCommandParameters -ArgumentList $GetChildItemParameters, $MaxAgeInDays `
        -ScriptBlock `
        {
            $GetChildItemParameters, $MaxAgeInDays = $Args
            $OldestDate = (Get-Date).AddDays([Math]::Abs($MaxAgeInDays) * -1)
            Get-ChildItem @GetChildItemParameters | Where-Object -FilterScript {
                $_.LastWriteTime -lt $OldestDate 
            }
        }
    }
    return $GroomableFiles
}
