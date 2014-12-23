<#
    .Synopsis
        Check the target Git Repo / Branch for any updated files
#>
Workflow Find-GitRepoChange
{
    Param([Parameter(Mandatory=$true) ] $Path,
          [Parameter(Mandatory=$true) ] $Branch,
          [Parameter(Mandatory=$false)] $WebserviceEndpoint = 'https://localhost')
    
    Write-Verbose -Message "Starting [$WorkflowCommandName]"

    $ErrorActionPreference = 'Stop'

    $ReturnJSON = inlinescript
    {
        $Path   = $Using:Path
        $Branch = $Using:Branch

        $ReturnObj = @{'Status' = 'No Change'}

        # Set Location to the target repo and initialize
        Set-Location $Path

        if(-not ((git branch) -contains "* $Branch"))
        {
            Write-Verbose -Message "Setting current branch to [$Branch]"
            try
            {
                git checkout $Branch
            }
            catch
            {
                if(ConvertTo-Boolean $LASTEXITCODE)
                {
                    Throw-Exception -ExceptionInfo $_
                }
                else
                {
                    Write-Exception -Stream Verbose -Exception $_
                }
            }
        }
        else
        {
            Write-Verbose -Message "Branch already set to [$Branch]"
        }

        # Check status
        $ErrorActionPreference = 'Continue'
        $initialization = (git fetch) 2> $null
        if((git status) -match 'Your branch is behind')
        {
            $update = (git pull) 2> $null
            $Modifications = (git show) 2> $null

            $Files = @()
            for($i = 0 ; $i -lt $Modifications.count ; $i+=1)
            {
                if($Modifications[$i] -match 'diff')
                {
                    $File = @{ 'FilePath' = "$Path\$($Modifications[$i].Substring(13).Split(' ')[0].Replace('/','\'))" ;
                               'ChangeType' = "$($Modifications[$i+1].Split(' ')[0])" }
                    $Files += $File

                }
            }
        }
        $ErrorActionPreference = 'Stop'
        
        if($Files) 
        { 
            $ReturnObj.Status = 'Updates'
            $ReturnObj.Add('File', $Files) 
        }

        return (ConvertTo-Json -InputObject $ReturnObj)
    }
        
    Write-Verbose -Message "`$ReturnJSON [$ReturnJSON]"
    Write-Verbose -Message "Finished [$WorkflowCommandName]"
    return $ReturnJSON
}