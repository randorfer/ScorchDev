Workflow Remove-SmaOrphanVariables
{
    Param($TFSServer,
          $TFSCollection,
          $SourcePath,
          $Branch,
          $WebServiceEndpoint = "https://localhost")
    
    Function Get-SmaReferencedVariables
    {
        Param($TFSServer, $TFSCollection, $SourcePath, $Branch)
        Write-Verbose -Message "Beginning Get-SmaReferencedVariables"

        # Build the TFS Location (server and collection)
        $TFSServerCollection = $TFSServer + "\" + $TFSCollection
        Write-Verbose -Message "Searching TFS Workspace [$($TFSServerCollection)] for all Referenced Variables"
        # Load the necessary assemblies for interacting with TFS
        $VClient  = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.TeamFoundation.VersionControl.Client")
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
                            $xNode = $xml.SelectNodes("//Variables/Variable/Name")
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
        Write-Verbose -Message "Finished Get-ReferencedVariables"
    }
    Function Get-AllSmaVariables
    {
        Param(  [Parameter(Mandatory=$true)]  [String]$WebServiceURL,
                [Parameter(Mandatory=$false)] [String]$WebServicePort="9090",
                [Parameter(Mandatory=$false)] [String]$tenantID = "00000000-0000-0000-0000-000000000000",
                [Parameter(Mandatory=$false)] [pscredential]$Credential )

        # Get all variables
        $variablesURI = "$WebServiceURL`:$WebServicePort/$tenantID/Variables"
        if ($Credential) { $variables = Invoke-RestMethod -Uri $variablesURI -Credential $Credential }
        else             { $variables = Invoke-RestMethod -Uri $variablesURI -UseDefaultCredentials }

        $addedToBox = $false

        $box = New-Object System.Collections.ArrayList
        foreach ($varible in $variables) 
        { 
            $box.Add($varible) | Out-Null
            $addedToBox = $true
        }

        while($addedToBox)
        {
            $addedToBox = $false
            $variablesURI = "$WebServiceURL`:$WebServicePort/$tenantID/Variables?$`skiptoken=guid'$($box[-1].Content.Properties.VariableID.'#text')'"

            if($credential) { $variables = Invoke-RestMethod -Uri $variablesURI -Credential $Credential }
            else            { $variables = Invoke-RestMethod -Uri $variablesURI -UseDefaultCredentials }
                    
            $addedToBox = $false
            foreach ($varible in $variables) 
            { 
                $box.Add($varible) | Out-Null
                $addedToBox = $true
            }
        }
    
        return $box
    }
    $CredName = (Get-SmaVariable -Name "SMAContinuousIntegration-CredName" -WebServiceEndpoint $WebServiceEndpoint).Value
	Write-Verbose -Message "Accessing Credential Store for Cred $CredName"
	$cred = Get-AutomationPSCredential -Name $CredName

    $ReferencedVariables = Get-SmaReferencedVariables -TFSServer $TFSServer `
                                                      -SourcePath $SourcePath `
                                                      -TFSCollection $TFSCollection `
                                                      -Branch $Branch

    $SMAVariables = Get-AllSmaVariables -WebServiceURL $WebServiceEndpoint `
                                        -Credential $cred

    Write-Verbose -Message "Comparing all SMA Variables to TFS variables"
    foreach -Parallel ($SMAVariable in $SMAVariables)
    {
        if($SMAVariable.content.properties.Name.GetType().Name -eq 'XmlElement')
        {
            $VariableName = $SMAVariable.content.properties.Name.'#text'.Trim()
        }
        else
        {
            $VariableName = $SMAVariable.content.properties.Name
        }
		# Allow schedules that start with NoSync to be excluded from the orphan cleanup process
		if($VariableName.ToUpper() -notlike 'NOSYNC*')
		{
			inlinescript
			{
				$ReferencedVariables = $Using:ReferencedVariables
				$VariableName        = $Using:VariableName
				$WebServiceEndpoint  = $Using:WebServiceEndpoint
				$Cred                = $Using:Cred

				if(!$ReferencedVariables.Contains($VariableName))
				{
					Write-Debug -Message "Removing $($VariableName)"
					Remove-SmaVariable -Name $($VariableName) `
									   -WebServiceEndpoint $WebServiceEndpoint `
									   -Credential $Cred
					New-VariableRunbookTrackingInstance -VariablePrefix 'TFSContinuousIntegration-RemoveOrphanVariables' `
														-WebServiceEndpoint $WebServiceEndpoint       
				}
			}
		}
    }
    Write-Verbose -Message "Finished comparing all SMA Variables to TFS variables"
}