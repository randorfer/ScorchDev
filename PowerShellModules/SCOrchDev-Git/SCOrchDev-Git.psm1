<#
    .Synopsis
        Check the target Git Repo / Branch for any updated files
#>
Function Find-GitRepoChange
{
    Param([Parameter(Mandatory=$true) ] $Path,
          [Parameter(Mandatory=$true) ] $Branch,
          [Parameter(Mandatory=$true) ] $CurrentCommit)
    
    $ErrorActionPreference = 'Continue'

    $ReturnObj = @{'Status' = 'No Change'}

    # Set Location to the target repo and initialize
    Set-Location $Path

    if(-not "$(git branch)" -match '\*\s(\w+)')
    {
        Throw-Exception -Type 'git error' `
                        -Message 'git could not find any current branch' `
                        -Property @{ 'result' = $(git branch) ;
                                     'match'  = "$(git branch)" -match '\*\s(\w+)'}
    }

    if($Matches[1] -eq $Branch)
    {
        Write-Verbose -Message "Setting current branch to [$Branch]"
        git checkout $Branch
        if($LASTEXITCODE -ne 0)
        {
            Write-Exception -Stream Error -Exception $_
        }
        else
        {
            Write-Exception -Stream Verbose -Exception $_
        }
    }

    
    $initialization = git fetch
    if((git status) -match 'Your branch is behind')
    {
        $update = git pull
        $ModifiedFiles = git diff --name-status $CurrentCommit (git rev-parse HEAD)
        
        $Files = @()
        Foreach($File in $ModifiedFiles)
        {
            if("$($File)" -Match '([a-zA-Z])\s+(.+((\.psm1)|(\.psd1)|(\.ps1)|(\.json)))$')
            {
                $Files += @{ 'FilePath' = "$($Path)\$($Matches[2])" ;
                             'ChangeType' = $Matches[1] }
            }
        }
    }
        
    $Files = ConvertTo-Json -InputObject $Files
    return $Files
}
Export-ModuleMember -Function * -Verbose:$false