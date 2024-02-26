<#
This script is intended to be used as a requirement script in software deployed via Intune. By applying it as a
requirement, you make it so that the software will not install during ESP, even if it is set as a required
application.

Note that the script error catching is not robust, as the requirement scripts do not give much room for
customization. As a result, if an error is triggered, it will be assumed that ESP is not running. That behavior
can be flipped by editing the catch block at the bottom of the script.

See the section below on how to use it in the Intune GUI to configure as a requirement.

### Configure additional requirement rules
- Click + Add
  - Script name: _(Allow to be auto filled by choose script below)_
  - Script File: `Get-ESPStatusRequirement.ps1`
  - Run script as 32-bit process on 64-bit clients: `No`
  - Run this script using the logged on credentials: `No`
  - Enforce script signature check: `No`
  - Select output data type: `String`
  - Operator: `Equals`
  - Value: `ESP is not running`
#>

try {
    [bool]$DevicePrepNotRunning = $false
    [bool]$DeviceSetupNotRunning = $false
    [bool]$AccountSetupNotRunning = $false

    [string]$AutoPilotSettingsKey = 'HKLM:\SOFTWARE\Microsoft\Provisioning\AutopilotSettings'
    [string]$DevicePrepName = 'DevicePreparationCategory.Status'
    [string]$DeviceSetupName = 'DeviceSetupCategory.Status'
    [string]$AccountSetupName = 'AccountSetupCategory.Status'

    [string]$AutoPilotDiagnosticsKey = 'HKLM:\SOFTWARE\Microsoft\Provisioning\Diagnostics\AutoPilot'
    [string]$TenantIdName = 'CloudAssignedTenantId'

    [string]$JoinInfoKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\JoinInfo'

    [string]$CloudAssignedTenantID = (Get-ItemProperty -Path $AutoPilotDiagnosticsKey -Name $TenantIdName -ErrorAction 'Ignore').$TenantIdName

    if (-not [string]::IsNullOrEmpty($CloudAssignedTenantID)) {
        foreach ($Guid in (Get-ChildItem -Path $JoinInfoKey -ErrorAction 'Ignore')) {
            [string]$AzureADTenantId = (Get-ItemProperty -Path "$JoinInfoKey\$($Guid.PSChildName)" -Name 'TenantId' -ErrorAction 'Ignore').'TenantId'
        }

        if ($CloudAssignedTenantID -eq $AzureADTenantId) {
            $DevicePrepDetails = (Get-ItemProperty -Path $AutoPilotSettingsKey -Name $DevicePrepName -ErrorAction 'Ignore').$DevicePrepName
            $DeviceSetupDetails = (Get-ItemProperty -Path $AutoPilotSettingsKey -Name $DeviceSetupName -ErrorAction 'Ignore').$DeviceSetupName
            $AccountSetupDetails = (Get-ItemProperty -Path $AutoPilotSettingsKey -Name $AccountSetupName -ErrorAction 'Ignore').$AccountSetupName

            if (-not [string]::IsNullOrEmpty($DevicePrepDetails)) {
                $DevicePrepDetails = $DevicePrepDetails | ConvertFrom-Json
            }
            else {
                $DevicePrepNotRunning = $true
            }
            if (-not [string]::IsNullOrEmpty($DeviceSetupDetails)) {
                $DeviceSetupDetails = $DeviceSetupDetails | ConvertFrom-Json
            }
            else {
                $DeviceSetupNotRunning = $true
            }
            if (-not [string]::IsNullOrEmpty($AccountSetupDetails)) {
                $AccountSetupDetails = $AccountSetupDetails | ConvertFrom-Json
            }
            else {
                $AccountSetupNotRunning = $true
            }

            if ((($DevicePrepDetails.categoryStatusMessage -in ('Complete','Failed')) -or ($DevicePrepDetails.categoryStatusText -in ('Complete','Failed'))) -or ($DevicePrepDetails.categoryState -notin ('notStarted','inProgress',$null))) {
                $DevicePrepNotRunning = $true
            }
            if ((($DeviceSetupDetails.categoryStatusMessage -in ('Complete','Failed')) -or ($DeviceSetupDetails.categoryStatusText -in ('Complete','Failed'))) -or ($DeviceSetupDetails.categoryState -notin ('notStarted','inProgress',$null))) {
                $DeviceSetupNotRunning = $true
            }
            if ((($AccountSetupDetails.categoryStatusMessage -in ('Complete','Failed')) -or ($AccountSetupDetails.categoryStatusText -in ('Complete','Failed'))) -or ($AccountSetupDetails.categoryState -notin ('notStarted','inProgress',$null))) {
                $AccountSetupNotRunning = $true
            }
            else {
                try {
                    $CurrentTime = Get-Date
                    [string]$AutoPilotStartTimeKey = 'HKLM:\SOFTWARE\Microsoft\Windows\Autopilot\EnrollmentStatusTracking\ESPTrackingInfo\Diagnostics\ExpectedPolicies'
                    $AutoPilotStartTimeValue = (Get-Childitem -Path $AutoPilotStartTimeKey -Recurse -ErrorAction 'Ignore')
                    if ([string]::IsNullOrEmpty($AutoPilotStartTimeValue)) {
                        Write-Host "ESP is running: Null or Empty value received from registry location '$AutoPilotStartTimeKey '."
                        exit 1
                    }
                    elseif ($($AutoPilotStartTimeValue.Count) -gt 1) {
                        Write-Host "ESP is running: Multiple Date/Time values were returned. Count: '$($AutoPilotStartTimeValue.Count)'"
                        exit 1
                    }
                    else {
                        $AutoPilotStartTime = $AutoPilotStartTimeValue.PSChildName
                    }

                    $FormattedTime = [datetime]::Parse($AutoPilotStartTime)
                    if ( $CurrentTime -ge $($FormattedTime.AddHours(1)) ) {
                        $AccountSetupNotRunning = $true
                    }
                }
                catch  {
                    Write-Host "ESP is running: Time that AutoPilot started '$AutoPilotStartTime', Time that this script ran '$CurrentTime'"
                    exit 1
                }
            }

            if ($DevicePrepNotRunning -and $DeviceSetupNotRunning -and $AccountSetupNotRunning) {
                Write-Host 'ESP is not running'
                exit 0
            }
            else {
                Write-Host 'ESP is running'
                exit 1
            }
        }
        else {
            Write-Host 'ESP is not running'
            exit 0
        }
    }
    else {
        Write-Host 'ESP is not running'
        exit 0
    }
}
catch {
    Write-Host 'ESP is not running'
    exit 0
}
