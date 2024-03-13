<#
.SYNOPSIS

PSApppDeployToolkit - This script performs the installation or uninstallation of an application(s).

.DESCRIPTION

- The script is provided as a template to perform an install or uninstall of an application(s).
- The script either performs an "Install" deployment type or an "Uninstall" deployment type.
- The install deployment type is broken down into 3 main sections/phases: Pre-Install, Install, and Post-Install.

The script dot-sources the AppDeployToolkitMain.ps1 script which contains the logic and functions required to install or uninstall an application.

PSApppDeployToolkit is licensed under the GNU LGPLv3 License - (C) 2023 PSAppDeployToolkit Team (Sean Lillis, Dan Cunningham and Muhammad Mashwani).

This program is free software: you can redistribute it and/or modify it under the terms of the GNU Lesser General Public License as published by the
Free Software Foundation, either version 3 of the License, or any later version. This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License
for more details. You should have received a copy of the GNU Lesser General Public License along with this program. If not, see <http://www.gnu.org/licenses/>.

.PARAMETER DeploymentType

The type of deployment to perform. Default is: Install.

.PARAMETER DeployMode

Specifies whether the installation should be run in Interactive, Silent, or NonInteractive mode. Default is: Interactive. Options: Interactive = Shows dialogs, Silent = No dialogs, NonInteractive = Very silent, i.e. no blocking apps. NonInteractive mode is automatically set if it is detected that the process is not user interactive.

.PARAMETER AllowRebootPassThru

Allows the 3010 return code (requires restart) to be passed back to the parent process (e.g. SCCM) if detected from an installation. If 3010 is passed back to SCCM, a reboot prompt will be triggered.

.PARAMETER TerminalServerMode

Changes to "user install mode" and back to "user execute mode" for installing/uninstalling applications for Remote Desktop Session Hosts/Citrix servers.

.PARAMETER DisableLogging

Disables logging to file for the script. Default is: $false.

.EXAMPLE

powershell.exe -Command "& { & '.\Deploy-Application.ps1' -DeployMode 'Silent'; Exit $LastExitCode }"

.EXAMPLE

powershell.exe -Command "& { & '.\Deploy-Application.ps1' -AllowRebootPassThru; Exit $LastExitCode }"

.EXAMPLE

powershell.exe -Command "& { & '.\Deploy-Application.ps1' -DeploymentType 'Uninstall'; Exit $LastExitCode }"

.EXAMPLE

Deploy-Application.exe -DeploymentType "Install" -DeployMode "Silent"

.INPUTS

None

You cannot pipe objects to this script.

.OUTPUTS

None

This script does not generate any output.

.NOTES

Toolkit Exit Code Ranges:
- 60000 - 68999: Reserved for built-in exit codes in Deploy-Application.ps1, Deploy-Application.exe, and AppDeployToolkitMain.ps1
- 69000 - 69999: Recommended for user customized exit codes in Deploy-Application.ps1
- 70000 - 79999: Recommended for user customized exit codes in AppDeployToolkitExtensions.ps1

.LINK

https://psappdeploytoolkit.com
#>


[CmdletBinding()]
Param (
    [Parameter(Mandatory = $false)]
    [ValidateSet('Install', 'Uninstall', 'Repair')]
    [String]$DeploymentType = 'Install',
    [Parameter(Mandatory = $false)]
    [ValidateSet('Interactive', 'Silent', 'NonInteractive')]
    [String]$DeployMode = 'Interactive',
    [Parameter(Mandatory = $false)]
    [switch]$AllowRebootPassThru = $false,
    [Parameter(Mandatory = $false)]
    [switch]$TerminalServerMode = $false,
    [Parameter(Mandatory = $false)]
    [switch]$DisableLogging = $false
)

function Get-ChromeVersion {
    # Get latest Google Chrome versions from public JSON feed
    # Alex Entringer 2024-03-12
    [CmdletBinding()]
    param (

        [Parameter(Mandatory = $False)]
        [ValidateSet('win', 'win64', 'mac', 'mac_arm64', 'linux', 'ios', 'lacros', 'android', 'webview')]
        [string]$Platform = 'win64',

        [Parameter(Mandatory = $False)]
        [ValidateSet('extended', 'stable', 'beta', 'dev', 'canary', 'canary_asan')]
        [string]$Channel = 'stable'
    )
    # Read the JSON and convert to a PowerShell object. Return the current release version of Chrome
    try {
        [uri]$Uri = "https://versionhistory.googleapis.com/v1/chrome/platforms/$($Platform)/channels/$($Channel)/versions/all/releases?filter=endtime=none&order_by=version%20desc"
        $ChromeVersions = Invoke-RestMethod -Method 'Get' -Uri $($Uri.AbsoluteUri) -UseBasicParsing -ErrorAction 'Stop'
        $LatestChromeValue = $ChromeVersions[0]

        $Output = [PSCustomObject]@{
            Channel = $Channel
            Platform = $Platform
            Version = $LatestChromeValue.version
            PublishedTime = $LatestChromeValue.serving.starttime
        }
        return $Output
    }
    catch {
        Write-Host "Chrome was not detected: Problem gathering version information from '$($Uri.AbsoluteUri)' $($_)"
        exit 1
    }
}

try {
    $Data = Get-Content -Path "$PSScriptRoot\*-AppSettings.json" -Raw | ConvertFrom-Json -ErrorAction 'Stop'
}
catch {
    if (Test-Path -LiteralPath 'variable:HostInvocation') {$script:ExitCode = 69000; exit} else { exit 69000}
}

try {
    $JsonFileValues = @(
        'Name'
        'Version'
        'Vendor'
        'Date'
        'ScriptVersion'
        'ScriptAuthor'
    )

    foreach ($Item in $JsonFileValues) {
        if ([string]::IsNullOrEmpty($($Data.$Item))) {
            if (Test-Path -LiteralPath 'variable:HostInvocation') {$script:ExitCode = 69001; exit} else { exit 69001}
        }
    }
}
catch {
    if (Test-Path -LiteralPath 'variable:HostInvocation') {$script:ExitCode = 69001; exit} else { exit 69001}
}

try {
    $ChromeDetails = Get-ChromeVersion

    foreach ($Item in $ChromeDetails.psobject.properties.name) {
        if ([string]::IsNullOrEmpty($($ChromeDetails.$Item))) {
            if (Test-Path -LiteralPath 'variable:HostInvocation') { $script:ExitCode = 69002; exit } else { exit 69002 }
        }
    }
}
catch {
    if (Test-Path -LiteralPath 'variable:HostInvocation') { $script:ExitCode = 69002; exit } else { exit 69002 }
}


Try {
    ## Set the script execution policy for this process
    Try {
        Set-ExecutionPolicy -ExecutionPolicy 'ByPass' -Scope 'Process' -Force -ErrorAction 'Stop'
    }
    Catch {
    }

    ##*===============================================
    ##* VARIABLE DECLARATION
    ##*===============================================
    ## Variables: Application
    [string]$appVendor = $($Data.Vendor)
    [string]$appName = $($Data.Name)
    [string]$appVersion = $ChromeDetails.Version
    [string]$appArch = ''
    [string]$appLang = 'EN'
    [string]$appRevision = '01'
    [string]$appScriptVersion = $($Data.ScriptVersion)
    [string]$appScriptDate = $($Data.Date)
    [string]$appScriptAuthor = $($Data.ScriptAuthor)
    ##*===============================================
    ## Variables: Install Titles (Only set here to override defaults set by the toolkit)
    [String]$installName = ''
    [String]$installTitle = ''

    ##* Do not modify section below
    #region DoNotModify

    ## Variables: Exit Code
    [Int32]$mainExitCode = 0

    ## Variables: Script
    [String]$deployAppScriptFriendlyName = 'Deploy Application'
    [Version]$deployAppScriptVersion = [Version]'3.9.3'
    [String]$deployAppScriptDate = '02/05/2023'
    [Hashtable]$deployAppScriptParameters = $PsBoundParameters

    ## Variables: Environment
    If (Test-Path -LiteralPath 'variable:HostInvocation') {
        $InvocationInfo = $HostInvocation
    }
    Else {
        $InvocationInfo = $MyInvocation
    }
    [String]$scriptDirectory = Split-Path -Path $InvocationInfo.MyCommand.Definition -Parent

    ## Dot source the required App Deploy Toolkit Functions
    Try {
        [String]$moduleAppDeployToolkitMain = "$scriptDirectory\AppDeployToolkit\AppDeployToolkitMain.ps1"
        If (-not (Test-Path -LiteralPath $moduleAppDeployToolkitMain -PathType 'Leaf')) {
            Throw "Module does not exist at the specified location [$moduleAppDeployToolkitMain]."
        }
        If ($DisableLogging) {
            . $moduleAppDeployToolkitMain -DisableLogging
        }
        Else {
            . $moduleAppDeployToolkitMain
        }
    }
    Catch {
        If ($mainExitCode -eq 0) {
            [Int32]$mainExitCode = 60008
        }
        Write-Error -Message "Module [$moduleAppDeployToolkitMain] failed to load: `n$($_.Exception.Message)`n `n$($_.InvocationInfo.PositionMessage)" -ErrorAction 'Continue'
        ## Exit the script, returning the exit code to SCCM
        If (Test-Path -LiteralPath 'variable:HostInvocation') {
            $script:ExitCode = $mainExitCode; Exit
        }
        Else {
            Exit $mainExitCode
        }
    }

    #endregion
    ##* Do not modify section above
    ##*===============================================
    ##* END VARIABLE DECLARATION
    ##*===============================================

    If ($deploymentType -ine 'Uninstall' -and $deploymentType -ine 'Repair') {
        ##*===============================================
        ##* PRE-INSTALLATION
        ##*===============================================
        [String]$installPhase = 'Pre-Installation'

        try {
            [string]$installPhase = 'Pre-Installation'
            [string]$ChromeFileName = "GoogleChromeEnterprise-$($appVersion).msi"
            [string]$ChromeDownloadPath = "$dirFiles\$ChromeFileName"
            [uri]$ChromeUrl = 'https://dl.google.com/tag/s/dl/chrome/install/googlechromestandaloneenterprise64.msi'

            $CurrentPreference = $ProgressPreference
            $ProgressPreference = 'SilentlyContinue'
            Write-Log -Message "Checking if the following path exists '$ChromeDownloadPath'" -Source 'Test-Path'
            if (-not (Test-Path -Path $ChromeDownloadPath -PathType 'Leaf')) {
                Write-Log -Message "Downloading '$ChromeFilename' from '$($ChromeUrl.AbsoluteUri)' to '$ChromeDownloadPath'" -Source 'Invoke-WebRequest'
                Invoke-WebRequest -Uri $($ChromeUrl.AbsoluteUri) -OutFile $ChromeDownloadPath -UseBasicParsing -ErrorAction 'Stop'
            }
        }
        catch {
            Write-Log -Message "Something went wrong with downloading '$ChromeDownloadPath' from '$($ChromeUrl.AbsoluteUri)'. Exiting with 69003. Error: $($_)"  -Source 'Invoke-WebRequest' -Severity 3
            Exit-Script -ExitCode 69003
        }
        finally {
            $ProgressPreference = $CurrentPreference
        }

        ## Show Welcome Message, close Chrome with a countdown of 2700 seconds (45 minutes)
        Show-InstallationWelcome -AllowDeferCloseApps -DeferTimes 1 -CloseApps 'chrome' -ForceCloseAppsCountdown 2700 -MinimizeWindows $false

        ## Show Progress Message (with the default message)
        Show-InstallationProgress -WindowLocation 'BottomRight' -TopMost $false

        ## <Perform Pre-Installation tasks here>
        try {
            [string]$InitialPrefFilePath = "${env:ProgramFiles}\Google\Chrome\Application\initial_preferences"
            Write-Log -Message "Checking if the following path exists '$InitialPrefFilePath'" -Source 'Test-Path'
            if (Test-Path -Path "$InitialPrefFilePath" -PathType 'Leaf') {
                Write-Log -Message "'$InitialPrefFilePath' file found, removing file" -Source 'Remove-Item'
                Remove-Item -Path "$InitialPrefFilePath" -Force -Confirm:$false -ErrorAction 'Stop'
            }
        }
        catch {
            Write-Log -Message "There was a problem deleting the initial_preferences: '$InitialPrefFilePath'. Exiting with error code 69004. Error: $($_)" -Source 'Remove-Item' -Severity 3
            Exit-Script -ExitCode 69004
        }

        ##*===============================================
        ##* INSTALLATION
        ##*===============================================
        [String]$installPhase = 'Installation'

        ## <Perform Installation tasks here>
        try {
            $InstallChromeArgs = @(
                '/qn'
                'NOGOOGLEUPDATEPING=1'
                'REBOOT=ReallySuppress'
            )

            Write-Log -Message "Attempting to install '$ChromeFileName' from '$ChromeDownloadPath'" -Source 'Execute-MSI'
            Execute-MSI -Action 'Install' -Path "$ChromeDownloadPath" -Parameters "$($InstallChromeArgs -join ' ')" -LogName "$($InstallName)_Msi"
        }
        catch {
            Write-Log -Message "There was an unexpected problem in Installation phase of script. Exiting with error code 69005. Error: $($_)" -Source 'Write-Log' -Severity 3
            Exit-Script -ExitCode 69005
        }

        ##*===============================================
        ##* POST-INSTALLATION
        ##*===============================================
        [String]$installPhase = 'Post-Installation'

        ## <Perform Post-Installation tasks here>
        try {

            # Create master_preferences file
            $InitialPrefContent = @"
{
    "browser": {
        "check_default_browser": false
    },
    "distribution": {
        "import_bookmarks": false,
        "import_history": false,
        "import_home_page": false,
        "import_search_engine": false,
        "suppress_first_run_bubble": true,
        "do_not_create_desktop_shortcut": true,
        "do_not_create_quick_launch_shortcut": true,
        "do_not_create_taskbar_shortcut": true,
        "do_not_launch_chrome": true,
        "do_not_register_for_update_launch": true,
        "make_chrome_default": false,
        "make_chrome_default_for_user": false,
        "msi": true,
        "require_eula": false,
        "suppress_first_run_default_browser_prompt": true,
        "system_level": true,
        "verbose_logging": true
    },
    "first_run_tabs": [
        "about:blank"
    ],
    "homepage": "about:blank",
    "homepage_is_newtabpage": false,
    "sync_promo": {
        "show_on_first_run_allowed": false
    }
}
"@

            $IntialPrefFilePath = "${env:ProgramFiles}\Google\Chrome\Application\initial_preferences"
            $InitialPrefContent | Out-File -FilePath $IntialPrefFilePath -Encoding 'ascii' -Force -Confirm:$false
        }
        catch {
            Write-Log -Message "There was a problem creating the initial_preferences file: '$IntialPrefFilePath'. Exiting with error code 69006. Error: $($_)" -Source 'Out-File' -Severity 3
            Exit-Script -ExitCode 69006
        }

        # Delete Desktop Shortcut
        try {
            [string]$ShortcutLinkFilePath = "$env:PUBLIC\Desktop\Google Chrome.lnk"
            Write-Log -Message "Checking if Chrome Desktop Shortcut is present:'$ShortcutLinkFilePath'" -Source 'Test-Path'
            if (Test-Path -Path "$ShortcutLinkFilePath" -PathType 'Leaf') {
                Write-Log -Message "Shortcut found at '$ShortcutLinkFilePath', deleting" -Source 'Remove-Item'
                Remove-Item -Path "$ShortcutLinkFilePath" -Force -Confirm:$false -ErrorAction 'Stop'
            }
            else {
                Write-Log -Message 'Chrome Desktop Shortcut is not present, continuing installation' -Source 'Test-Path'
            }
        }
        catch {
            Write-Log -Message "There was a problem deleting the shortcut'$ShortcutLinkFilePath'. Exiting with error code 69007. Error: $($_)" -Source 'Remove-Item' -Severity 3
            Exit-Script -ExitCode 69007
        }

    }
    ElseIf ($deploymentType -ieq 'Uninstall') {
        ##*===============================================
        ##* PRE-UNINSTALLATION
        ##*===============================================
        [String]$installPhase = 'Pre-Uninstallation'

        ## Show Welcome Message, close Chrome with a 300 second countdown before automatically closing
        Show-InstallationWelcome -CloseApps 'chrome' -CloseAppsCountdown 300 -MinimizeWindows $false

        ## Show Progress Message (with the default message)
        Show-InstallationProgress -WindowLocation 'BottomRight' -TopMost $false

        ## <Perform Pre-Uninstallation tasks here>


        ##*===============================================
        ##* UNINSTALLATION
        ##*===============================================
        [String]$installPhase = 'Uninstallation'

        ## <Perform Uninstallation tasks here>
        try {
            [string]$HKLM64 = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
            [string]$HKLM32 = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
            $ChromeInstalls = (Get-ChildItem -Path $HKLM64, $HKLM32 | Get-ItemProperty).Where({ $_.DisplayName -match 'Chrome' })

            foreach ($ChromeInstall in $ChromeInstalls) {
                $Guid = $ChromeInstall.PSChildName
                Write-Log -Message "Uninstalling the following GUID '$Guid' for Chrome" -Source 'Execute-MSI'
                Execute-MSI -Action 'Uninstall' -Path $Guid -LogName "$($appVendor)_$($appName)_$($Item.DisplayVersion)_$($appLang)_$($appRevision)_Msi"
                Clear-Variable -Name 'Guid' -ErrorAction 'Ignore'
            }
        }
        catch {
            Write-Log -Message "There was an unexpected problem in uninstallation phase of script. Exiting with error code 69008. Error: $($_)" -Source 'Write-Log' -Severity 3
            Exit-Script -ExitCode 69008
        }

        ##*===============================================
        ##* POST-UNINSTALLATION
        ##*===============================================
        [String]$installPhase = 'Post-Uninstallation'

        ## <Perform Post-Uninstallation tasks here>
        try {
            [string]$ChromeInstallationFolder = "$env:ProgramFiles\Google\Chrome"
            Write-Log -Message "Checking if Chrome installation folder '$ChromeInstallationFolder' is present" -Source 'Test-Path'
            if (Test-Path -Path $ChromeInstallationFolder -PathType 'Container') {
                Write-Log -Message "Folder found at '$ChromeInstallationFolder', deleting file and folders" -Source 'Remove-Item'
                Remove-Item -Path $ChromeInstallationFolder -Recurse -Force -Confirm:$false -ErrorAction 'Stop'
            }
        }
        catch {
            Write-Log -Message "There was an problem removing leftover Chrome files and folders from '$ChromeInstallationFolder'. Exiting with error code 69009. Error: $($_)" -Source 'Write-Log' -Severity 3
            Exit-Script -ExitCode 69009
        }

    }
    ElseIf ($deploymentType -ieq 'Repair') {
        ##*===============================================
        ##* PRE-REPAIR
        ##*===============================================
        [String]$installPhase = 'Pre-Repair'

        ## Show Welcome Message, close Chrome with a 300 second countdown before automatically closing
        Show-InstallationWelcome -CloseApps 'chrome' -CloseAppsCountdown 300 -MinimizeWindows $false

        ## Show Progress Message (with the default message)
        Show-InstallationProgress -WindowLocation 'BottomRight' -TopMost $false

        ## <Perform Pre-Repair tasks here>

        ##*===============================================
        ##* REPAIR
        ##*===============================================
        [String]$installPhase = 'Repair'

        ## <Perform Repair tasks here>

        ##*===============================================
        ##* POST-REPAIR
        ##*===============================================
        [String]$installPhase = 'Post-Repair'

        ## <Perform Post-Repair tasks here>


    }
    ##*===============================================
    ##* END SCRIPT BODY
    ##*===============================================

    ## Call the Exit-Script function to perform final cleanup operations
    Exit-Script -ExitCode $mainExitCode
}
Catch {
    [Int32]$mainExitCode = 60001
    [String]$mainErrorMessage = "$(Resolve-Error)"
    Write-Log -Message $mainErrorMessage -Severity 3 -Source $deployAppScriptFriendlyName
    Show-DialogBox -Text $mainErrorMessage -Icon 'Stop'
    Exit-Script -ExitCode $mainExitCode
}
