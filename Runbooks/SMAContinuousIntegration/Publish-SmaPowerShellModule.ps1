<#
    .SYNOPSIS
        Imports a PowerShell module into SMA
    
    .Description
        Create Zip file in local temp directory
        Import Zip file
            Cleanup

        All PowerShell modules must follow the following structure

        ContainingFolder\
            ModuleName\
                ModuleName.psd1
                ModuleName.psm1
                Dependencies
    
    .PARAMETER ModuleName
        The Name of the module to import

    .PARAMETER ModuleRootPath
        The path to the root of the Module Directory
    
    .PARAMETER WebServiceEndpoint
        The web service endpoint of the SMA environment to use for accessing variables
        Defaults to https://localhost

    
#>
Workflow Publish-SmaPowerShellModule
{
    Param( [Parameter(Mandatory=$true) ][string] $ModuleName,
           [Parameter(Mandatory=$true) ][string] $ModuleRootPath,
           [Parameter(Mandatory=$false)][string] $WebServiceEndpoint = "https://localhost")
    
    Function New-ZipFile
    {
        Param([Parameter(Mandatory=$true) ][string] $SourceDir,
              [Parameter(Mandatory=$true) ][string] $ZipFilePath,
              [Parameter(Mandatory=$false)][bool]   $OverwriteExisting = $true)
            
        $null = $(
            Write-Verbose -Message "Starting New-ZipFile"
            Write-Verbose -Message "`$SourceDir [$SourceDir]"
            Write-Verbose -Message "`$ZipFilePath [$ZipFilePath]"
                
            if($OverwriteExisting)
            {
                if(Test-Path -Path $ZipFilePath)
                {
                    Remove-Item $ZipFilePath -Force -Confirm:$false
                }
            }

            if(-not (Test-Path -Path "$($ZipFilePath.Substring(0,$ZipFilePath.LastIndexOf('\')))"))
            {
                $newDir = New-Item -ItemType Directory `
                                    -Path "$($ZipFilePath.Substring(0,$ZipFilePath.LastIndexOf('\')))" `
                                    -Force `
                                    -Confirm:$false
            }

            Add-Type -Assembly System.IO.Compression.FileSystem
            $CompressionLevel = [System.IO.Compression.CompressionLevel]::Optimal
            [System.IO.Compression.ZipFile]::CreateFromDirectory($SourceDir, $ZipFilePath, $CompressionLevel, $false)
            Write-Verbose -Message "Finished New-ZipFile"
        )
    }
    
    Write-Debug -Message "Starting Import-SmaPowerShellModule for [$ModuleName]"

    # Create a temp directory to zip the file to
    $TempDirectory   = "C:\temp\$([System.Guid]::NewGuid())"
    $DirectoryExists = Test-Path -Path $TempDirectory
    while($DirectoryExists)
    {
        $TempDirectory   = "C:\temp\$([System.Guid]::NewGuid())"
        $DirectoryExists = Test-Path -Path $TempDirectory
    }

    $ZipFilePath = "$tempDirectory\$($ModuleName)"
            
    New-ZipFile -SourceDir $ModuleRootPath `
                -ZipFilePath $ZipFilePath

    $import = Import-SmaModule -Path $ZipFilePath `
                               -WebServiceEndpoint $WebServiceEndpoint
        
    Write-Verbose -Message "Cleaning up filesystem"
    inlinescript { Remove-Item -Path $Using:TempDirectory -Recurse -Force -Confirm:$false } 
    
	New-VariableRunbookTrackingInstance -VariablePrefix 'TFSContinuousIntegration-SMAPSModuleDeploy' -WebServiceEndpoint $WebServiceEndpoint

    Write-Debug -Message "Finished Import-SmaPowerShellModule for [$ModuleName]"
}