#  Edge

  - Vendor: Microsoft
  - URL: https://www.microsoft.com/en-us/edge/business/download
  - Update/RSS Feed: https://edgeupdates.microsoft.com/api/products

## Package Deployment Steps
1. Download latest version of [PowerShell App Deployment Toolkit](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/releases)
2. Download latest version of ServiceUI (64-bit) via [Microsoft Deployment Toolkit](https://aka.ms/mdtdownload)
   - When MDT is installed, you can find the 64-bit ServiceUI.exe in:
   > `C:\Program Files\Microsoft Deployment Toolkit\Templates\Distribution\Tools\x64`
3. Download latest version of [Microsoft Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool)
4. Extract toolkit to staging area
5. Copy ServiceUI to root folder of App.
6. Update Edge.txt file from this repository with applicable information
   and copy to toolkit root folder
7.  Update Deploy-Application.ps1 from this repository (ensure it matches the latest toolkit version) and copy to toolkit root folder
8.  Download [Configure.ps1](https://github.com/aentringer/intune-apps/raw/main/Intune/Configure.ps1) and copy to toolkit root folder
9.  Use Win32 Content Prep Tool to package toolkit folder into .intunewin file
10. Update Edge App in [Microsoft Endpoint Manager](https://endpoint.microsoft.com) with new .intunewin file and other related changes.
11. If the is a new App for Intune add the logo file so it will always be available in GitHub.

## App Deployment Details

### Program
- Install command: `"%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\Configure.ps1" -Mode Install`
- Uninstall command: `"%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\Configure.ps1" -Mode Uninstall`
- Install behavior: `System`
- Device restart behavior: `Determine behavior based on return codes`
- Return codes:
  > | Return Code    | Code Type    | Description                                      | Intune Error Codes    |
  > | :------------- | :----------- | :----------------------------------------------- | :-------------------- |
  > | 60001          | Failed       | AppDeployToolkit - General Failure               | 0x8007EA61            |
  > | 60008          | Failed       | AppDeployToolkit - Failed to DotSource Main file | 0x8007EA68            |
  > | 60012          | Failed       | AppDeployToolkit - User Deferred Process         | 0x8007EA6C            |
  > | 69000          | Failed       | AppDeployToolkit - Data Check Failure            | 0x80070D88            |
  > | 69001          | Failed       | AppDeployToolkit - Get-EdgeVersion Failure       | 0x80070D89            |
  > | 69002          | Failed       | AppDeployToolkit - Edge MSI Download Failure     | 0x80070D8A            |
  > | 69003          | Failed       | AppDeployToolkit - Edge MSI File Hash Mismatch   | 0x80070D8B            |
  > | 69900          | Failed       | Configure.ps1    - Data Check Failure            | 0x8007110C            |
  > | 69901          | Failed       | Configure.ps1    - Process Launch Error          | 0x8007110D            |

### Requirements
- Operating system architecture: `64-bit`
- Minimum operating system: `Windows 10 1903`

### Detection rules
- Rules format: `Use a custom dectection script`
  - Script file: `Select Detect-MSEdge.ps1 within this repository`
  - Run script as 32-bit process on 64-bit clients: `No`
  - Enforce script signature check and run script silently: `No`

### Log Names
- Logs should be written to the following folder: `$env:windir\Logs\Software`
  - Install Log: `Microsoft_Edge_[version]_EN_01_PSAppDeployToolkit_Install.log`
    - MSI Logs: `Microsoft_Edge_[version]_EN_01_Msi_Install.log`
  - Uninstall Log: `Microsoft_Edge_[version]_EN_01_PSAppDeployToolkit_Uninstall.log`
    - MSI Logs: `Microsoft_Edge_[version]_EN_01_Msi_Uninstall.log`
