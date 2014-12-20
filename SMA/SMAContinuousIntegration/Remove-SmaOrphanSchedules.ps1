Workflow Remove-SmaOrphanSchedules
{
    Param($TFSServer,
          $TFSCollection,
          $SourcePath,
          $Branch,
          $WebServiceEndpoint = "https://localhost")

    Function Get-SmaReferencedSchedules
    {
        Param($TFSServer, $TFSCollection, $SourcePath, $Branch)
        Write-Verbose -Message "Beginning Get-SmaReferencedSchedules"
        # Build the TFS Location (server and collection)
        $TFSServerCollection = $TFSServer + "\" + $TFSCollection
        Write-Verbose -Message "Searching TFS Workspace [$($TFSServerCollection)] for all Referenced Schedules"
        # Load the necessary assemblies for interacting with TFS
        $VClient = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.TeamFoundation.VersionControl.Client")
        $TFClient = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.TeamFoundation.Client")
    
        # Connect to TFS
        $regProjCollection = [Microsoft.TeamFoundation.Client.RegisteredTfsConnections]::GetProjectCollection($TFSServerCollection)
    
        # This is necessary to interact with your TFS from a source control perspective
        $tfsTeamProjCollection = [Microsoft.TeamFoundation.Client.TfsTeamProjectCollectionFactory]::GetTeamProjectCollection($regProjCollection)
        $vcs = $tfsTeamProjCollection.GetService([Type]"Microsoft.TeamFoundation.VersionControl.Client.VersionControlServer")

        $allItems = $vcs.GetItems($SourcePath,2)
        
        foreach ($item in $allItems.Items)
        {
            if($item.ItemType.ToString().Equals('File')) 
            { 
                if($item.ServerItem.ToString().ToLower().EndsWith('.xml'))
                {
                    $ServerPath = $item.ServerItem.ToString()
                    $fi = Get-Item -Path (($ServerPath.Replace($allItems.QueryPath, $SourcePath)).Replace('/','\'))
                    if($fi.Directory.Name.ToLower().Equals($Branch.ToLower()))
                    {
                        try
                        {
                            [xml]$xml = Get-Content -Path $fi.FullName
                            $xNode = $xml.SelectNodes("//Schedules/Schedule/Name")
                            if($xNode)
                            {
                                $strValue = $xNode.InnerText
                                if(![String]::IsNullOrEmpty($strValue))
                                {
                                    $strValue = $strValue.Trim()
                                    if(![String]::IsNullOrEmpty($strValue))
                                    {
                                        $strValue
                                        Write-Verbose -Message "[$($fi.FullName)] [$strValue]"
                                    }
                                }
                            }
                        }
                        catch { Write-Verbose -Message "Error reading $($fi.Name)" }
                    }
                }
            }
        }
        Write-Verbose -Message "Finished Get-SmaReferencedSchedules"
    }

    Function Get-AllSmaSchedules
    {
        Param(  [Parameter(Mandatory=$true)]  [String]$WebServiceURL,
                [Parameter(Mandatory=$false)] [String]$WebServicePort="9090",
                [Parameter(Mandatory=$false)] [String]$tenantID = "00000000-0000-0000-0000-000000000000",
                [Parameter(Mandatory=$false)] [pscredential]$Credential )

        # Get all variables
        $schedulesURI = "$WebServiceURL`:$WebServicePort/$tenantID/Schedules"
        if ($Credential) { $schedules = Invoke-RestMethod -Uri $schedulesURI -Credential $Credential }
        else             { $schedules = Invoke-RestMethod -Uri $schedulesURI -UseDefaultCredentials }

        $addedToBox = $false

        $box = New-Object System.Collections.ArrayList
        foreach ($schedule in $schedules) 
        { 
            $box.Add($schedule) | Out-Null
            $addedToBox = $true
        }

        while($addedToBox)
        {
            $addedToBox = $false
            $schedulesURI = "$WebServiceURL`:$WebServicePort/$tenantID/Schedules?$`skiptoken=guid'$($box[-1].Content.Properties.ScheduleID.'#text')'"
            if ($Credential) { $schedules = Invoke-RestMethod -Uri $schedulesURI -Credential $Credential }
            else             { $schedules = Invoke-RestMethod -Uri $schedulesURI -UseDefaultCredentials }
                    
            $addedToBox = $false
            foreach ($schedule in $schedules) 
            { 
                $box.Add($schedule) | Out-Null
                $addedToBox = $true
            }
        }
    
        return $box
    }
    
    $CredName = (Get-SmaVariable -Name "SMAContinuousIntegration-CredName" -WebServiceEndpoint $WebServiceEndpoint).Value
	Write-Verbose -Message "Accessing Credential Store for Cred $CredName"
	$cred = Get-AutomationPSCredential -Name $CredName

    $ReferencedSchedules = Get-SmaReferencedSchedules -TFSServer $TFSServer `
                                                      -SourcePath $SourcePath `
                                                      -TFSCollection $TFSCollection `
                                                      -Branch $Branch

    $SMASchedules = Get-AllSmaSchedules -WebServiceURL $WebServiceEndpoint `
                                        -Credential $cred

    Write-Verbose -Message "Comparing all SMA Variables to TFS variables"
    foreach -Parallel ($SMASchedule in $SMASchedules)
    {
		# Allow schedules that start with NoSync to be excluded from the orphan cleanup process
		if($SMASchedule.content.properties.Name.ToUpper() -notlike 'NOSYNC*')
		{
			inlinescript
			{
				$ReferencedSchedules = $Using:ReferencedSchedules
				$SMASchedule         = $Using:SMASchedule
				$WebServiceEndpoint  = $Using:WebServiceEndpoint
				$Cred                = $Using:Cred

				if(!$ReferencedSchedules.Contains($SMASchedule.content.properties.Name))
				{
					if($SMASchedule.content.properties.DayInterval.'#text' -eq $Null)
					{
						# if it is a one time schedule only delete it if its expired
						if($SMASchedule.ExpiryTime -lt (Get-Date))
						{
							Write-Verbose -Message "Removing $($SMASchedule.content.properties.Name)"
							Remove-SmaSchedule -Name $($SMASchedule.content.properties.Name) -WebServiceEndpoint $WebServiceEndpoint -Credential $Cred -Force 
							New-VariableRunbookTrackingInstance -VariablePrefix 'TFSContinuousIntegration-RemoveOrphanSchedules' `
																-WebServiceEndpoint $WebServiceEndpoint       
						}
					}
					else
					{
						# Always remove recurring schedules if they are not referenced
						Write-Debug -Message "Removing $($SMASchedule.content.properties.Name)"
						Remove-SmaSchedule -Name $($SMASchedule.content.properties.Name) -WebServiceEndpoint $WebServiceEndpoint -Credential $Cred -Force
						New-VariableRunbookTrackingInstance -VariablePrefix 'TFSContinuousIntegration-RemoveOrphanSchedules' `
															-WebServiceEndpoint $WebServiceEndpoint       
					}
				}
			}
		}
    }
    Write-Verbose -Message "Finished comparing all SMA Variables to TFS variables"
}