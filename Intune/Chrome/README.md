# Chrome

  - Vendor: Google, Inc.
  - URL: https://www.google.com/chrome/
  - Update/RSS Feed: https://chromereleases.googleblog.com/

## Package Deployment Steps
1. Download latest version of [PowerShell App Deployment Toolkit](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/releases)
2. Download latest version of ServiceUI (64-bit)
   - When [MDT](https://aka.ms/mdtdownload) is installed, you can find the 64-bit ServiceUI.exe in:
   > `C:\Program Files\Microsoft Deployment Toolkit\Templates\Distribution\Tools\x64`
3. Download latest version of [Microsoft Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool)
4. Extract toolkit to staging area
5. Copy ServiceUI to root folder of App.
6. Update Chrome-AppSettings.json file from this repository with applicable information and copy to toolkit root folder
7.  Update Deploy-Application.ps1 from this repository (ensure it matches the latest toolkit version) and copy to toolkit root folder
8.  Edit `AppDeployToolkitConfig.xml` in .\AppDeployToolkit folder to change the following lines:
    ```xml
    <Toolkit_LogPath>$envWinDir\Logs\Software</Toolkit_LogPath>
    <InstallationUI_Timeout>6900</InstallationUI_Timeout>
    <MSI_LogPath>$envWinDir\Logs\Software</MSI_LogPath>
    ```
    to
    ```xml
    <Toolkit_LogPath>$envProgramData\Logs\Software</Toolkit_LogPath>
    <InstallationUI_Timeout>3300</InstallationUI_Timeout>
    <MSI_LogPath>$envProgramData\Logs\Software</MSI_LogPath>
    ```
9.  Download [Configure.ps1](https://raw.githubusercontent.com/aentringer/intune-apps/main/Intune/Configure.ps1) and copy to toolkit root folder
10. Use Win32 Content Prep Tool to package toolkit folder into .intunewin file
11. Update Chrome App in [Microsoft Endpoint Manager](https://endpoint.microsoft.com) with new .intunewin file and other related changes.

## App Deployment Details

### Program
- Install command: `"%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NoLogo -ExecutionPolicy Bypass -File ".\Configure.ps1" -Mode Install`
- Uninstall command: `"%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NoLogo -ExecutionPolicy Bypass -File ".\Configure.ps1" -Mode Uninstall`
- Install behavior: `System`
- Device restart behavior: `Determine behavior based on return codes`
- Return codes:
  *Due to Intune limit of 25 error codes, some Toolkit codes have been removed to make room for custom codes*
  > | Return Code    | Code Type    | Description                                                                            | Intune Error Codes|
  > | :------------- | :----------- | :--------------------------------------------------------------------------------------|:------------------|
  > | 60001          | Failed       | Toolkit: General Failure                                                               | 0x8007EA61        |
  > | 60002          | Failed       | Toolkit: Execute-Process failed with no specific error                                 | 0x8007EA62        |
  > | 60003          | Failed       | Toolkit: Execute-ProcessAsUser failed to run with HighestAvailable privileges          | 0x8007EA63        |
  > | 60004          | Failed       | Toolkit: Failed to load GUI assemblies while running in Interactive mode               | 0x8007EA64        |
  > | 60005          | Failed       | Toolkit: Failed to display installation prompt in blocking mode                        | 0x8007EA65        |
  > | 60007          | Failed       | Toolkit: Execute-ProcessAsUser failed to export scheduled task XML                     | 0x8007EA67        |
  > | 60008          | Failed       | Toolkit: Failed to DotSource Main file                                                 | 0x8007EA68        |
  > | 60009          | Failed       | Toolkit: Execute-ProcessAsUser failed to detect active user                            | 0x8007EA69        |
  > | 60012          | Failed       | Toolkit: User Deferred Process                                                         | 0x8007EA6C        |
  > | 60013          | Failed       | Toolkit: Execute-Process process failed with exit code out of int32 range              | 0x8007EA6D        |
  > | 69000          | Failed       | AppDeployToolkit - Malformed Json File                                                 | 0x80070D88        |
  > | 69001          | Failed       | AppDeployToolkit - Json variables are null or empty                                    | 0x80070D89        |
  > | 69002          | Failed       | AppDeployToolkit - Problem getting version information from Get-ChromeVersion function | 0x80070D8A        |
  > | 69003          | Failed       | AppDeployToolkit - Problem downloading Chrome installer                                | 0x80070D8B        |
  > | 69004          | Failed       | AppDeployToolkit - Problem deleting initial_preferences file                           | 0x80070D8C        |
  > | 69005          | Failed       | AppDeployToolkit - An Unexpected problem occurred in installation phase of script      | 0x80070D8D        |
  > | 69006          | Failed       | AppDeployToolkit - Problem creating initial_preferences file                           | 0x80070D8E        |
  > | 69007          | Failed       | AppDeployToolkit - Problem deleting desktop shortcut                                   | 0x80070D8F        |
  > | 69008          | Failed       | AppDeployToolkit - An Unexpected problem occurred in uninstallation phase of script    | 0x80070D90        |
  > | 69009          | Failed       | AppDeployToolkit - Problem deleting leftover Chrome Files and Folders                  | 0x80070D91        |
  > | 69900          | Failed       | Configure.ps1 - Data Check Failure                                                     | 0x8007110C        |
  > | 69901          | Failed       | Configure.ps1 - Process Launch Error                                                   | 0x8007110D        |
  > | 69902          | Failed       | Configure.ps1 - Error Running Start-CustomProcess                                      | 0x8007110E        |

### Requirements
- Operating system architecture: `64-bit`
- Minimum operating system: `Windows 11 22H2`

### Detection rules
- Rules format: `Use a custom dectection script`
  - Script file: `Select Detect-Chrome.ps1 within this repository`

### Log Names
- Logs should be written to the following folder: `C:\ProgramData\Logs\Software`
  - Install Logs: `Google_Chrome_[Version]_EN_01_PSAppDeployToolkit_Install`
  - Uninstall Logs: `Google_Chrome_[Version]_EN_01_PSAppDeployToolkit_Uninstall`
