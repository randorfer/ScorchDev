<#
    .Synopsis
        Foo Bar!
#>
Function foo
{
    Write-Verbose 'bar'
}
Export-ModuleMember -Function * -Verbose:$false