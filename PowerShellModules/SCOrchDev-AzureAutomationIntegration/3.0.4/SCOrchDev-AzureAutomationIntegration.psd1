﻿#
# Module manifest for module 'ScorchDev-AzureAutomationIntegration'
#
# Generated by: Ryan Andorfer
#
# Generated on: 2014-12-20
#

@{

# Script module or binary module file associated with this manifest.
RootModule = '.\SCOrchDev-AzureAutomationIntegration.psm1'

# Version number of this module.
ModuleVersion = '3.0.4'

# ID used to uniquely identify this module
GUID = '1dafd04a-a2c2-4245-a2ba-69bfcd6bfe0a'

# Author of this module
Author = 'Ryan Andorfer'

# Company or vendor of this module
CompanyName = 'SCOrchDev'

# Copyright statement for this module
Copyright = '(c) SCOrchDev. All rights reserved.'

# Description of the functionality provided by this module
Description = 'Integration wrapper for Azure Automation'

# Minimum version of the Windows PowerShell engine required by this module
PowerShellVersion = '4.0'

# Name of the Windows PowerShell host required by this module
# PowerShellHostName = ''

# Minimum version of the Windows PowerShell host required by this module
# PowerShellHostVersion = ''

# Minimum version of Microsoft .NET Framework required by this module
# DotNetFrameworkVersion = ''

# Minimum version of the common language runtime (CLR) required by this module
# CLRVersion = ''

# Processor architecture (None, X86, Amd64) required by this module
# ProcessorArchitecture = ''

# Modules that must be imported into the global environment prior to importing this module
RequiredModules = @('SCOrchDev-Utility', 'SCOrchDev-GitIntegration', 'SCOrchDev-Exception')

# Assemblies that must be loaded prior to importing this module
# RequiredAssemblies = @()

# Script files (.ps1) that are run in the caller's environment prior to importing this module.
# ScriptsToProcess = @()

# Type files (.ps1xml) to be loaded when importing this module
# TypesToProcess = @()

# Format files (.ps1xml) to be loaded when importing this module
# FormatsToProcess = @()

# Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
# NestedModules = @()

# Functions to export from this module
FunctionsToExport = '*'

# Cmdlets to export from this module
CmdletsToExport = '*'

# Variables to export from this module
VariablesToExport = '*'

# Aliases to export from this module
AliasesToExport = '*'

# List of all modules packaged with this module
ModuleList = @('SCOrchDev-AzureAutomationIntegration')

# List of all files packaged with this module
FileList = @('SCOrchDev-AzureAutomationIntegration.psd1', 'SCOrchDev-AzureAutomationIntegration.psm1', 'LICENSE', 'README.md', '.\Tests\SCOrchDev-AzureAutomationIntegration.tests.ps1', 'appveyor.yml')

# Private data to pass to the module specified in RootModule/ModuleToProcess
# PrivateData = ''

# HelpInfo URI of this module
# HelpInfoURI = ''

# Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
# DefaultCommandPrefix = ''
}
