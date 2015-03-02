<#
    Breaks in SMA -- Maximum stream length exceeded (5000000 bytes)

    This appears to be a limitation imposed within this file. “:\Program Files\Microsoft System Center 2012 R2\Service Management Automation\Orchestrator.Sandbox.exe.config"
 
    Which imposes the limit on the sandbox and I believe this is more to do with ASP.NET(?) than writing to the DB but not sure.
    Bumping this setting up in the file will allow it to complete but I can’t comment on whether this is safe and what max limit should be. The below setting bumped mine up to ~95 MB and that seemed to work without issue in SMA. 
 
    <?xml version="1.0"?>
    <configuration>
      <system.diagnostics configSource="Orchestrator.Sandbox.Diagnostics.config" />
      <startup useLegacyV2RuntimeActivationPolicy="true">
        <supportedRuntime version="v4.0" sku=".NETFramework,Version=v4.0"/>
      </startup>
      <appSettings>
        <add key="MaxStreamLength" value="100000000" />
      </appSettings>
    </configuration>
    
    ID	   Title	                                                            Assigned To	State	    Work Item Type
    389248 Maximum stream size that a runbook worker is configured with is low	Beth Cooper	Resolved	Bug
#>

Workflow Test-SMACheckPoint
{
    Write-Verbose -Message "Starting to create file"
    inlinescript 
    {
        if(Test-Path -Path "C:\temp\sizeTest.txt") { Remove-Item -Path "C:\temp\sizeTest.txt" -Force }
        for($i = 0; $i -lt 5000000/360; $i++)
        {
            $content = '............................................................' +
                       '............................................................' + 
                       '............................................................' +
                       '............................................................' +
                       '............................................................' +
                       '............................................................'
            Add-Content -Value $content -Path c:\temp\sizeTest.txt -Force
        }
    }
    Write-Verbose -Message "File Created - Checkpointing"
    Checkpoint-Workflow
    Write-Verbose -Message "Reading File"
    $var = Get-Content -Path "C:\temp\sizeTest.txt"
    Write-Verbose -Message "Checkpointing"
    Checkpoint-Workflow
    Write-Verbose -Message "Post Checkpoint Removing File"
    if(Test-Path -Path "C:\temp\sizeTest.txt") { inlinescript { Remove-Item -Path "C:\temp\sizeTest.txt" -Force } }
    Write-Verbose -Message "File Removed"
}
