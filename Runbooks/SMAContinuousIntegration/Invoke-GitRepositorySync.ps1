﻿<#
    .Synopsis
        Check GIT repository for new commits. If found sync the changes into
        the current SMA environment

    .Parameter Path
        The path to the root of the Git Repository

    .Parameter Branch
        The branch of the repository to syncronize this SMA environment with

    .Parameter RunbookFolder
        The relative path from the repository root that will contain all all
        runbook files

    .Parameter PowerShellModuleFolder
        The relative path from the repository root that will contain all all
        PowerShell module folders
#>
Workflow Invoke-GitRepositorySync
{
    Param([Parameter(Mandatory=$true)][String] $Path)
    
    Write-Verbose -Message "Starting [$WorkflowCommandName]"
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    $CIVariables = Get-BatchAutomationVariable -Name @('RepositoryInformation',
                                                       'SMACredName',
                                                       'WebserviceEndpoint'
                                                       'WebservicePort') `
                                               -Prefix 'SMAContinuousIntegration'
    $SMACred = Get-AutomationPSCredential -Name $CIVariables.SMACredName
    Try
    {
        $RepositoryInformation = (ConvertFrom-Json $CIVariables.RepositoryInformation)."$Path"
        Write-Verbose -Message "`$RepositoryInformation [$(ConvertTo-JSON $RepositoryInformation)]"

        $RepoChangeJSON = Find-GitRepoChange -Path $Path `
                                             -Branch $RepositoryInformation.Branch `
                                             -CurrentCommit $RepositoryInformation.CurrentCommit

        $RepoChange = ConvertFrom-JSON -InputObject $RepoChangeJSON
        if($RepoChange.CurrentCommit -ne $RepositoryInformation.CurrentCommit)
        {
            Write-Verbose -Message "Processing [$($RepositoryInformation.CurrentCommit)..$($RepoChange.CurrentCommit)]"
            
            $ProcessedWorkflows = @()
            $ProcessedSettingsFiles = @()
            $ProcessedPowerShellModules = @()
            
            $CleanupOrphanRunbooks = $False
            $CleanupOrphanAssets = $False

            # Only Process the file 1 time per set. Sort by change type so Adds get
            # Priority over deletes. Sorts .ps1 files before .json files
            Foreach($File in ($RepoChange.Files | Sort-Object ChangeType |Sort-Object FileExtension -Descending))
            {
                Write-Verbose -Message "[$($File.FileName)] Starting Processing"
                # Process files in the runbooks folder
                if($File.FullPath -like "$Path\$($RepositoryInformation.RunbookFolder)\*")
                {
                    Switch -CaseSensitive ($File.FileExtension)
                    {
                        '.ps1'
                        {   
                            if($ProcessedWorkflows -notcontains $File.FileName)
                            {
                                $ProcessedWorkflows += $File.FileName
                                Switch -CaseSensitive ($File.FileExtension)
                                {
                                    "D"
                                    {
                                        $CleanupOrphanRunbooks = $True
                                    }
                                    Default
                                    {
                                        Publish-SMARunbookChange -FilePath $File.FullPath `
                                                                 -CurrentCommit $RepoChange.CurrentCommit
                                    }
                                }
                            }
                            else
                            {
                                Write-Verbose -Message "Skipping [$(ConvertTo-Json $File)]. File already processed in changeset"
                            }
                        }
                        '.json'
                        {
                            if($ProcessedSettingsFiles -notcontains $File.FileName)
                            {
                                $ProcessedSettingsFiles += $File.FileName
                                Switch -CaseSensitive ($File.FileExtension)
                                {
                                    "D"
                                    {
                                        $CleanupOrphanAssets = $true
                                    }
                                    Default
                                    {
                                        Publish-SMASettingsFileChange -FilePath $File.FullPath
                                    }
                                }
                            }
                            else
                            {
                                Write-Verbose -Message "Skipping [$(ConvertTo-Json $File)]. File already processed in changeset"
                            }
                        }
                        default
                        {
                            Write-Verbose -Message "[$($File.FileName)] is not a supported file type for the runbooks folder (.json / .ps1). Skipping"
                        }
                    }
                }

                # Process files in the PowerShellModules folder
                elseif($File.FullPath -like "$Path\$($RepositoryInformation.PowerShellModuleFolder)\*")
                {
                    Switch -CaseSensitive ($File.FileExtension)
                    {
                        '.psd1'
                        {
                            if($ProcessedPowerShellModules -notcontains $File.FileName)
                            {
                                $ProcessedPowerShellModules += $File.FileName
                                Switch -CaseSensitive ($File.FileExtension)
                                {
                                    "D"
                                    {
                                        # Not implemented
                                    }
                                    Default
                                    {
                                    }
                                }
                            }
                            else
                            {
                                Write-Verbose -Message "Skipping [$(ConvertTo-Json $File)]. File already processed in changeset"
                            }
                        }
                        default
                        {
                            Write-Verbose -Message "[$($File.FileName)] is not a supported file type for the PowerShellModules folder (.psd1). Skipping"
                        }
                    }
                }
                Write-Verbose -Message "[$($File.FileName)] Finished Processing"
                Checkpoint-Workflow

            }

            if($CleanupOrphanRunbooks)
            {
                #Remove-OrphanRunbook
            }
            if($CleanupOrphanAssets)
            {
                #Remove-OrphanVariable
                #Remove-OrphanSchedule
            }
            
            $UpdatedRepositoryInformation = Set-SmaRepositoryInformationCommitVersion -RepositoryInformation $CIVariables.RepositoryInformation `
                                                                                      -Path $Path `
                                                                                      -Commit $RepoChange.CurrentCommit
            Set-SmaVariable -Name 'SMAContinuousIntegration-RepositoryInformation' `
                            -Value $UpdatedRepositoryInformation `
                            -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                            -Port $CIVariables.WebservicePort `
                            -Credential $SMACred

            Write-Verbose -Message "Finished Processing [$($RepositoryInformation.CurrentCommit)..$($RepoChange.CurrentCommit)]"
        }
    }
    Catch
    {
        Write-Exception -Stream Warning -Exception $_
    }
    Write-Verbose -Message "Finished [$WorkflowCommandName]"
}