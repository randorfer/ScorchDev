$here = Split-Path -Parent $MyInvocation.MyCommand.Path

$ModuleRoot = "$here\.."
$manifestPath = "$ModuleRoot\SCOrchDev-AzureAutomationIntegration.psd1"
Import-Module $manifestPath -Force -Scope Local

Describe 'Style rules' {
    $_ModuleBase = (Get-Module SCOrchDev-AzureAutomationIntegration).ModuleBase

    $files = @(
        Get-ChildItem $_ModuleBase -Include *.ps1,*.psm1
    )

    It 'Module source files contain no trailing whitespace' {
        $badLines = @(
            foreach ($file in $files)
            {
                $lines = [System.IO.File]::ReadAllLines($file.FullName)
                $lineCount = $lines.Count

                for ($i = 0; $i -lt $lineCount; $i++)
                {
                    if ($lines[$i] -match '\s+$')
                    {
                        'File: {0}, Line: {1}' -f $file.FullName, ($i + 1)
                    }
                }
            }
        )

        if ($badLines.Count -gt 0)
        {
            throw "The following $($badLines.Count) lines contain trailing whitespace: `r`n`r`n$($badLines -join "`r`n")"
        }
    }

    It 'Module Source Files all end with a newline' {
        $badFiles = @(
            foreach ($file in $files)
            {
                $string = [System.IO.File]::ReadAllText($file.FullName)
                if ($string.Length -gt 0 -and $string[-1] -ne "`n")
                {
                    $file.FullName
                }
            }
        )

        if ($badFiles.Count -gt 0)
        {
            throw "The following files do not end with a newline: `r`n`r`n$($badFiles -join "`r`n")"
        }
    }
}

Describe 'ConvertFrom-AutomationDescriptionTagLine' {
    InModuleScope -ModuleName SCOrchDev-AzureAutomationIntegration {
        Context 'When passed a description string with a tag section' {
            $RepositoryName = 'AAAAAAAAA'
            $CurrentCommit = 'BBBBBBBB'
            $DescriptionString = "__RepositoryName:$RepositoryName;CurrentCommit:$CurrentCommit;__"
            $Return = ConvertFrom-AutomationDescriptionTagLine -InputObject $DescriptionString
            It 'Should return an object with a CurrentCommit property' {
                $Return.ContainsKey('CurrentCommit') | Should Be $True
            }
            It 'Should have the proper value in current commit' {
                $Return.CurrentCommit | Should Match $CurrentCommit
            }
            It 'Should return an object with RepositoryName property' {
                $Return.ContainsKey('RepositoryName') | Should Be $True
            }
            It 'Should have the proper value in Repository Name' {
                $Return.RepositoryName | Should Match $RepositoryName
            }
            It 'Should return an object with Description property' {
                $Return.ContainsKey('Description') | Should Be $True
            }
            It 'Should have the proper value in Description' {
                $Return.Description | Should Match $DescriptionString
            }
        }
    }
}

Describe 'Converting a AutomationDescription Tag Line' {
    InModuleScope -ModuleName SCOrchDev-AzureAutomationIntegration {
        $RepositoryName = 'AAAAAAAAA'
        $CurrentCommit = 'BBBBBBBB'
        $DescriptionString = "__RepositoryName:$RepositoryName;CurrentCommit:$CurrentCommit;__"
        $Return = ConvertFrom-AutomationDescriptionTagLine -InputObject $DescriptionString
        $NewRepositoryName = 'CCCCCCCCC'
        $NewCommit = 'DDDDDDDD'
        $UpdatedString = ConvertTo-AutomationDescriptionTagLine `
            -Description $Return.Description `
            -CurrentCommit $NewCommit `
            -RepositoryName $NewRepositoryName

        Context 'Converting a string to a Description Hashtable' {
            It 'Should return an object with a CurrentCommit property' {
                $Return.ContainsKey('CurrentCommit') | Should Be $True
            }
            It 'Should have the proper value in current commit' {
                $Return.CurrentCommit | Should Match $CurrentCommit
            }
            It 'Should return an object with RepositoryName property' {
                $Return.ContainsKey('RepositoryName') | Should Be $True
            }
            It 'Should have the proper value in Repository Name' {
                $Return.RepositoryName | Should Match $RepositoryName
            }
            It 'Should return an object with Description property' {
                $Return.ContainsKey('Description') | Should Be $True
            }
            It 'Should have the proper value in Description' {
                $Return.Description | Should Match $DescriptionString
            }
        }
        Context 'Converting an updated Description Hashtable' {
            It 'Should have a properly updated Current Commit' {
                $UpdatedString | Should Match "__RepositoryName:$NewRepositoryName;"
            }
            It 'Should have a properly updated RepositoryName' {
                $UpdatedString | Should Match "CurrentCommit:$NewCommit;__"
            }
        }
    }
}