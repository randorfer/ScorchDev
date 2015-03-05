<#
    .Synopsis
        Foo Bar!
#>
Function foo
{
    Write-Verbose 'bar'
}
<#
    .Synopsis
        Foo Bar!
#>
Function bar
{
    Write-Verbose 'foo'
}
Export-ModuleMember -Function * -Verbose:$false