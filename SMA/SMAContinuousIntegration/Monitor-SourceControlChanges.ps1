<#
    #TODO Put header information here
#>
workflow Monitor-SourceControlChanges
{
    Param([string]$WebServiceEndpoint = "https://localhost")
    
    Write-Verbose -Message "Starting [$WorkflowCommandName]"
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    $CIVariables = Get-BatchSMAVariable -Name @('MonitorLifeSpan',
                                                'LocalGitRepo',
                                                'GitBranch') `
                                        -Prefix 'SMAContinuousIntegration' `
                                        -WebServiceEndpoint $WebServiceEndpoint

    $MonitorRefreshTime = ( Get-Date ).AddMinutes( $CIVariables.MonitorLifeSpan )
    $MonitorActive      = ( Get-Date ) -lt $MonitorRefreshTime

    Initialize-LocalGitRepo

    while($MonitorActive)
    {
		try
		{
			$currentChangesetID =  Get-LastestTFSChangeset -TFSServer $TFSServer -TFSCollection $TFSCollection

			Write-Verbose -Message "`$currentChangesetID [$currentChangesetID]"
			Write-Verbose -Message "`$LatestChangesetID [$LatestChangesetID]"

			if($currentChangesetID -gt $LatestChangesetID)
			{
				# If this is a new changset then check for updates in the branch and update
                
                #region update Scripts
                Write-Verbose -Message "Updating Workspace Server[$TFSServer] collection [$TFSCollection] SourcePath [$TFSScriptsSourcePath] Branch [$Branch]"

			    $results = Update-TFSWorkspace -TFSServer         $TFSServer `
                                               -TFSCollection     $TFSCollection `
                                               -SourcePath        $TFSScriptsSourcePath `
                                               -Branch            $Branch `
                                               -LatestChangesetID $LatestChangesetID `
                                               -FileTypes         @('.ps1','.xml')
                Checkpoint-Workflow

                $ItemsDeletedInChangeset = $results[0]
                $NumberOfUpdatedItems    = $results[1]
                $ChangesetArray          = $results[2]
                $itemPathArray           = $results[3]

			    # If there were changes detected from the Update-TFSWorkspace funtion process them
			    if($NumberOfUpdatedItems -gt 0)
			    {
					Write-Debug -Message "Starting to Process PS1 and XML file Updates for Changeset [$currentChangesetID]"
                    
                    # Create list of runbooks that were updated (just ps1 files)
                    # and import everything
                    $RunbookList = @()

                    Foreach ($ChangedItemPath in $itemPathArray)
                    {
                        try
                        {
                            $ChangesetID = $ChangesetArray[$itemPathArray.IndexOf($ChangedItemPath)]

                            if($ChangedItemPath.Split('.')[-1] -eq "ps1")
                            {
                                $fileArray = Load-FileInformation -ItemPath $ChangedItemPath

                                $runbookName = $fileArray[-1]
                                if($runbookName -notin $RunbookList)
                                {
                                    $RunbookList += $runbookName
                                }
                            }
                        
                            Publish-SMARunbookChanges -ItemPath           $ChangedItemPath `
                                                      -ChangesetID        $ChangesetID `
                                                      -TFSServer          $TFSServer `
                                                      -TFSCollection      $TFSCollection `
                                                      -WebServiceEndpoint $WebServiceEndpoint
                        }
                        catch
                        {
                            Write-Error $_ -ErrorAction Continue
                        }
                    }
                    Checkpoint-Workflow

                    # cleanup orphans
                    Parallel
                    {
                        Remove-SmaOrphanSchedules -TFSServer          $TFSServer `
                                                  -TFSCollection      $TFSCollection `
                                                  -SourcePath         $TFSScriptsSourcePath `
                                                  -Branch             $Branch `
                                                  -WebServiceEndpoint $WebServiceEndpoint `
												  -ErrorAction        Continue

                        Remove-SmaOrphanVariables -TFSServer          $TFSServer `
                                                  -TFSCollection      $TFSCollection `
                                                  -SourcePath         $TFSScriptsSourcePath `
                                                  -Branch             $Branch `
                                                  -WebServiceEndpoint $WebServiceEndpoint `
												  -ErrorAction        Continue

                        Start-SmaRunbookListRepublish -RunbookList        $RunbookList `
                                                      -WebServiceEndpoint $WebServiceEndpoint `
												      -ErrorAction        Continue
                    }
					Write-Debug -Message "Finished Processing PS1 and XML file Updates for Changeset [$currentChangesetID]"
                    Checkpoint-workflow
			    }
                
                # If there were any deleted items run the runbook cleanup
                if($ItemsDeletedInChangeset)
                {
					Write-Debug -Message "Starting to Process PS1 and XML file Deletions for Changeset  [$currentChangesetID]"
                    Remove-SmaOrphanRunbooks -TFSServer          $TFSServer `
                                             -TFSCollection      $TFSCollection `
                                             -SourcePath         $TFSScriptsSourcePath `
                                             -Branch             $Branch `
                                             -WebServiceEndpoint $WebServiceEndpoint `
					                         -ErrorAction        Continue
					
					# If no items were updated we could have just deleted an XML file. We should run the
				    # orphan cleanups
					if($NumberOfUpdatedItems -eq 0)
					{
						Parallel
						{
							Remove-SmaOrphanSchedules -TFSServer          $TFSServer `
                                                      -TFSCollection      $TFSCollection `
                                                      -SourcePath         $TFSScriptsSourcePath `
                                                      -Branch             $Branch `
                                                      -WebServiceEndpoint $WebServiceEndpoint `
												      -ErrorAction        Continue

							Remove-SmaOrphanVariables -TFSServer          $TFSServer `
													  -TFSCollection      $TFSCollection `
													  -SourcePath         $TFSScriptsSourcePath `
													  -Branch             $Branch `
													  -WebServiceEndpoint $WebServiceEndpoint `
													  -ErrorAction        Continue
						}
					}
					Write-Debug -Message "Finished Processing PS1 and XML file Deletions for Changeset [$currentChangesetID]"
                }
                #endregion

                #region modules
                Write-Verbose -Message "Updating Workspace Server[$TFSServer] collection [$TFSCollection] SourcePath [$TFSModulesSourcePath] Branch [$Branch]"

                $results = Update-TFSWorkspace -TFSServer         $TFSServer `
                                               -TFSCollection     $TFSCollection `
                                               -SourcePath        $TFSModulesSourcePath `
                                               -Branch            $Branch `
                                               -LatestChangesetID $LatestChangesetID `
                                               -FileTypes         @('.psd1')
                Checkpoint-Workflow

                $ItemsDeletedInChangeset = $results[0]
                $NumberOfUpdatedItems    = $results[1]
                $ChangesetArray          = $results[2]
                $itemPathArray           = $results[3]

				if($NumberOfUpdatedItems -gt 0)
				{
					Write-Debug -Message "Starting to Processing PSD1 file Updates for Changeset [$currentChangesetID]"
					foreach($ItemPath in $itemPathArray)
					{
						$verificationResutls = Verify-SMAPowerShellModuleVersion -PowerShellModuleManifestPath $ItemPath `
																				 -WebServiceEndpoint           $WebServiceEndpoint

						$Deploy         = $verificationResutls[-1]
						$ModuleRootPath = $verificationResutls[-2]
						$ModuleName     = $verificationResutls[-3]

						if($Deploy)
						{
							Import-SmaPowerShellModule -ModuleName         $ModuleName `
													   -ModuleRootPath     $ModuleRootPath `
													   -WebServiceEndpoint $WebServiceEndpoint
                        
							Deploy-LocalPowerShellModule -ModuleName         $ModuleName `
														 -ModuleRootPath     $ModuleRootPath `
														 -WebServiceEndpoint $WebServiceEndpoint

							Update-SmaPowerShellModuleDefinition -PowerShellModuleManifestPath $ItemPath `
																 -WebServiceEndpoint $WebServiceEndpoint
						}
						Checkpoint-Workflow
					}
					Write-Debug -Message "Finished Processing PSD1 file Updates for Changeset [$CurrentChangesetID]"
				}
                if($ItemsDeletedInChangeset)
                {
                    <# TODO: Write Cleanup for removed modules #>
                }
                #endregion
				# update our variable so we don't kick off again and save to SMA Variable
				$LatestChangesetID = $currentChangesetID
                $holder            = Set-SmaVariable -Name "SMAContinuousIntegration-LatestChangeset" `
                                                     -Value ([int]$currentChangesetID) `
                                                     -WebServiceEndpoint $WebServiceEndpoint
			}
		}
		catch [Exception]
		{
			Write-Error  -Message  "$($_.Message) - $($_.StackTrace)"
		}
		finally
		{
			#region Sleep for Delay Cycle
			[int]$RemainingDelay = $DelayCycle - (Get-Date).TimeOfDay.TotalSeconds % $DelayCycle
			If ( $RemainingDelay -eq 0 ) { $RemainingDelay = $DelayCycle }
			Write-Verbose -Message "Sleeping for $RemainingDelay seconds."
			Checkpoint-Workflow

			While ( $RemainingDelay -gt 0 )
			{    
				Start-Sleep -Seconds ( [math]::Min( $RemainingDelay, $DelayCheckpoint ) )
				Checkpoint-Workflow
				$RemainingDelay -= $DelayCheckpoint
			}
			#endregion
			$MonitorActive = ( Get-Date ) -lt $MonitorRefreshTime
		}
    }
	#  Relaunch this monitor
	Write-Verbose -Message "Reached end of monitor lifespan. Relaunching this monitor [$MonitorRunbook]."
	$Launch = Start-SmaRunbook -Name $MonitorRunbook `
							   -WebServiceEndpoint $WebServiceEndpoint `
							   -Parameters @{ "currentChangesetID" = $LatestChangesetID  }
}