<#
    .Synopsis
        Check the target Git Repo / Branch for any updated files
#>
Function Find-GitRepoChange
{
    Param([Parameter(Mandatory=$true) ] $Path,
          [Parameter(Mandatory=$true) ] $Branch,
          [Parameter(Mandatory=$true) ] $LastCommit)
    
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    
    # Set current directory to the git repo location
    Set-Location $Path

    $CurrentCommit = (git rev-parse --short HEAD)
    Write-Verbose -Message "Last Commit [$LastCommit] - Current Commit [$CurrentCommit]"
    
    $ReturnObj = @{ 'CurrentCommit' = $CurrentCommit;
                    'Files' = @() }

    if(-not ("$(git branch)" -match '\*\s(\w+)'))
    {
        Throw-Exception -Type 'GitTargetBranchNotFound' `
                        -Message 'git could not find any current branch' `
                        -Property @{ 'result' = $(git branch) ;
                                     'match'  = "$(git branch)" -match '\*\s(\w+)'}
    }

    if($Matches[1] -ne $Branch)
    {
        Write-Verbose -Message "Setting current branch to [$Branch]"
        try
        {
            git checkout $Branch | Out-Null
        }
        catch
        {
            if($LASTEXITCODE -ne 0)
            {
                Write-Exception -Stream Error -Exception $_
            }
            else
            {
                Write-Exception -Stream Verbose -Exception $_
            }
        }
    }

    
    $initialization = git pull
    if(-not ($initialization -eq 'Already up-to-date.'))
    {
        $ModifiedFiles = git diff --name-status (Select-FirstValid -Value $LastCommit, $null -FilterScript { $_ -ne -1 }) $CurrentCommit
        
        Foreach($File in $ModifiedFiles)
        {
            if("$($File)" -Match '([a-zA-Z])\s+(.+((\.psm1)|(\.psd1)|(\.ps1)|(\.json)))$')
            {
                $ReturnObj.Files += @{ 'FilePath' = "$($Path)\$($Matches[2])" ;
                                       'ChangeType' = $Matches[1] }
            }
        }
    }
    
    return (ConvertTo-Json $ReturnObj)
}
Export-ModuleMember -Function * -Verbose:$false