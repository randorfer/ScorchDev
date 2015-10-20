workflow invoke-reproduction-playfair
{
    $starttime = get-date
    while($true)
    {
        $ElapsedTime = ((Get-Date)-$StartTime).TotalSeconds
        Write-Verbose -Message "Elapsed Time [$("{0:N0}" -f $ElapsedTime)] Seconds"
        Start-Sleep -Seconds 5
    }
}