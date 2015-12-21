$here = Split-Path -Parent $MyInvocation.MyCommand.Path

$manifestPath = "$here\SCOrchDev-Exception.psd1"
Import-Module SCOrchDev-Exception -Force
Describe -Tags 'VersionChecks' 'SCOrchDev-Exception manifest' {
    $script:manifest = $null
    It 'has a valid manifest' {
        {
            $script:manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop -WarningAction SilentlyContinue
        } | Should Not Throw
    }

    It 'has a valid name in the manifest' {
        $script:manifest.Name | Should Be SCOrchDev-Exception
    }

    It 'has a valid guid in the manifest' {
        $script:manifest.Guid | Should Be '41d1dfce-c2f0-42e5-b4b0-43eac2226fcd'
    }

    It 'has a valid version in the manifest' {
        $script:manifest.Version -as [Version] | Should Not BeNullOrEmpty
    }

    if (Get-Command git.exe -ErrorAction SilentlyContinue) {
        $script:tagVersion = $null
        It 'is tagged with a valid version' {
            $cwd = get-location
            Set-Location ($Path -as [System.IO.FileInfo]).Directory
            $thisCommit = git.exe log --decorate --oneline HEAD~1..HEAD
            Set-Location $cwd
            if ($thisCommit -match 'tag:\s*(\d+(?:\.\d+)*)')
            {
                $script:tagVersion = $matches[1]
            }

            $script:tagVersion                  | Should Not BeNullOrEmpty
            $script:tagVersion -as [Version]    | Should Not BeNullOrEmpty
            
        }

        It 'all versions are the same' {
            $script:manifest.Version -as [Version] | Should be ( $script:tagVersion -as [Version] )
        }

    }

    It 'should have all files listed in the FileList' {
        $ModuleFiles = (Get-ChildItem -Path $here -Recurse -Exclude .git).FullName
        $FileDifferences = Compare-Object -ReferenceObject $ModuleFiles -DifferenceObject $script:manifest.FileList
        
        if (($FileDifferences -as [array]).Count -gt 0)
        {
            Throw-Exception -Type 'MissingFiles' `
                            -Message 'Files missing or not tracked in FileList' `
                            -Property @{
                'Missing Files' = ($FileDifferences | Where-Object {$_.SideIndicator -eq '=>'}).InputObject ;
                'Non Tracked Files' = ($FileDifferences | Where-Object {$_.SideIndicator -eq '<='}).InputObject ;
            }
        }
    }
}

if ($PSVersionTable.PSVersion.Major -ge 3)
{
    $error.Clear()
    Describe 'Clean treatment of the $error variable' {
        Context 'A Context' {
            It 'Performs a successful test' {
                $true | Should Be $true
            }
        }

        It 'Did not add anything to the $error variable' {
            $error.Count | Should Be 0
        }
    }
}

Describe 'Style rules' {
    $SCOrchDevExceptionRoot = (Get-Module SCOrchDev-Exception).ModuleBase

    $files = @(
        Get-ChildItem $SCOrchDevExceptionRoot -Include *.ps1,*.psm1
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
Describe 'Select-CustomException'{
    $ExceptionOutput = '{"__CUSTOM_EXCEPTION__":true,"InnerException":null,"Message":"a","FullyQualifiedErrorId":"a","Type":"a"}'
    Context 'PSScript' {
        Function Test-SelectCustomException
        {
            try { Throw-Exception -Type 'a' -Message 'a' } catch { Select-CustomException -Exception $_ }
        }
        Function Test-SelectNonCustomException
        {
            try { Throw 'a' } catch { Select-CustomException -Exception $_ }
        }
        It 'Should Detect custom exceptions' {
            Test-SelectCustomException | Should Be $ExceptionOutput
        }
        It 'Should ignore non custom exceptions' {
            Test-SelectNonCustomException | Should BeNullOrEmpty
        }
    }
    Context 'PSWorkflow' {
        Workflow Test-SelectCustomException
        {
            try { Throw-Exception -Type 'a' -Message 'a' } catch { Select-CustomException -Exception $_ }
        }
        Workflow Test-SelectNonCustomException
        {
            try { Throw 'a' } catch { Select-CustomException -Exception $_ }
        }
        It 'Should Detect custom exceptions' {
            Test-SelectCustomException | Should Be $ExceptionOutput
        }
        It 'Should ignore non custom exceptions' {
            Test-SelectNonCustomException | Should BeNullOrEmpty
        }
    }
}
Describe 'Get ExceptionInfo' {
    Context 'PSScript' {
        $Message = 'a'
        $Type = 'b'
        Function Test-GetExceptionInfoCustomException
        {
            Param($Message, $Type)
            try { Throw-Exception -Type $Type -Message $Message } catch { Get-ExceptionInfo -Exception $_ | ConvertTo-JSON -Compress }
        }
        Function Test-GetExceptionInfoNonCustomException
        {
            Param($Message)
            try { Throw $Message } catch { Get-ExceptionInfo -Exception $_ | ConvertTo-JSON -Compress }
        }
        It 'Custom Exceptions should retain the mesage thrown when intertpreted by Get-ExceptionInfo' {
            (Test-GetExceptionInfoCustomException -Message $Message -Type $Type | ConvertFrom-JSON).Message | Should Be $Message
        }
        It 'Custom Exceptions should retain their type when intertpreted by Get-ExceptionInfo' {
            (Test-GetExceptionInfoCustomException -Message $Message -Type $Type | ConvertFrom-JSON).Type | Should Be $Type
        }
        It 'Non Custom Exceptions should retain the mesage thrown when intertpreted by Get-ExceptionInfo' {
            (Test-GetExceptionInfoNonCustomException -Message $Message | ConvertFrom-JSON).Message | Should Be $Message
        }
    }
    Context 'PSWorkflow' {
        $Message = 'a'
        $Type = 'b'
        Workflow Test-GetExceptionInfoCustomException
        {
            Param($Message, $Type)
            try { Throw-Exception -Type $Type -Message $Message } catch { Get-ExceptionInfo -Exception $_ | ConvertTo-JSON -Compress }
        }
        Workflow Test-GetExceptionInfoNonCustomException
        {
            Param($Message)
            try { Throw $Message } catch { Get-ExceptionInfo -Exception $_ | ConvertTo-JSON -Compress }
        }
        It 'Custom Exceptions should retain the mesage thrown when intertpreted by Get-ExceptionInfo' {
            (Test-GetExceptionInfoCustomException -Message $Message -Type $Type | ConvertFrom-JSON).Message | Should Be $Message
        }
        It 'Custom Exceptions should retain their type when intertpreted by Get-ExceptionInfo' {
            (Test-GetExceptionInfoCustomException -Message $Message -Type $Type | ConvertFrom-JSON).Type | Should Be $Type
        }
        It 'Non Custom Exceptions should retain the mesage thrown when intertpreted by Get-ExceptionInfo' {
            (Test-GetExceptionInfoNonCustomException -Message $Message | ConvertFrom-JSON).Message | Should Be $Message
        }
    }
}
Describe 'Write-Exception' {
    InModuleScope ScorchDev-Exception {
        Mock Write-Warning {
            Param(
                $Message
            )
            'Warning'
        }
        Mock Write-Verbose {
            Param(
                $Message
            )
            'Verbose'
        }
        Mock Write-Error {
            Param(
                $Message
            )
            'Error'
        }
        Mock Write-Debug {
            Param(
                $Message
            )
            'Debug'
        } -ParameterFilter { $Message -like 'Exception information*' }
        Context 'PowerShell Script' {
            Function Test-WriteException 
            {
                Param($ExceptionType, $ExceptionMessage, $ExceptionProperty, $Stream)
                
                Try
                {
                    Throw-Exception -Type 'a' -Message 'b'
                }
                Catch
                {
                    if($Stream -as [bool])
                    {
                        Write-Exception -Exception $_ -Stream $Stream
                    }
                    else
                    {
                        Write-Exception -Exception $_
                    }
                }
            }

            It 'Should write to the warning stream properly'{
                Test-WriteException @TestParams -Stream Warning | Should Be 'Warning'
            }

            It 'Should write to the verbose stream properly'{
                Test-WriteException @TestParams -Stream Verbose | Should Be 'Verbose'
            }

            It 'Should write to the debug stream properly'{
                Test-WriteException @TestParams -Stream Debug | Should Be 'Debug'
            }

            It 'Should write to the error stream properly'{
                Test-WriteException @TestParams -Stream Error | Should Be 'Error'
            }

            It 'Should write to the warning stream if no stream is specified'{
                Test-WriteException @TestParams | Should Be 'Warning'
            }
        }
    }
}