<#
    .Synopsis
        Check the target Git Repo / Branch for any updated files. 
        Ingores files in the root        
#>
Function Find-GitRepoChange
{
    Param([Parameter(Mandatory=$true) ] $Path,
          [Parameter(Mandatory=$true) ] $Branch,
          [Parameter(Mandatory=$true) ] $CurrentCommit)
    
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    
    # Set current directory to the git repo location
    Set-Location $Path
      
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

    
    try
    {
        $initialization = git pull
    }
    catch
    {
        if($LASTEXITCODE -ne -1)
        {
            Write-Exception -Stream Error -Exception $_
        }
        else
        {
            Write-Exception -Stream Verbose -Exception $_
        }
    }
    $NewCommit = (git rev-parse --short HEAD)
    $ModifiedFiles = git diff --name-status (Select-FirstValid -Value $CurrentCommit, $null -FilterScript { $_ -ne -1 }) $NewCommit
    $ReturnObj = @{ 'CurrentCommit' = $NewCommit ; 'Files' = @() }
    Foreach($File in $ModifiedFiles)
    {
        if("$($File)" -Match '([a-zA-Z])\s+(.+\/([^\./]+(\..+)))$')
        {
            $ReturnObj.Files += @{ 'FullPath' = "$($Path)\$($Matches[2].Replace('/','\'))" ;
                                   'FileName' = $Matches[3] ;
                                   'FileExtension' = $Matches[4].ToLower()
                                   'ChangeType' = $Matches[1] }
        }
    }
    
    return (ConvertTo-Json $ReturnObj)
}
Export-ModuleMember -Function * -Verbose:$false