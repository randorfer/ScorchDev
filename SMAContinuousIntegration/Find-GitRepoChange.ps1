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

    inlinescript
    {
        $Path   = $Using:Path
        $Branch = $Using:Branch

        # Set Location to the target repo and initialize
        Set-Location $Path
        $ErrorActionPreference = 'Continue'
        $initialization = (git init) 2> $null
        $ErrorActionPreference = 'Stop'

        if(-not ((git branch) -contains "* $Branch"))
        {
            Write-Verbose -Message "Setting current branch to [$Branch]"
            $ErrorActionPreference = 'Continue'
            $output = (git checkout $Branch) 2> $null
            $ErrorActionPreference = 'Stop'
        }
        else
        {
            Write-Verbose -Message "Branch already set to [$Branch]"
        }
    }

    Write-Verbose -Message "Finished [$WorkflowCommandName]"
}