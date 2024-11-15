# https://www.reddit.com/r/Intune/comments/q8v92z/make_a_powershell_script_determine_if_it_is/

$scriptName = "RequirementRule-ESPCompleted"
# Dynamically sets the log directory to the system drive typically C:ProgramData\!SUPPORT\_LogFiles
$csLogPath = Join-Path -Path $Env:PROGRAMDATA -ChildPath "!SUPPORT\_LogFiles"

# The log file named as the running script, & created in the Log directory
$csLogFile = Join-Path -Path $csLogPath -ChildPath "$scriptName.log"

#Start-Transcript -Path $csLogFile -Append -Force

[bool]$DevicePrepComplete = $false
[bool]$DeviceSetupComplete = $false
[bool]$AccountSetupComplete = $false
[bool]$Userless = $false

[string]$AutoPilotSettingsKey = 'HKLM:\SOFTWARE\Microsoft\Provisioning\AutopilotSettings'
[string]$DevicePrepName = 'DevicePreparationCategory.Status'
[string]$DeviceSetupName = 'DeviceSetupCategory.Status'
[string]$AccountSetupName = 'AccountSetupCategory.Status'

[string]$AutoPilotDiagnosticsKey = 'HKLM:\SOFTWARE\Microsoft\Provisioning\Diagnostics\AutoPilot'
[string]$TenantIdName = 'CloudAssignedTenantId'

[string]$JoinInfoKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\JoinInfo'

[string]$CloudAssignedTenantID = (Get-ItemProperty -Path $AutoPilotDiagnosticsKey -Name $TenantIdName -ErrorAction 'Ignore').$TenantIdName

# Look for fooUser upn for a userless device deployment with the user account setup skipped, this finds the unique device guid for enrollment
[string]$EnrollRegKey = (@(Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Enrollments" -recurse | Where-Object {$_.PSChildName -like 'DeviceEnroller'}))
[string]$RegPath = $EnrollRegKey.TrimStart("HKEY_LOCAL_MACHINE")
[string]$EnrollmentPath = $RegPath -replace '\\DeviceEnroller$',''
$EnrollmentUser = Get-ItemProperty -Path "HKLM:\$EnrollmentPath" -Name 'UPN'

if ($EnrollmentUser.upn -like "fooUser*") {
        $Userless = $true
    }

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
        if (-not [string]::IsNullOrEmpty($DeviceSetupDetails)) {
            $DeviceSetupDetails = $DeviceSetupDetails | ConvertFrom-Json
        }
        if (-not [string]::IsNullOrEmpty($AccountSetupDetails)) {
            $AccountSetupDetails = $AccountSetupDetails | ConvertFrom-Json
        }

        if (($DevicePrepDetails.categorySucceeded -eq 'True') -or ($DevicePrepDetails.categoryState -eq 'succeeded')) {
            $DevicePrepComplete = $true
        }
        if (($DeviceSetupDetails.categorySucceeded -eq 'True') -or ($DeviceSetupDetails.categoryState -eq 'succeeded')) {
            $DeviceSetupComplete = $true
        }

        if (($AccountSetupDetails.categorySucceeded -eq 'True') -or ($AccountSetupDetails.categoryState -eq 'succeeded')) {
            $AccountSetupComplete = $true
        }

        if ($Userless -and ($AccountSetupDetails.categoryState -eq 'notStarted')) {
            $AccountSetupComplete = $true
        }

        if ($DevicePrepComplete -and $DeviceSetupComplete -and $AccountSetupComplete) {
            Write-Host "ESP is complete"
            #Write-Host "DevicePrepComplete is $DevicePrepComplete"
            #Write-Host "DeviceSetupComplete is $DeviceSetupComplete"
            #Write-Host "AccountSetupComplete is $AccountSetupComplete"
            #Write-Host "Userless is $Userless"
            #Stop-Transcript
            #exit 0
        }
        else {
            Write-Host "ESP is running"
            #Write-Host "DevicePrepComplete is $DevicePrepComplete"
            #Write-Host "DeviceSetupComplete is $DeviceSetupComplete"
            #Write-Host "AccountSetupComplete is $AccountSetupComplete"
            #Write-Host "Userless is $Userless"
            #Stop-Transcript
            #exit 1
        }
    }
    else {
        Write-Host "ESP is complete"
        #Stop-Transcript
        #exit 0
    }
}
else {
    Write-Host "ESP is complete"
    #Stop-Transcript
    #exit 0
}