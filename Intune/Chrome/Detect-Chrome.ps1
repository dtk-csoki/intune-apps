function Get-ChromeVersion {
    # Get latest Google Chrome versions from public JSON feed
    # Alex Entringer 2024-03-12
    [CmdletBinding()]
    param (

        [Parameter(Mandatory = $False)]
        [ValidateSet('win', 'win64', 'mac', 'linux', 'ios', 'cros', 'android', 'webview')]
        [string]$Platform = 'win64',

        [Parameter(Mandatory = $False)]
        [ValidateSet('stable', 'beta', 'dev', 'canary', 'canary_asan')]
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
    [int]$Success = 0
    $ChromeDetails = Get-ChromeVersion
    $CurrentDate = Get-Date
    $GracePeriodExpiration = (([datetime]$ChromeDetails.PublishedTime).AddDays(2.5)).AddHours(-7)
    [string]$ChromeInstallPath = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"

    if (Test-Path -Path $ChromeInstallPath -PathType 'Leaf') {
        $InstalledVersion = (Get-Item -Path $ChromeInstallPath -ErrorAction 'SilentlyContinue').VersionInfo.FileVersion
        if ([string]::IsNullOrEmpty($InstalledVersion)) {
            $InstalledVersion = '0.0.0.0'
        }

        if ([version]$InstalledVersion -ge [version]$($ChromeDetails.Version)) {
            $Success++
        }
        elseif ($CurrentDate -lt $GracePeriodExpiration) {
            # Grace period assumes the following policies are enabled on the device:
            # Notify a user that a browser restart is recommended or required for pending updates: Required
            # Set the time period for update notifications: 129600000 (1.5 days)
            Write-Host "Chrome detected: Version mismatch, but grace period still in effect. Installed version: '$($InstalledVersion)'. Expected Version: '$($ChromeDetails.Version)'. Grace Period Expiration: '$($GracePeriodExpiration.ToString('yyyy-MM-dd HH:mm:ss'))'"
            exit 0
        }
    }
    else {
        Write-Host "Chrome was not detected: Cannot locate '$ChromeInstallPath'"
        exit 1
    }

    if ( $Success -eq 1 ) {
        Write-Host "Chrome detected: '$($ChromeDetails.Version)' installed successfully"
        exit 0
    }
    else {
        Write-Host "Chrome was not detected: installed version: '$InstalledVersion', expected version: '$($ChromeDetails.Version)'"
        exit 1
    }
}
catch {
    Write-Host "Chrome not detected: Detection script ran into an unexpected error. Error: $($_)"
    exit 1
}
