Workflow Publish-SMARunbookChanges
{
    Param([Parameter(Mandatory=$true) ][string] $ItemPath, 
          [Parameter(Mandatory=$true) ][string] $ChangesetID, 
          [Parameter(Mandatory=$true) ][string] $TFSServer, 
          [Parameter(Mandatory=$true) ][string] $TFSCollection,
          [Parameter(Mandatory=$false)][string] $WebServiceEndpoint = "https://localhost")
   
    #region Functions
    Function Save-TFSSourceChanges
    {
        Param($TFSServer, $TFSCollection="defaultcollection", $ItemPath)
        Write-Verbose -Message "Starting Save-TFSSourceChanges"
        $TFSServerCollection = $TFSServer + "\" + $TFSCollection
    
        # Load the necessary assemblies for interacting with TFS
        $VClient  = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.TeamFoundation.VersionControl.Client")
        $TFClient = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.TeamFoundation.Client")
    
        # Connect to TFS
        $regProjCollection = [Microsoft.TeamFoundation.Client.RegisteredTfsConnections]::GetProjectCollection($TFSServerCollection)
    
        # This is necessary to interact with your TFS from a source control perspective
        $tfsTeamProjCollection = [Microsoft.TeamFoundation.Client.TfsTeamProjectCollectionFactory]::GetTeamProjectCollection($regProjCollection)
        $vcs = $tfsTeamProjCollection.GetService([Type]"Microsoft.TeamFoundation.VersionControl.Client.VersionControlServer")

        # Setting up your workspace and source path you are managing
        $vcsWorkspace = $vcs.GetWorkspace($ItemPath)
            
        $PendingAddItems = $vcsWorkspace.PendAdd($ItemPath)
        $PendingChanges  = $vcsWorkspace.GetPendingChanges($ItemPath)
        if($PendingChanges)
        {
            Write-Verbose -Message "Changes were made, saving"
            $ChangesCheckIn = $vcsWorkspace.CheckIn($PendingChanges, "Updates via PowerShell")
            Write-Verbose -Message "Finished saving changes"
        }
        Write-Verbose -Message "Finished Save-TFSSourceChanges"
    }
    Function Process-ConfigurationVariables
    {
        Param($Configuration, $WebServiceEndpoint)
        Write-Verbose -Message "Starting Process-ConfigurationVariables"   
        [xml]$cXML = $Configuration
        foreach($Variable in $cXML.SelectNodes("//Variable"))
        {
            $VariableName          = $Variable.Name
            [object]$VariableValue = $Variable.Value
            $VariableDescription   = $Variable.Description
            $VariableType          = $Variable.Type
            $IsEncrypted           = [Convert]::ToBoolean($Variable.IsEncrypted)
            
            Write-Verbose -Message "Setting up [$VariableName] with Value [$VariableValue] Description [$VariableDescription] Type [$VariableType] Is Encrypted [$IsEncrypted]"
                       
            # Detect this is a $NULL variable (cannot create currently)
            if($VariableValue -eq "")
            { 
                Write-Error -Message "No value in [$variableName]. Must be a NULL variable. Not created." -ErrorAction Continue
            }
            # If this is an encrypted variable, handle appropriately
            elseif($IsEncrypted)
            {
				switch -CaseSensitive ($VariableType.ToLower())
				{
					{($_ -eq "int") -or ($_ -eq "integer")}
					{
						[int]$intValue = $variablevalue
						$CreateEncryptedVariable = Set-SmaVariable -Name $VariableName `
																-Value $intValue `
																-Description $VariableDescription `
																-Encrypted `
																-WebServiceEndpoint $WebServiceEndpoint
					} 
					{($_ -eq "bool") -or ($_ -eq "boolean")}
					{
						[bool]$boolValue = [System.Convert]::ToBoolean($variablevalue)
						$CreateEncryptedVariable = Set-SmaVariable -Name $VariableName `
																-Value $boolValue `
																-Description $VariableDescription `
																-Encrypted `
																-WebServiceEndpoint $WebServiceEndpoint
					} 
					{($_ -eq "date") -or ($_ -eq "datetime")}
					{
						[datetime]$dateValue = [System.Convert]::ToDateTime($variablevalue)
						$CreateEncryptedVariable = Set-SmaVariable -Name $VariableName `
																-Value $dateValue `
																-Description $VariableDescription `
																-Encrypted `
																-WebServiceEndpoint $WebServiceEndpoint
					} 
					default
					{
						$CreateEncryptedVariable = Set-SmaVariable -Name $VariableName `
																-Value $variablevalue `
																-Description $VariableDescription `
																-Encrypted `
																-WebServiceEndpoint $WebServiceEndpoint
					}
				}
                
                Write-Verbose -Message "Creating encrypted variable $variableName of type $VariableType"
            }
            else #Otherwise Create normally (non encrypted)
            {
                switch -CaseSensitive ($VariableType.ToLower())
				{
					{($_ -eq "int") -or ($_ -eq "integer")}
					{
						[int]$intValue = $variablevalue
						$CreateVariable = Set-SmaVariable -Name $VariableName `
																-Value $intValue `
																-Description $VariableDescription `
																-WebServiceEndpoint $WebServiceEndpoint
					} 
					{($_ -eq "bool") -or ($_ -eq "boolean")}
					{
						[bool]$boolValue = [System.Convert]::ToBoolean($variablevalue)
						$CreateVariable = Set-SmaVariable -Name $VariableName `
																-Value $boolValue `
																-Description $VariableDescription `
																-WebServiceEndpoint $WebServiceEndpoint
					} 
					{($_ -eq "date") -or ($_ -eq "datetime")}
					{
						[datetime]$dateValue = [System.Convert]::ToDateTime($variablevalue)
						$CreateVariable = Set-SmaVariable -Name $VariableName `
																-Value $dateValue `
																-Description $VariableDescription `
																-WebServiceEndpoint $WebServiceEndpoint
					} 
					default
					{
						$CreateVariable = Set-SmaVariable -Name $VariableName `
																-Value $variablevalue `
																-Description $VariableDescription `
																-WebServiceEndpoint $WebServiceEndpoint
					}
				}
                Write-Verbose -Message "Creating standard variable $variableName of type $VariableType"
            }
            Write-Verbose -Message "Variable Created"
        }
         Write-Verbose -Message "Finished Process-ConfigurationVariables"
    }
    Function Process-ConfigurationSchedules
    {
        Param($Configuration, $runbookName, $WebServiceEndpoint)
        Write-Verbose -Message "Starting Process-ConfigurationSchedules"   
        [xml]$cXML = $Configuration
        foreach($Schedule in $cXML.SelectNodes("//Schedule"))
        {
            Write-Verbose -Message "Starting to Process Schedule $($schedule.ScheduleName)"
            # Assign variables for Schedule with XML Data
            [string]$ScheduleName         = $Schedule.Name
            [string]$ScheduleDescription  = $Schedule.Description
            [string]$ScheduleType         = $Schedule.Type
            [datetime]$ScheduleNextRun    = [System.Convert]::ToDateTime($Schedule.NextRun)
            [datetime]$ScheduleExpiryTime = [System.Convert]::ToDateTime($Schedule.ExpirationTime)
            [int32]$ScheduleDayInterval   = $Schedule.ScheduleDayInterval
            Write-Verbose -Message "$($ScheduleName): Next Run [$($ScheduleNextRun)] Expiration [$($ScheduleExpiryTime)] Interval [$($ScheduleDayInterval)]"
            # Create schedule with details from XML - start time in the past will be set to execute on the next scheduled instance
            # (assigning to variable to avoid displaying to screen)
            $SMASchedule = Set-SmaSchedule -Name $ScheduleName -Description $ScheduleDescription -ScheduleType DailySchedule -StartTime $ScheduleNextRun -ExpiryTime $ScheduleExpiryTime -DayInterval $ScheduleDayInterval -WebServiceEndpoint $WebServiceEndpoint
            
            if($RunbookName)
            {
                # Associating Schedule to Runbook (assigning to variable to avoid displaying to screen)
                $StartSMARunbook = Start-SmaRunbook -Name $RunbookName -ScheduleName $ScheduleName -WebServiceEndpoint $WebServiceEndpoint
                Write-Verbose -Message "Associating [$ScheduleName] with $RunbookName."
            }
            Write-Verbose -Message "Finished Processing Schedule $($schedule.ScheduleName)"
        }
        Write-Verbose -Message "Finished Process-ConfigurationSchedules"
    }
    Function Load-FileInformation
    {
        Param($ItemPath)
        
        $null = $(
            $fi = Get-Item -Path $ItemPath
        
            $folder        = $fi.Directory
            $folderPath    = $folder.FullName
            $fileExtension = $fi.Extension
            $fileName      = $fi.Name.Substring(0, $fi.Name.length - $fileExtension.Length)
        
            if($fileExtension.ToLower().Equals('.ps1'))
            {
                $scriptText = Get-Content -Path $fi.FullName
                for($i=0; $i -lt $scriptText.Length; $i++)
                {
                    if($scriptText[$i] -like "workflow*") { $line = $scriptText[$i]; $i = $scriptText.Length } 
                }

                $workflowTagFound = $false
                $runbookName = [System.String]::Empty
                foreach($str in $line.Split(' '))
                {
                    if(!$workflowTagFound) { if($str.ToLower().Equals('workflow')) { $workflowTagFound = $true } }
                    else { if($str) { $runbookName = $str ; break; } }                
                }
            }

        )
        return $folderPath, $fileName, $fileExtension, $runbookName
    }
    Function Setup-WorkflowConfigurationFile
    {
        Param($filePath)

        $null = $(
            $configurationTemplate = @'
<Root>
    <Description>
    </Description>
    <LogVerbose>False</LogVerbose>
    <LogDebug>False</LogDebug>
    <LogProgress>False</LogProgress>
    <Tags>
    <!--
        <Tag></Tag>
    -->
    </Tags>
    <Variables>
    <!--
        <Variable>
            <Name></Name>
            <Description></Description>
            <Value></Value>
            <Type>String</Type>
            <isEncrypted>False</isEncrypted>
        </Variable>
    -->
    </Variables>
    <Schedules>
    <!--
        <Schedule>
            <Name></Name>
            <Description></Description>
            <Type></Type>
            <NextRun></NextRun>
            <ExpirationTime></ExpirationTime>
            <ScheduleDayInterval></ScheduleDayInterval>
        </Schedule>
    -->
    </Schedules>
</Root>
'@
            Write-Verbose -Message "Looking for file [$filePath]"
            if(-not (Test-Path $filePath))
            {
                Write-Verbose -Message "Not Found, creating [$filePath]"
                $ConfigurationFile = New-Item -Path $filePath -ItemType File
            
                $configurationTemplateLines = $configurationTemplate.Split("`n")
                foreach($line in $configurationTemplateLines)
                {
                    Add-Content -Path $filePath -Value $line
                }
                Write-Verbose -Message "Created File"
                $retValue = $true
            }
            else
            {
                Write-Verbose -Message "File existed"
                $retValue = $false
            }
        )
        return $retValue
    }
    Function Load-ConfigurationFile
    {
        Param($ItemPath, $ChangesetID)
        $null = $(
            Write-Verbose -Message "Starting Load-ConfigurationFile for [$ItemPath]"
            [xml]$configuration = (Get-Content -Path $ItemPath)

            # Load Tag Information from configuration file
            $tagLine = New-Object -TypeName System.Text.Stringbuilder
            foreach($TagNode in $configuration.SelectNodes("//Tags/Tag"))
            {
                $tagLine.Append("$($TagNode.'#text'); ") | Out-Null
            }
            $tagLine.Append("TFS-Changeset-ID:$ChangesetID") | Out-Null
            $RunbookTags = $tagLine.ToString()

            # Load other runbook settings information
            $RunbookDescription = $configuration.Root.Description
            $RunbookLogDebug    = [Convert]::ToBoolean($configuration.Root.LogDebug)
            $RunbookLogVerbose  = [Convert]::ToBoolean($configuration.Root.LogVerbose)
            $RunbookLogProgress = [Convert]::ToBoolean($configuration.Root.LogProgress)
            $RunbookScriptFileExists = Test-Path -Path "$($ItemPath.Substring(0,$ItemPath.Length - 4)).ps1"

            Write-Verbose -Message "Configuration [$configuration]"
            Write-Verbose -Message "RunbookTags [$RunbookTags]"
            Write-Verbose -Message "RunbookDescription [$RunbookDescription]"
            Write-Verbose -Message "RunbookLogDebug [$RunbookLogDebug]"
            Write-Verbose -Message "RunbookLogVerbose [$RunbookLogVerbose]"
            Write-Verbose -Message "RunbookLogProgress [$RunbookLogProgress]"
            Write-Verbose -Message "RunbookScriptFileExists [$RunbookScriptFileExists]"

            Write-Verbose -Message "Finished Load-ConfigurationFile for [$filePath]"
        )
        return [xml]$configuration, $RunbookTags, $RunbookDescription, $RunbookLogDebug, $RunbookLogVerbose, $RunbookLogProgress, $RunbookScriptFileExists
    } 
    Function Update-RunbookConfiguration
    {
        Param($id, 
              $WebServiceEndpoint, 
              $RunbookDescription, 
              $RunbookLogDebug, 
              $RunbookLogVerbose, 
              $RunbookLogProgress, 
              $RunbookTags)

        Function Set-SmaRunbookTags
        {
            Param([string]$RunbookID, 
                  [string]$Tags=$null,
                  [string]$WebserviceEndpoint=$null,
                  [string]$port = "9090")

            $null = $(
                Write-Verbose -Message "Starting Set-SmaRunbookTags for [$RunbookID] Tags [$Tags]" 
                $RunbookURI = "$($WebserviceEndpoint):$($port)/00000000-0000-0000-0000-000000000000/Runbooks(guid'$($RunbookID)')"
                $runbook = Get-SmaRunbook -Id $RunbookID `
                                          -WebServiceEndpoint $WebserviceEndpoint `
                                          -Port $port
 
                [xml]$baseXML = @'
<?xml version="1.0" encoding="utf-8"?>
<entry xmlns="http://www.w3.org/2005/Atom" xmlns:d="http://schemas.microsoft.com/ado/2007/08/dataservices" xmlns:m="http://schemas.microsoft.com/ado/2007/08/dataservices/metadata">
    <id></id>
    <category term="Orchestrator.ResourceModel.Runbook" scheme="http://schemas.microsoft.com/ado/2007/08/dataservices/scheme" />
    <title />
    <updated></updated>
    <author>
        <name />
    </author>
    <content type="application/xml">
        <m:properties>
            <d:Tags></d:Tags>
        </m:properties>
    </content>
</entry>
'@
                $baseXML.Entry.id                      = $RunbookURI
                $baseXML.Entry.Content.Properties.Tags = [string]$Tags

                $output = Invoke-RestMethod -Method Merge `
                                            -Uri $RunbookURI `
                                            -Body $baseXML `
                                            -UseDefaultCredentials `
                                            -ContentType 'application/atom+xml'

                Write-Verbose -Message "Finished Set-SmaRunbookTags for $RunbookID"
            )
        }

        Write-Verbose -Message "Starting Update-RunbookConfiguration for $id"
        Set-SmaRunbookConfiguration -Id                 $id `
                                    -Description        $RunbookDescription `
                                    -LogDebug           $RunbookLogDebug `
                                    -LogVerbose         $RunbookLogVerbose `
                                    -LogProgress        $RunbookLogProgress `
                                    -WebServiceEndpoint $WebServiceEndpoint

        Set-SMARunbookTags -RunbookID $id `
                           -Tags $RunbookTags `
                           -WebserviceEndpoint $WebServiceEndpoint

        Write-Verbose -Message "Finsihed Update-RunbookConfiguration for [$id]"
    }
    Function Import-Runbook
    {
        Param($RunbookName,
              $WebServiceEndpoint,
              $ItemPath,
              $ChangesetId)

        Function Set-SmaRunbookTags
        {
            Param([string]$RunbookID, 
                  [string]$Tags=$null,
                  [string]$WebserviceEndpoint=$null,
                  [string]$port = "9090")

            $null = $(
                Write-Verbose -Message "Starting Set-SmaRunbookTags for [$RunbookID] Tags [$Tags]" 
                $RunbookURI = "$($WebserviceEndpoint):$($port)/00000000-0000-0000-0000-000000000000/Runbooks(guid'$($RunbookID)')"
                $runbook = Get-SmaRunbook -Id $RunbookID `
                                          -WebServiceEndpoint $WebserviceEndpoint `
                                          -Port $port
 
                [xml]$baseXML = @'
<?xml version="1.0" encoding="utf-8"?>
<entry xmlns="http://www.w3.org/2005/Atom" xmlns:d="http://schemas.microsoft.com/ado/2007/08/dataservices" xmlns:m="http://schemas.microsoft.com/ado/2007/08/dataservices/metadata">
    <id></id>
    <category term="Orchestrator.ResourceModel.Runbook" scheme="http://schemas.microsoft.com/ado/2007/08/dataservices/scheme" />
    <title />
    <updated></updated>
    <author>
        <name />
    </author>
    <content type="application/xml">
        <m:properties>
            <d:Tags></d:Tags>
        </m:properties>
    </content>
</entry>
'@
                $baseXML.Entry.id                      = $RunbookURI
                $baseXML.Entry.Content.Properties.Tags = [string]$Tags

                $output = Invoke-RestMethod -Method Merge `
                                            -Uri $RunbookURI `
                                            -Body $baseXML `
                                            -UseDefaultCredentials `
                                            -ContentType 'application/atom+xml'

                Write-Verbose -Message "Finished Set-SmaRunbookTags for $RunbookID"
            )
        } 
        Function Parse-RunbookChangesetID
        {
            Param($Runbook)
            
            $null = $(
                $RBChangesetID = 0
                if($Runbook.Tags)
                {
                    try
                    {
                        [array] $tagArray = $runbook.Tags.Split(';')
                        foreach($tag in $tagArray)
                        {
                            if($tag -like "*TFS-Changeset-ID:*")
                            {
                                [int]$RBChangesetID = $tag.Split(':')[1].Trim()
                            }
                        }
                    }
                    catch
                    {
                        $RBChangesetID = 0
                    }
                }
            )
            Return $RBChangesetID, [string]$runbook.Tags
        }
        Write-Verbose -Message "Beginning Import-Runbook"
        $GetRunbook = Get-SmaRunbook -Name $runbookName `
                                     -WebServiceEndpoint $WebServiceEndpoint `
									 -ErrorAction SilentlyContinue

        if(-not ($GetRunbook.RunbookID.Guid))
        {
            Write-Verbose -Message "Runbook [$runbookName] Didn't Exist -- Importing"
            
            $ImportedRunbook = Import-SmaRunbook -Path $ItemPath `
                                                 -WebServiceEndpoint $WebServiceEndpoint
            
            $GetRunbook      = Get-SmaRunbook -Name $runbookName `
                                              -WebServiceEndpoint $WebServiceEndpoint

            $WFHolder        = Publish-SmaRunbook -WebServiceEndpoint $WebServiceEndpoint `
                                                  -id $ImportedRunbook.RunbookID

            $tagLine = "TFS-Changeset-ID:$ChangesetId"
            
            Set-SmaRunbookTags -RunbookID $GetRunbook.RunbookID.Guid `
                               -Tags $tagLine `
                               -WebserviceEndpoint $WebServiceEndpoint

            Write-Verbose -Message "New Runbook $RunbookName was successfully imported Changeset [$ChangesetId]"
        }
        else
        {
            Write-Verbose -Message "Runbook Existed Updating" 
            
            $outputs = Parse-RunbookChangesetID -Runbook $GetRunbook
            
            $RBChangesetID = $outputs[0]
            $TagLine       = $outputs[1]

            if($ChangesetID -ge $RBChangesetID)
            {
                $tagBuilder = New-Object -TypeName System.Text.StringBuilder
                [array] $tagArray = $tagLine.Split(';')
                foreach($tag in $tagArray)
                {
                    if($tag -like "*TFS-Changeset-ID:*")
                    {
                        $tagBuilder.Append("TFS-Changeset-ID:$ChangesetId; ") | Out-Null
                    }
                    else
                    {
                       $tagBuilder.Append("$tag; ") | Out-Null
                    }
                }
                $tagLine = $tagBuilder.ToString()
                $tagLine = $tagLine.Substring(0,$tagLine.Length-2)
                Write-Verbose -Message "Newer Changeset [$ChangesetId] / [$RBChangesetID] for Runbook $RunbookName Found - Updating"
                
                $EditStatus = Edit-SmaRunbook -Overwrite `
                                              -Path $ItemPath `
                                              -Name $RunbookName `
                                              -WebServiceEndpoint $WebServiceEndpoint

                # Redirect the output of Publish-SmaRunbook to a variable so it isn't saved in SMA
                $WFHolder = Publish-SmaRunbook -WebServiceEndpoint $WebServiceEndpoint `
                                               -Id $GetRunbook.RunbookID

                Set-SmaRunbookTags -RunbookID $GetRunbook.RunbookID `
                                   -Tags $tagLine `
                                   -WebserviceEndpoint $WebServiceEndpoint
            }
            else
            {
                Write-Verbose -Message "Version is not newer - not edit attempted [$ChangesetId] / [$RBChangesetID]"
            }
            Write-Verbose -Message "Finished Import-Runbook"
        }
    }
    #endregion
    
    # Load changeset and serveritem properties for the current file

    Write-Verbose -Message "`$ItemPath [$ItemPath]"
    Write-Verbose -Message "`$ChangesetID [$ChangesetID]"

    # Parse information about this file
    $fileArray = Load-FileInformation -ItemPath $ItemPath
    Write-Verbose -Message "File Information Loaded"
    
    $FolderPath    = $fileArray[0]
    $FileName      = $fileArray[1]
    $FileExtension = $fileArray[2]
    $RunbookName   = $fileArray[3]
    
    # Process the file based on its type
    switch -CaseSensitive ($FileExtension)
    {
        ".ps1" 
        {
            Write-Verbose -Message "Processing   [$($FileName)$($FileExtension)] as a .ps1 file"
            Write-Verbose -Message "Runbook Name [$($RunbookName)]"
            Write-Verbose -Message "ChangesetId  [$($ChangesetID)]"
            
            # Import / update the runbook Do not publish yet
            Import-Runbook -RunbookName        $RunbookName `
                           -ItemPath           $ItemPath `
                           -WebServiceEndpoint $WebServiceEndpoint `
                           -ChangesetId        $ChangesetID
            
            # Check / Create a configuration file -- if this is created fresh it will be processed in the next pass
            $fileCreated = Setup-WorkflowConfigurationFile -FilePath "$($folderPath)\$($runbookName).xml"
            Write-Verbose -Message "Finished Processing [$($fileName)$($FileExtension)] as a .ps1 file"
            
            if($fileCreated)
            {
                Write-Verbose -Message "Saving any TFS Changes"
                Save-TFSSourceChanges -TFSServer $TFSServer `
                                      -TFSCollection $TFSCollection `
                                      -ItemPath "$($folderPath)\$($runbookName).xml"
            }
			Write-Debug -Message "Runbook Name [$($runbookName)] Imported"
        }
        ".xml"
        {
            Write-Verbose -Message "Processing [$($fileName)$($FileExtension)] as a .xml file"
            # Load configuration Settings
            $ConfigurationFileSettings = Load-ConfigurationFile -ItemPath $ItemPath -ChangesetID $ChangesetID
            
            $ConfigurationXML        = $ConfigurationFileSettings[0]
            $RunbookTags             = $ConfigurationFileSettings[1]
            $RunbookDescription      = $ConfigurationFileSettings[2]
            $RunbookLogDebug         = $ConfigurationFileSettings[3]
            $RunbookLogVerbose       = $ConfigurationFileSettings[4]
            $RunbookLogProgress      = $ConfigurationFileSettings[5]
            $RunbookScriptFileExists = $ConfigurationFileSettings[6]
            
            # If the runbook doesn't exist (initial import) than wait up to 5 minutes for it to be imported
            if($RunbookScriptFileExists)
            {
                $Runbook = $null
                $attemptCount = 0
                While((!$Runbook) -and ($attemptCount -lt 10))
                {
                    $Runbook = Get-SmaRunbook -WebServiceEndpoint $WebServiceEndpoint `
                                              -Name $fileName `
                                              -ErrorAction SilentlyContinue

                    if(!$Runbook) 
                    { 
                        $attemptCount++ 
                        Write-Verbose -Message "Runbook [$fileName] not found"
                        Start-Sleep -Seconds 30
                    }
                }
            }
            # If there is a related runbook (same name as configuration file) process
            if($Runbook)
            {                        
                Update-RunbookConfiguration -Id                 $Runbook.RunbookID.Guid `
                                            -WebServiceEndpoint $WebServiceEndpoint `
                                            -RunbookDescription $RunbookDescription `
                                            -RunbookLogDebug    $RunbookLogDebug `
                                            -RunbookLogVerbose  $RunbookLogVerbose `
                                            -RunbookLogProgress $RunbookLogProgress `
                                            -RunbookTags        $RunbookTags `

                # If there was a draft version of the Runbook from a previous import publish it
                if($runbook.DraftRunbookVersionID) 
                { 
                    Write-Verbose -Message "Found a draft version - Publishing"
                    
                    # Redirect the output of Publish-SmaRunbook to a variable so it isn't saved in SMA
                    $WFHolder = Publish-SmaRunbook -WebServiceEndpoint $WebServiceEndpoint `
                                                   -Id $runbook.RunbookID
                }
                # Process Schedules related to a runbook
                Process-ConfigurationSchedules -Configuration      $ConfigurationXML `
                                               -RunbookName        $FileName `
                                               -WebServiceEndpoint $WebServiceEndpoint
            }            
            else
            {
                # Process Schedules not related to a runbook
                Process-ConfigurationSchedules -Configuration      $ConfigurationXML `
                                               -WebServiceEndpoint $WebServiceEndpoint
            }

            # Always Process Variables
            Process-ConfigurationVariables -Configuration      $ConfigurationXML `
                                           -WebServiceEndpoint $WebServiceEndpoint         

            Write-Debug -Message "Finished Processing [$($fileName)$($FileExtension)] as a .xml file"
        }
        default
        {
        }
    }
	
	New-VariableRunbookTrackingInstance -VariablePrefix 'TFSContinuousIntegration-DeployRunbook' -WebServiceEndpoint $WebServiceEndpoint   
}