<#
.SYNOPSIS
    This script performs the installation or uninstallation of an application(s).
    # LICENSE #
    PowerShell App Deployment Toolkit - Provides a set of functions to perform common application deployment tasks on Windows.
    Copyright (C) 2017 - Sean Lillis, Dan Cunningham, Muhammad Mashwani, Aman Motazedian.
    This program is free software: you can redistribute it and/or modify it under the terms of the GNU Lesser General Public License as published by the Free Software Foundation, either version 3 of the License, or any later version. This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
    You should have received a copy of the GNU Lesser General Public License along with this program. If not, see <http://www.gnu.org/licenses/>.
.DESCRIPTION
    The script is provided as a template to perform an install or uninstall of an application(s).
    The script either performs an "Install" deployment type or an "Uninstall" deployment type.
    The install deployment type is broken down into 3 main sections/phases: Pre-Install, Install, and Post-Install.
    The script dot-sources the AppDeployToolkitMain.ps1 script which contains the logic and functions required to install or uninstall an application.
.PARAMETER DeploymentType
    The type of deployment to perform. Default is: Install.
.PARAMETER DeployMode
    Specifies whether the installation should be run in Interactive, Silent, or NonInteractive mode. Default is: Interactive. Options: Interactive = Shows dialogs, Silent = No dialogs, NonInteractive = Very silent, i.e. no blocking apps. NonInteractive mode is automatically set if it is detected that the process is not user interactive.
.PARAMETER AllowRebootPassThru
    Allows the 3010 return code (requires restart) to be passed back to the parent process (e.g. SCCM) if detected from an installation. If 3010 is passed back to SCCM, a reboot prompt will be triggered.
.PARAMETER TerminalServerMode
    Changes to "user install mode" and back to "user execute mode" for installing/uninstalling applications for Remote Destkop Session Hosts/Citrix servers.
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
.NOTES
    Toolkit Exit Code Ranges:
    60000 - 68999: Reserved for built-in exit codes in Deploy-Application.ps1, Deploy-Application.exe, and AppDeployToolkitMain.ps1
    69000 - 69999: Recommended for user customized exit codes in Deploy-Application.ps1
    70000 - 79999: Recommended for user customized exit codes in AppDeployToolkitExtensions.ps1
.LINK
    http://psappdeploytoolkit.com
#>
[CmdletBinding()]
Param (
    [Parameter(Mandatory=$false)]
    [ValidateSet('Install','Uninstall','Repair')]
    [string]$DeploymentType = 'Install',
    [Parameter(Mandatory=$false)]
    [ValidateSet('Interactive','Silent','NonInteractive')]
    [string]$DeployMode = 'Interactive',
    [Parameter(Mandatory=$false)]
    [switch]$AllowRebootPassThru = $false,
    [Parameter(Mandatory=$false)]
    [switch]$TerminalServerMode = $false,
    [Parameter(Mandatory=$false)]
    [switch]$DisableLogging = $false
)

function Get-EdgeVersion {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $False)]
        # Alternative with more links: https://edgeupdates.microsoft.com/api/products?view=enterprise
        [string] $Uri = 'https://edgeupdates.microsoft.com/api/products',

        [Parameter(Mandatory = $False)]
        [ValidateSet('Windows', 'MacOS')]
        [string] $Platform = 'Windows',

        [Parameter(Mandatory = $False)]
        [ValidateSet('arm64', 'x86', 'x64')]
        [string] $Architecture = 'x64',

        [Parameter(Mandatory = $False)]
        [ValidateSet('Stable', 'Beta', 'Dev', 'Canary')]
        [string] $Channel = 'Stable'
    )
    try {
        $EdgeApi = Invoke-RestMethod -UseBasicParsing -Uri $Uri -Method 'Get' -ErrorAction 'Stop'
        $ChannelDetails = ($EdgeApi.SyncRoot).Where({$_.Product -eq "$Channel"})
        $LatestChannelValue = (($ChannelDetails.Releases).Where({($_.Platform -eq $Platform) -and ($_.Architecture -eq $Architecture)}) | Sort-Object 'ReleaseId' -Descending)[0]
        $DownloadUri = $LatestChannelValue.Artifacts.Location
        $DownloadHash = $LatestChannelValue.Artifacts.Hash
        $DownloadHashAlgorithm = $LatestChannelValue.Artifacts.HashAlgorithm
        $DownloadSize = $LatestChannelValue.Artifacts.SizeInBytes
        $DownloadVersion = $LatestChannelValue.ProductVersion

        $Output = [PSCustomObject]@{
            Channel = $Channel
            Platform = $Platform
            Architecture = $Architecture
            URI = $DownloadUri
            Hash = $DownloadHash
            HashAlgorithm = $DownloadHashAlgorithm
            SizeInBytes = $DownloadSize
            Version = $DownloadVersion
        }
    }
    catch {
        $Output = $null
    }
    return $Output
}

$VersionDetails = Get-EdgeVersion

foreach ($Item in $VersionDetails.psobject.properties.name) {
    if ([string]::IsNullOrEmpty($($VersionDetails.$Item))) {
        if (Test-Path -LiteralPath 'variable:HostInvocation') { $script:ExitCode = 69001; exit } else { exit 69001 }
    }
}

try {
    $Data = Get-Content -Path "$PSScriptRoot\*.txt" -Raw | ConvertFrom-Json -ErrorAction 'Stop'
}
catch {
    if (Test-Path -LiteralPath 'variable:HostInvocation') { $script:ExitCode = 69000; exit } else { exit 69000 }
}

$TxtFileValues = @(
    'Name'
    'Version'
    'Vendor'
    'Date'
    'ScriptVersion'
    'ScriptAuthor'
)

foreach ($Item in $TxtFileValues) {
    if ([string]::IsNullOrEmpty($($Data.$Item))) {
        if (Test-Path -LiteralPath 'variable:HostInvocation') { $script:ExitCode = 69000; exit } else { exit 69000 }
    }
}

Try {
    ## Set the script execution policy for this process
    Try { Set-ExecutionPolicy -ExecutionPolicy 'ByPass' -Scope 'Process' -Force -ErrorAction 'Stop' } Catch {}

    ##*===============================================
    ##* VARIABLE DECLARATION
    ##*===============================================
    ## Variables: Application
    [string]$appVendor = $($Data.Vendor)
    [string]$appName = $($Data.Name)
    [string]$appVersion = $VersionDetails.Version
    [string]$appArch = ''
    [string]$appLang = 'EN'
    [string]$appRevision = '01'
    [string]$appScriptVersion = $($Data.ScriptVersion)
    [string]$appScriptDate = $($Data.Date)
    [string]$appScriptAuthor = $($Data.ScriptAuthor)
    ##*===============================================
    ## Variables: Install Titles (Only set here to override defaults set by the toolkit)
    [string]$installName = ''
    [string]$installTitle = ''

    ##* Do not modify section below
    #region DoNotModify

    ## Variables: Exit Code
    [int32]$mainExitCode = 0

    ## Variables: Script
    [string]$deployAppScriptFriendlyName = 'Deploy Application'
    [version]$deployAppScriptVersion = [version]'3.8.4'
    [string]$deployAppScriptDate = '26/01/2021'
    [hashtable]$deployAppScriptParameters = $psBoundParameters

    ## Variables: Environment
    If (Test-Path -LiteralPath 'variable:HostInvocation') { $InvocationInfo = $HostInvocation } Else { $InvocationInfo = $MyInvocation }
    [string]$scriptDirectory = Split-Path -Path $InvocationInfo.MyCommand.Definition -Parent

    ## Dot source the required App Deploy Toolkit Functions
    Try {
        [string]$moduleAppDeployToolkitMain = "$scriptDirectory\AppDeployToolkit\AppDeployToolkitMain.ps1"
        If (-not (Test-Path -LiteralPath $moduleAppDeployToolkitMain -PathType 'Leaf')) { Throw "Module does not exist at the specified location [$moduleAppDeployToolkitMain]." }
        If ($DisableLogging) { . $moduleAppDeployToolkitMain -DisableLogging } Else { . $moduleAppDeployToolkitMain }
    }
    Catch {
        If ($mainExitCode -eq 0){ [int32]$mainExitCode = 60008 }
        Write-Error -Message "Module [$moduleAppDeployToolkitMain] failed to load: `n$($_.Exception.Message)`n `n$($_.InvocationInfo.PositionMessage)" -ErrorAction 'Continue'
        ## Exit the script, returning the exit code to SCCM
        If (Test-Path -LiteralPath 'variable:HostInvocation') { $script:ExitCode = $mainExitCode; Exit } Else { Exit $mainExitCode }
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
        [string]$installPhase = 'Pre-Installation'

        $EdgeFilename = 'MicrosoftEdgeEnterpriseX64.msi'
        $EdgeDownloadPath = "$dirFiles\$EdgeFilename"

        try {
            if (-not (Test-Path -Path $EdgeDownloadPath -PathType 'Leaf' -ErrorAction 'SilentlyContinue')) {
                try {
                    $CurrentPreference = $ProgressPreference
                    $ProgressPreference = 'SilentlyContinue'
                    Write-Log -Message "Downloading Edge $($VersionDetails.Version) from '$($VersionDetails.URI)'" -Source 'Invoke-WebRequest'
                    Invoke-WebRequest -Uri $VersionDetails.URI -UseBasicParsing -OutFile "$EdgeDownloadPath" -ErrorAction 'SilentlyContinue'
                }
                catch {
                    Write-Log -Message "Failed to download Edge from '$($VersionDetails.URI)'. Exiting with error code 69002." -Source 'Invoke-WebRequest'
                    Exit-Script -ExitCode 69002
                }
                finally {
                    $ProgressPreference = $CurrentPreference
                }
            }

            if (-not (Test-Path -Path $EdgeDownloadPath -PathType 'Leaf' -ErrorAction 'SilentlyContinue')) {
                Write-Log -Message "Edge MSI not found at '$($EdgeDownloadPath)' after download completed. Exiting with error code 69002." -Source 'Test-Path'
                Exit-Script -ExitCode 69002
            }
            else {
                $DownloadedFileHash = (Get-FileHash -Path $EdgeDownloadPath -Algorithm $VersionDetails.HashAlgorithm).Hash
                $ExpectedHash = $VersionDetails.Hash
                if ($DownloadedFileHash -ne $ExpectedHash) {
                    Write-Log -Message "Edge MSI hash {$($DownloadedFileHash)} does not match expected {$($ExpectedHash)}. Exiting with error code 69003." -Source 'Get-FileHash'
                    Exit-Script -ExitCode 69003
                }
            }
        }
        catch {
            Write-Log -Message "Failed to download Edge from '$($VersionDetails.URI)'. Exiting with error code 69002." -Source 'Invoke-WebRequest'
            Exit-Script -ExitCode 69002
        }

        ## Show Welcome Message
        Show-InstallationWelcome -CloseApps 'msedge,MicrosoftEdge,MicrosoftEdgeCP,MicrosoftEdgeUpdate' -CloseAppsCountdown 2700 -MinimizeWindows $false

        ## Show Progress Message (with the default message)
        Show-InstallationProgress -WindowLocation 'BottomRight' -TopMost $false

        ##*===============================================
        ##* INSTALLATION
        ##*===============================================
        [string]$installPhase = 'Installation'

        ## <Perform Installation tasks here>
        $HKLM64 = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
        $HKLM32 = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'

        # Remove Microsoft Edge Dev, if present
        $EdgeInstalls = (Get-ChildItem -Path $HKLM64, $HKLM32 | Get-ItemProperty).Where({$_.DisplayName -match '^Microsoft Edge Dev$'})

        foreach ($Item in $EdgeInstalls) {
            if ($Item.PSChildName -match '^Microsoft Edge Dev$') {
                $UninstallArgs = @(
                    '--uninstall'
                    '--system-level'
                    '--verbose-logging'
                    '--force-uninstall'
                )
                $UninstallExe = $(($Item.UninstallString -split '" ')[0] -replace '"','')
                if (Test-Path -Path $UninstallExe -PathType 'Leaf' -ErrorAction 'SilentlyContinue') {
                    Write-Log -Message "Uninstalling Microsoft Edge Dev $($Item.DisplayVersion) via Exe Uninstall" -Source 'Execute-Process'
                    # Exit Code 20 can occur if 'MicrosoftEdgeUpdate.exe /uninstall', which is triggered based on
                    # the UninstallArgs takes longer than 60 seconds to finish. It should finish given more time,
                    # however.
                    $ExeProcessInfo = Execute-Process -Path $UninstallExe -Parameters $($UninstallArgs -join ' ') -IgnoreExitCodes '20' -PassThru

                    if ($ExeProcessInfo.ExitCode -eq 20) {
                        Write-Log -Message "Microsoft Edge Dev $($Item.DisplayVersion) Exe uninstall exited with a possible timeout issue. Providing additional time for completion"
                        $UninstallStatus = $false
                        $UninstallTimer = 0
                        do {
                            $MicrosoftEdgeUpdateLog = "$env:ProgramData\Microsoft\EdgeUpdate\Log\MicrosoftEdgeUpdate.log"
                            if (Test-Path -Path $MicrosoftEdgeUpdateLog -PathType 'Leaf' -ErrorAction 'SilentlyContinue') {
                                $UninstallStatus = Get-Content -Path $MicrosoftEdgeUpdateLog -ErrorAction 'SilentlyContinue' | Select-String 'Update complete' -Quiet
                                Start-Sleep -Seconds 5
                                $UninstallTimer++
                            }
                        } until (($UninstallStatus) -or ($UninstallTimer -eq 60))
                        Clear-Variable -Name 'UninstallStatus','UninstallTimer' -ErrorAction 'SilentlyContinue'
                    }
                }
            }
            else {
                $Guid = $Item.PSChildName
                Write-Log -Message "Uninstalling Microsoft Edge Dev $($Item.DisplayVersion)" -Source 'Execute-MSI'
                Execute-MSI -Action 'Uninstall' -Path $Guid -LogName "$($appVendor)_EdgeDev_$($Item.DisplayVersion)_$($appLang)_$($appRevision)_Msi"
            }
        }

        if (Test-Path -Path "${env:ProgramFiles(x86)}\Microsoft\Edge Dev" -PathType 'Container') {
            Write-Log -Message "Removing folder: '${env:ProgramFiles(x86)}\Microsoft\Edge Dev'" -Source 'Remove-Item'
            Remove-Item -Path "${env:ProgramFiles(x86)}\Microsoft\Edge Dev" -Recurse -Force -Confirm:$false -ErrorAction 'SilentlyContinue'
        }
        if (Test-Path -Path "$env:ProgramFiles\Microsoft\Edge Dev" -PathType 'Container') {
            Write-Log -Message "Removing folder: '$env:ProgramFiles\Microsoft\Edge Dev'" -Source 'Remove-Item'
            Remove-Item -Path "$env:ProgramFiles\Microsoft\Edge Dev" -Recurse -Force -Confirm:$false -ErrorAction 'SilentlyContinue'
        }
        Clear-Variable -Name 'EdgeInstalls' -ErrorAction 'SilentlyContinue'

        # Remove Edge Exe Installer, if present
        $EdgeInstalls = (Get-ChildItem -Path $HKLM64, $HKLM32 | Get-ItemProperty).Where({$_.DisplayName -match '^Microsoft Edge$'})
        foreach ($Item in $EdgeInstalls) {
            if ($Item.PSChildName -match '^Microsoft Edge$') {
                $UninstallArgs = @(
                    '--uninstall'
                    '--system-level'
                    '--verbose-logging'
                    '--force-uninstall'
                )
                $UninstallExe = $(($Item.UninstallString -split '" ')[0] -replace '"','')
                if (Test-Path -Path $UninstallExe -PathType 'Leaf' -ErrorAction 'SilentlyContinue') {
                    Write-Log -Message "Uninstalling Microsoft Edge $($Item.DisplayVersion) via Exe Uninstall" -Source 'Execute-Process'
                    # Exit Code 20 can occur if 'MicrosoftEdgeUpdate.exe /uninstall', which is triggered based on
                    # the UninstallArgs takes longer than 60 seconds to finish. It should finish given more time,
                    # however.
                    $ExeProcessInfo = Execute-Process -Path $UninstallExe -Parameters $($UninstallArgs -join ' ') -IgnoreExitCodes '20' -PassThru

                    if ($ExeProcessInfo.ExitCode -eq 20) {
                        Write-Log -Message "Microsoft Edge $($Item.DisplayVersion) Exe uninstall exited with a possible timeout issue. Providing additional time for completion"
                        $UninstallStatus = $false
                        $UninstallTimer = 0
                        do {
                            $MicrosoftEdgeUpdateLog = "$env:ProgramData\Microsoft\EdgeUpdate\Log\MicrosoftEdgeUpdate.log"
                            if (Test-Path -Path $MicrosoftEdgeUpdateLog -PathType 'Leaf' -ErrorAction 'SilentlyContinue') {
                                $UninstallStatus = Get-Content -Path $MicrosoftEdgeUpdateLog -ErrorAction 'SilentlyContinue' | Select-String 'Update complete' -Quiet
                                Start-Sleep -Seconds 5
                                $UninstallTimer++
                            }
                        } until (($UninstallStatus) -or ($UninstallTimer -eq 60))
                        Clear-Variable -Name 'UninstallStatus','UninstallTimer' -ErrorAction 'SilentlyContinue'
                    }

                    if (Test-Path -Path "${env:ProgramFiles(x86)}\Microsoft\Edge" -PathType 'Container') {
                        Write-Log -Message "Removing folder: '${env:ProgramFiles(x86)}\Microsoft\Edge'" -Source 'Remove-Item'
                        Remove-Item -Path "${env:ProgramFiles(x86)}\Microsoft\Edge" -Recurse -Force -Confirm:$false -ErrorAction 'SilentlyContinue'
                    }
                    if (Test-Path -Path "$env:ProgramFiles\Microsoft\Edge" -PathType 'Container') {
                        Write-Log -Message "Removing folder: '$env:ProgramFiles\Microsoft\Edge'" -Source 'Remove-Item'
                        Remove-Item -Path "$env:ProgramFiles\Microsoft\Edge" -Recurse -Force -Confirm:$false -ErrorAction 'SilentlyContinue'
                    }
                }
            }
        }
        Clear-Variable -Name 'EdgeInstalls' -ErrorAction 'SilentlyContinue'

        # Install Microsoft Edge
        Write-Log -Message "Installing Microsoft Edge $($VersionDetails.Version) using '$EdgeDownloadPath'" -Source 'Execute-MSI'
        Execute-MSI -Action 'Install' -Path "$edgeDownloadPath" -Parameters "/qn REBOOT=ReallySuppress" -LogName "$($installName)_Msi"

        # If Edge installation made a 'new_msedge.exe' file, do additional checks
        # We want to make sure the main 'msedge.exe' was updated to the detected latest version before exiting the installer
        if (Test-Path -Path "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\new_msedge.exe" -PathType 'Leaf') {
            if (Test-Path -Path "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe" -PathType 'Leaf') {
                $InstalledVersion = (Get-Item -Path "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe" -ErrorAction 'SilentlyContinue').VersionInfo.FileVersion
                if ([string]::IsNullOrEmpty($InstalledVersion)) {
                    $InstalledVersion = '0.0.0.0'
                }
                if ([version]$InstalledVersion -lt [version]$VersionDetails.Version) {
                    $EdgeInstalls = (Get-ChildItem -Path $HKLM64, $HKLM32 | Get-ItemProperty).Where({$_.DisplayName -match '^Microsoft Edge$'})

                    foreach ($Item in $EdgeInstalls) {
                        if ($Item.PSChildName -match '^Microsoft Edge$') {
                            $UninstallArgs = @(
                                '--uninstall'
                                '--system-level'
                                '--verbose-logging'
                                '--force-uninstall'
                            )
                            $UninstallExe = $(($Item.UninstallString -split '" ')[0] -replace '"','')
                            if (Test-Path -Path $UninstallExe -PathType 'Leaf' -ErrorAction 'SilentlyContinue') {
                                Write-Log -Message "Uninstalling Microsoft Edge $($Item.DisplayVersion) via Exe Uninstall" -Source 'Execute-Process'
                                # Exit Code 20 can occur if 'MicrosoftEdgeUpdate.exe /uninstall', which is triggered based on
                                # the UninstallArgs takes longer than 60 seconds to finish. It should finish given more time,
                                # however.
                                $ExeProcessInfo = Execute-Process -Path $UninstallExe -Parameters $($UninstallArgs -join ' ') -IgnoreExitCodes '20' -PassThru

                                if ($ExeProcessInfo.ExitCode -eq 20) {
                                    Write-Log -Message "Microsoft Edge $($Item.DisplayVersion) Exe uninstall exited with a possible timeout issue. Providing additional time for completion"
                                    $UninstallStatus = $false
                                    $UninstallTimer = 0
                                    do {
                                        $MicrosoftEdgeUpdateLog = "$env:ProgramData\Microsoft\EdgeUpdate\Log\MicrosoftEdgeUpdate.log"
                                        if (Test-Path -Path $MicrosoftEdgeUpdateLog -PathType 'Leaf' -ErrorAction 'SilentlyContinue') {
                                            $UninstallStatus = Get-Content -Path $MicrosoftEdgeUpdateLog -ErrorAction 'SilentlyContinue' | Select-String 'Update complete' -Quiet
                                            Start-Sleep -Seconds 5
                                            $UninstallTimer++
                                        }
                                    } until (($UninstallStatus) -or ($UninstallTimer -eq 60))
                                    Clear-Variable -Name 'UninstallStatus','UninstallTimer' -ErrorAction 'SilentlyContinue'
                                }
                            }
                        }
                        else {
                            $Guid = $Item.PSChildName
                            Write-Log -Message "Uninstalling Microsoft Edge $($Item.DisplayVersion)" -Source 'Execute-MSI'
                            Execute-MSI -Action 'Uninstall' -Path $Guid -LogName "$($appVendor)_$($appName)_$($Item.DisplayVersion)_$($appLang)_$($appRevision)_Msi"
                        }
                    }

                    if (Test-Path -Path "${env:ProgramFiles(x86)}\Microsoft\Edge" -PathType 'Container') {
                        Write-Log -Message "Removing folder: '${env:ProgramFiles(x86)}\Microsoft\Edge'" -Source 'Remove-Item'
                        Remove-Item -Path "${env:ProgramFiles(x86)}\Microsoft\Edge" -Recurse -Force -Confirm:$false -ErrorAction 'SilentlyContinue'
                    }
                    if (Test-Path -Path "$env:ProgramFiles\Microsoft\Edge" -PathType 'Container') {
                        Write-Log -Message "Removing folder: '$env:ProgramFiles\Microsoft\Edge'" -Source 'Remove-Item'
                        Remove-Item -Path "$env:ProgramFiles\Microsoft\Edge" -Recurse -Force -Confirm:$false -ErrorAction 'SilentlyContinue'
                    }

                    # Reinstall Edge again to try to get to a good clean state
                    Write-Log -Message "Installing Microsoft Edge $($VersionDetails.Version) using '$edgeDownloadPath' after removing old copy" -Source 'Execute-MSI'
                    Execute-MSI -Action 'Install' -Path "$edgeDownloadPath" -Parameters "/qn REBOOT=ReallySuppress" -LogName "$($installName)_Msi"
                }
            }
        }

        ##*===============================================
        ##* POST-INSTALLATION
        ##*===============================================
        [string]$installPhase = 'Post-Installation'

        ## <Perform Post-Installation tasks here>
        $MasterPreferences = @"
{
    "distribution" : {
        "do_not_create_desktop_shortcut" : true,
        "do_not_create_quick_launch_shortcut" : true,
        "do_not_create_taskbar_shortcut" : true,
        "msi" : true,
        "system_level" : true,
        "verbose_logging" : true,
        "allow_downgrade" : false
    }
}
"@

        if (Test-Path -Path "${env:ProgramFiles(x86)}\Microsoft\Edge\Application" -PathType 'Container') {
            Write-Log -Message "Creating master_preferences file at '${env:ProgramFiles(x86)}\Microsoft\Edge\Application\master_preferences'" -Source 'Set-Content'
            Set-Content -Path "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\master_preferences" -Value $MasterPreferences -Force -Confirm:$false -ErrorAction 'SilentlyContinue'
        }

        if (Test-Path -Path "$env:PUBLIC\Desktop\Microsoft Edge.lnk" -PathType 'Leaf') {
            Write-Log -Message "Removing Desktop Shortcut at '$env:PUBLIC\Desktop\Microsoft Edge.lnk'" -Source 'Set-Content'
            Remove-Item -Path "$env:PUBLIC\Desktop\Microsoft Edge.lnk" -Force -Confirm:$false -ErrorAction 'SilentlyContinue'
        }

        if (Test-Path -Path "$edgeDownloadPath" -PathType 'Leaf') {
            Write-Log -Message "Removing Edge Msi at '$edgeDownloadPath'" -Source 'Set-Content'
            Remove-Item -Path "$edgeDownloadPath" -Force -Confirm:$false -ErrorAction 'SilentlyContinue'
        }
    }
    ElseIf ($deploymentType -ieq 'Uninstall')
    {
        ##*===============================================
        ##* PRE-UNINSTALLATION
        ##*===============================================
        [string]$installPhase = 'Pre-Uninstallation'

        ## Show Welcome Message
        Show-InstallationWelcome -CloseApps 'msedge,MicrosoftEdge,MicrosoftEdgeCP,MicrosoftEdgeUpdate' -CloseAppsCountdown 300 -MinimizeWindows $false

        ## Show Progress Message (with the default message)
        Show-InstallationProgress -WindowLocation 'BottomRight' -TopMost $false

        ## <Perform Pre-Uninstallation tasks here>
        $HKLM64 = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
        $HKLM32 = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
        $EdgeInstalls = (Get-ChildItem -Path $HKLM64, $HKLM32 | Get-ItemProperty).Where({$_.DisplayName -match '^Microsoft Edge$'})

        ##*===============================================
        ##* UNINSTALLATION
        ##*===============================================
        [string]$installPhase = 'Uninstallation'

        # <Perform Uninstallation tasks here>
        foreach ($Item in $EdgeInstalls) {
            if ($Item.PSChildName -match '^Microsoft Edge$') {
                $UninstallArgs = @(
                    '--uninstall'
                    '--system-level'
                    '--verbose-logging'
                    '--force-uninstall'
                )
                $UninstallExe = $(($Item.UninstallString -split '" ')[0] -replace '"','')
                if (Test-Path -Path $UninstallExe -PathType 'Leaf' -ErrorAction 'SilentlyContinue') {
                    Write-Log -Message "Uninstalling Microsoft Edge $($Item.DisplayVersion) via Exe Uninstall" -Source 'Execute-Process'
                    # Exit Code 20 can occur if 'MicrosoftEdgeUpdate.exe /uninstall', which is triggered based on
                    # the UninstallArgs takes longer than 60 seconds to finish. It should finish given more time,
                    # however.
                    $ExeProcessInfo = Execute-Process -Path $UninstallExe -Parameters $($UninstallArgs -join ' ') -IgnoreExitCodes '20' -PassThru

                    if ($ExeProcessInfo.ExitCode -eq 20) {
                        Write-Log -Message "Microsoft Edge $($Item.DisplayVersion) Exe uninstall exited with a possible timeout issue. Providing additional time for completion"
                        $UninstallStatus = $false
                        $UninstallTimer = 0
                        do {
                            $MicrosoftEdgeUpdateLog = "$env:ProgramData\Microsoft\EdgeUpdate\Log\MicrosoftEdgeUpdate.log"
                            if (Test-Path -Path $MicrosoftEdgeUpdateLog -PathType 'Leaf' -ErrorAction 'SilentlyContinue') {
                                $UninstallStatus = Get-Content -Path $MicrosoftEdgeUpdateLog -ErrorAction 'SilentlyContinue' | Select-String 'Update complete' -Quiet
                                Start-Sleep -Seconds 5
                                $UninstallTimer++
                            }
                        } until (($UninstallStatus) -or ($UninstallTimer -eq 60))
                        Clear-Variable -Name 'UninstallStatus','UninstallTimer' -ErrorAction 'SilentlyContinue'
                    }
                }
            }
            else {
                $Guid = $Item.PSChildName
                Write-Log -Message "Uninstalling Microsoft Edge $($Item.DisplayVersion)" -Source 'Execute-MSI'
                Execute-MSI -Action 'Uninstall' -Path $Guid -LogName "$($appVendor)_$($appName)_$($Item.DisplayVersion)_$($appLang)_$($appRevision)_Msi"
            }
        }

        ##*===============================================
        ##* POST-UNINSTALLATION
        ##*===============================================
        [string]$installPhase = 'Post-Uninstallation'

        ## <Perform Post-Uninstallation tasks here>
        if (Test-Path -Path "${env:ProgramFiles(x86)}\Microsoft\Edge" -PathType 'Container') {
            Write-Log -Message "Removing folder: '${env:ProgramFiles(x86)}\Microsoft\Edge'" -Source 'Remove-Item'
            Remove-Item -Path "${env:ProgramFiles(x86)}\Microsoft\Edge" -Recurse -Force -Confirm:$false -ErrorAction 'SilentlyContinue'
        }
        if (Test-Path -Path "$env:ProgramFiles\Microsoft\Edge" -PathType 'Container') {
            Write-Log -Message "Removing folder: '$env:ProgramFiles\Microsoft\Edge'" -Source 'Remove-Item'
            Remove-Item -Path "$env:ProgramFiles\Microsoft\Edge" -Recurse -Force -Confirm:$false -ErrorAction 'SilentlyContinue'
        }
    }
    ElseIf ($deploymentType -ieq 'Repair')
    {
        ##*===============================================
        ##* PRE-REPAIR
        ##*===============================================
        [string]$installPhase = 'Pre-Repair'

        ## Show Progress Message (with the default message)
        Show-InstallationProgress

        ## <Perform Pre-Repair tasks here>

        ##*===============================================
        ##* REPAIR
        ##*===============================================
        [string]$installPhase = 'Repair'

        # <Perform Repair tasks here>

        ##*===============================================
        ##* POST-REPAIR
        ##*===============================================
        [string]$installPhase = 'Post-Repair'

        ## <Perform Post-Repair tasks here>

    }
    ##*===============================================
    ##* END SCRIPT BODY
    ##*===============================================

    ## Call the Exit-Script function to perform final cleanup operations
    Exit-Script -ExitCode $mainExitCode
}
Catch {
    [int32]$mainExitCode = 60001
    [string]$mainErrorMessage = "$(Resolve-Error)"
    Write-Log -Message $mainErrorMessage -Severity 3 -Source $deployAppScriptFriendlyName
    Show-DialogBox -Text $mainErrorMessage -Icon 'Stop'
    Exit-Script -ExitCode $mainExitCode
}
