<#
    .SYNOPSIS
        Imports a PowerShell module into SMA and deploys it to the local file system
        of the all runbook workers
    
    .Description
        Check local repository for PowerShell module. If this is a newer version deploy
            1. Local file system deploy
                1. Copy to network share
                2. Run command to copy file from network share to each runbook worker in environment
                3. Validate module path
            2. SMA Deployment
                1. Create Zip file in local temp directory
                2. Import Zip file
                3. Cleanup
        
    .PARAMETER ModuleDefinitionFilePath
        The path to the PowerShell Module definition file (psd1)
    
    .PARAMETER RepositoryName
        The name of the repository that this module is being sourced from

    
#>
Workflow Publish-SmaPowerShellModule
{
    Param( [Parameter(Mandatory=$true) ][string] $ModuleDefinitionFilePath,
           [Parameter(Mandatory=$true) ][string] $RepositoryName)
    
    Write-Verbose -Message "Starting [$WorkflowCommandName] for [$ModuleDefinitionFilePath]"


    Write-Verbose -Message "Finished [$WorkflowCommandName] for [$ModuleDefinitionFilePath]"
}