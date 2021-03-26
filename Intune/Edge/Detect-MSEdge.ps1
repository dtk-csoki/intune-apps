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

if (-not [string]::IsNullOrEmpty($VersionDetails.Version)) {
    if (Test-Path -Path "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe" -PathType 'Leaf' -ErrorAction 'SilentlyContinue') {
        if (Test-Path -Path "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\master_preferences" -PathType 'Leaf' -ErrorAction 'SilentlyContinue') {
            $InstalledVersion = (Get-Item -Path "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe" -ErrorAction 'SilentlyContinue').VersionInfo.FileVersion
            if ([string]::IsNullOrEmpty($InstalledVersion)) {
                $InstalledVersion = '0.0.0.0'
            }
            if ([version]$InstalledVersion -ge [version]$VersionDetails.Version) {
                Write-Host "Microsoft Edge Installed with version $InstalledVersion"
            }
        }
    }
}
