<#
    .SYNOPSIS
        Creates scaffold template instance.

    .PARAMETER Path
        The full path in which to create the scaffold templates
        Ex: C:\temp

    .PARAMETER Name
        The scaffold name to use
        
    .PARAMETER Template
        The template to use 
#>
Function New-Scaffold
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$False)]
        [String]$Path = $PWD,

        [Parameter(Mandatory=$True)]
        [String]$Name
    )
    DynamicParam {
        $attributes = new-object System.Management.Automation.ParameterAttribute
        $attributes.ParameterSetName = '__AllParameterSets'
        $attributes.Mandatory = $true
        $attributeCollection = new-object -Type System.Collections.ObjectModel.Collection[System.Attribute]
        $attributeCollection.Add($attributes)
        $_Values = (Get-ChildItem -Path "$PSScriptRoot\Templates\*").Name
        $ValidateSet = new-object System.Management.Automation.ValidateSetAttribute($_Values)
        $attributeCollection.Add($ValidateSet)
        $dynParam1 = new-object -Type System.Management.Automation.RuntimeDefinedParameter('Template', [string], $attributeCollection)
        $paramDictionary = new-object -Type System.Management.Automation.RuntimeDefinedParameterDictionary
        $paramDictionary.Add('Template', $dynParam1)
        return $paramDictionary 
    }
    Process {
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
        $Template = $PSBoundParameters.Template
        $CompletedParams = Write-StartingMessage -String "Template [$Template] Name [$Name]"
    
        $TemplateCode = Get-Content -Path "$PSScriptRoot\Templates\$Template"

        # Look up table is used as a map <Key=template reference, Value=replace template value>
        $lookupTable = @{
            '#name#' = $($Name)
        }
   
        $lookupTable.GetEnumerator() | ForEach-Object {
              if($_.Key -eq '#name#')
              {
                $TemplateCode = $TemplateCode -replace $_.Key, $_.Value
              }
        }
    
        if (-not (Test-Path -Path $Path)) 
        {
            New-Item -ItemType Directory -Path $Path | Out-Null
        }

        $FullPath = Join-Path -Path $Path -ChildPath $Name
        if($FullPath -notlike '*.ps1') { $FullPath = "$FullPath.ps1" }
        if (-not (Test-Path -Path $FullPath)) 
        {
            Set-Content -Path $FullPath -Value $TemplateCode -Encoding UTF8
            Get-Item -Path $FullPath
        }
        else
        {
            Write-Warning "Skipping the file '$FullPath', because it already exists." -WarningAction Continue
        }

        Write-CompletedMessage @CompletedParams
    }
}
Export-ModuleMember -Function * -Verbose:$false