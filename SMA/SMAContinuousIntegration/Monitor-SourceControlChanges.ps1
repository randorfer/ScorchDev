<#
    #TODO Put header information here
#>
workflow Monitor-SourceControlChanges
{
    Param([string]$WebServiceEndpoint = "https://localhost")
    
    Write-Verbose -Message "Starting [$WorkflowCommandName]"
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    # TODO: implement local dev module so we can pull these without being connected.
    <#
    $CIVariables = Get-BatchSMAVariable -Name @('MonitorLifeSpan',
                                                'LocalGitRepo',
                                                'GitBranch') `
                                        -Prefix 'SMAContinuousIntegration' `
                                        -WebServiceEndpoint $WebServiceEndpoint

    $MonitorRefreshTime = ( Get-Date ).AddMinutes( $CIVariables.MonitorLifeSpan )
    #>
    $MonitorRefreshTime = ( Get-Date ).AddMinutes( 60 )
    $MonitorActive      = ( Get-Date ) -lt $MonitorRefreshTime
    $DelayCycle         = 5
    $DelayCheckpoint    = 5
    $RepoVars = New-Object PSObject -Property @{'Path' = 'C:\git\SCORCHDev' ; 'Branch' = 'Dev'}
    
    while($MonitorActive)
    {
		try
		{
			$RepoChangeJSON = Find-GitRepoChange -Path $RepoVars.Path `
                                                 -Branch $RepoVars.Branch

            $RepoChange = ConvertFrom-JSON -InputObject $RepoChangeJSON

            if($RepoChange.Status -eq 'Updates')
            {
                Write-Warning -Message "Updates Found" -WarningAction Continue
            }
        }
        catch
        {
            
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
	Write-Verbose -Message "Reached end of monitor lifespan. Relaunching this monitor [$WorkflowCommandName]."
	#$Launch = Start-SmaRunbook -Name $WorkflowCommandName `
#							   -WebServiceEndpoint $WebServiceEndpoint
}