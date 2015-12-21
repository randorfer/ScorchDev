#requires -Version 3 -Modules SCOrchDev-Exception
<#
.Synopsis
    Creates a zip file from a target directory
    
.Parameter SourceDir
    The directory to zip up

.Parameter ZipFilePath
    The path to store the new zip file at

.Parameter OverwriteExisting
    If the zip file already exists should it be overwritten. Default: True
#>
Function New-ZipFile
{
    Param(
        [Parameter(Mandatory = $True)]
        [string]
        $SourceDir,

        [Parameter(Mandatory = $True)]
        [string]
        $ZipFilePath,
    
        [Parameter(Mandatory = $False)]
        [bool]
        $OverwriteExisting = $True
    )
            
    $Null = $(
        Write-Verbose -Message 'Starting [New-ZipFile]'
        Write-Verbose -Message "`$SourceDir [$SourceDir]"
        Write-Verbose -Message "`$ZipFilePath [$ZipFilePath]"
                
        if($OverwriteExisting)
        {
            if(Test-Path -Path $ZipFilePath)
            {
                Remove-Item -Path $ZipFilePath -Force -Confirm:$False
            }
        }

        if(-not (Test-Path -Path "$($ZipFilePath.Substring(0,$ZipFilePath.LastIndexOf('\')))"))
        {
            $null = New-Item -ItemType Directory `
                             -Path "$($ZipFilePath.Substring(0,$ZipFilePath.LastIndexOf('\')))" `
                             -Force `
                             -Confirm:$False
        }

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $CompressionLevel = [System.IO.Compression.CompressionLevel]::Optimal
        [System.IO.Compression.ZipFile]::CreateFromDirectory($SourceDir, $ZipFilePath, $CompressionLevel, $False)
        Write-Verbose -Message 'Finished [New-ZipFile]'
    )
}
<#
.Synopsis
    Creates a new empty temporary directory
    
.Parameter Root
    The root path to create the temporary directory under
#>
Function New-TempDirectory
{
    [OutputType([System.IO.DirectoryInfo])]
    Param(
        [Parameter(Mandatory = $False, ValueFromPipeline = $True)]
        [string]
        $SourceDir = "$($env:SystemDrive)\"
    )
    
    do
    {
        $TempDirectory   = "$($SourceDir)\$([System.Guid]::NewGuid())"
        $DirectoryExists = Test-Path -Path $TempDirectory
    }
    while($DirectoryExists)

    New-Item -ItemType Directory -Path $TempDirectory
}

<#
.SYNOPSIS
    Gets file encoding. From http://poshcode.org/2059
    
.DESCRIPTION
    The Get-FileEncoding function determines encoding by looking at Byte Order Mark (BOM).
    Based on port of C# code from http://www.west-wind.com/Weblog/posts/197245.aspx
    
.EXAMPLE
    Get-ChildItem  *.ps1 | select FullName, @{n='Encoding';e={Get-FileEncoding $_.FullName}} | where {$_.Encoding -ne 'ASCII'}
    This command gets ps1 files in current directory where encoding is not ASCII

.EXAMPLE
    Get-ChildItem  *.ps1 | select FullName, @{n='Encoding';e={Get-FileEncoding $_.FullName}} | where {$_.Encoding -ne 'ASCII'} | foreach {(get-content $_.FullName) | set-content $_.FullName -Encoding ASCII}
    Same as previous example but fixes encoding using set-content
#>
Function Get-FileEncoding
{
    [OutputType([string])]
    Param ( 
        [Parameter(Mandatory = $True, ValueFromPipeline = $True)] 
        [string]$Path 
    )
 
    [byte[]]$byte = Get-Content -Encoding byte -ReadCount 4 -TotalCount 4 -Path $Path
    if ( $byte[0] -eq 0xef -and $byte[1] -eq 0xbb -and $byte[2] -eq 0xbf )
    {
        Return 'UTF8'
    }
    elseif ($byte[0] -eq 0xfe -and $byte[1] -eq 0xff)
    {
        Return 'Unicode'
    }
    elseif ($byte[0] -eq 0 -and $byte[1] -eq 0 -and $byte[2] -eq 0xfe -and $byte[3] -eq 0xff)
    {
        Return 'UTF32'
    }
    elseif ($byte[0] -eq 0x2b -and $byte[1] -eq 0x2f -and $byte[2] -eq 0x76)
    {
        Return 'UTF7'
    }
    Return 'ASCII'
}
<#
.Synopsis
    Converts a filt to UTF8

.Parameter Path
    The path to the file to convert
#>
Function ConvertTo-UTF8
{
    Param ( 
        [Parameter(Mandatory = $True, ValueFromPipeline = $True)] 
        [string]$Path 
    )
    $File = Get-Item -Path $Path
    $content = Get-Content -Path $Path
    if ( $Null -ne $content ) 
    {
        Remove-Item -Path $File.FullName -Force
        $content | Out-File -FilePath $File.FullName -Encoding utf8
    } 
    else
    {
        Throw-Exception -Type 'NoContentFound' `
        -Message 'Could not read the file' `
        -Property @{
            'Path'  = $Path
            'File'  = $(ConvertTo-Json -InputObject $File)
            'Content' = $content
        }
    }
}
<#
.Synopsis
    Takes a passed item path and creates the container if it does not already exist
    
.Parameter FileItemPath
    The path to the file who's container object will be created if it does not already exist
#>
Function New-FileItemContainer
{
    Param(
        [Parameter(Mandatory = $True, ValueFromPipeline = $True)]
        $FileItemPath
    )
    
    $ContainerPath = $FileItemPath -replace '[^\\]+$', ''
    if(-Not (Test-Path -Path $ContainerPath))
    {
        Write-Verbose -Message 'Creating Directory'
        New-Item -ItemType Directory -Path $ContainerPath
    }
    else
    {
        Write-Verbose -Message 'Directory Existed'
        Get-Item -Path $ContainerPath
    }
}
<#
.SYNOPSIS
    Returns $True if the passed string is a UNC path, $False otherwise.

.PARAMETER String
    The string to evaluate.
#>
Function Test-UncPath
{
    param([Parameter(Mandatory=$True)] [String] $String)

    # TODO: Do we need more sophisticated logic for this?
    return $String.StartsWith('\\')
}
Export-ModuleMember -Function * -Verbose:$False -Debug:$False