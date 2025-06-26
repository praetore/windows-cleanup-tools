@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'LlmModule.psm1'

    # Version number of this module.
    ModuleVersion = '1.0.0'

    # ID used to uniquely identify this module
    GUID = 'f8dbc215-1f09-4d4a-9846-5e16c5212346'

    # Author of this module
    Author = 'Windows Cleanup Tools'

    # Description of the functionality provided by this module
    Description = 'LLM integration functions for Windows Cleanup Tools scripts'

    # Minimum version of the Windows PowerShell engine required by this module
    PowerShellVersion = '5.1'

    # Functions to export from this module
    FunctionsToExport = @(
        'Get-BatchLlmSuggestions'
    )

    # Cmdlets to export from this module
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess
    PrivateData = @{
        PSData = @{
            # Tags applied to this module
            Tags = @('Utility', 'FileManagement', 'LLM', 'AI')

            # A URL to the license for this module
            LicenseUri = ''

            # A URL to the main website for this project
            ProjectUri = ''
        }
    }
}
