<#
    .Synopsis
#>
workflow Deploy-Integration
{
    Param($currentcommit,$repositoryname)
    
    Write-Verbose -Message "Starting [$WorkflowCommandName]"
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    Foreach($RunbookFile in (Get-ChildItem -Path ..\Runbooks -Recurse -Filter *.ps1))
    {
        Publish-SMARunbookChange -FilePath $RunbookFile.FullName -CurrentCommit $currentcommit -RepositoryName $repositoryname
    }
    Foreach($SettingsFile in (Get-ChildItem -Path ..\Runbooks -Recurse -Filter *.json))
    {
        Publish-SMASettingsFileChange -FilePath $SettingsFile.FullName -CurrentCommit $currentcommit -RepositoryName $repositoryname
    }
    Write-Verbose -Message "Finished [$WorkflowCommandName]"
}