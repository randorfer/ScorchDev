@{
RootModule = 'LocalDev.psm1'
ModuleVersion = '1.4.0'
GUID = '06011173-a954-4b8d-a6c4-c9015af47702'
Author = 'Scorch Dev'
CompanyName = 'Scorch Dev'
Copyright = ''
Description = 'Useful utilites for local SMA development'
PowerShellVersion = '4.0'
FunctionsToExport = '*'
RequiredModules = @('SCOrchDev-Utility')
CmdletsToExport = '*'
VariablesToExport = @()
AliasesToExport = @()
ModuleList = @('LocalDev')
FileList = @('LocalDev.psd1', 'LocalDev.psm1', 'EmulatedAutomationActivitiesInner.psm1')
NestedModules = @('.\EmulatedAutomationActivitiesInner.psm1')
}

