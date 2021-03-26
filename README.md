# intune-apps
Scripts used to automate software installations and updates using Intune Mobile
Device Management.

Many scripts leverage the [PowerShell App Deploy Toolkit](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit).
Many thanks to the developers for making such a useful toolkit available to the public.

All folders underneath the 'Intune' folder should be named using the respective
application's name and should have a README.md file explaining the full process
of downloading, scripting, and packaging the application for distribution via
Intune.

No folders should have spaces in their names. Use '-' (dash) in lieu of spaces.

> ***NOTE***: This repository should **never** contain installation binaries
> (like .exe files) that may be obtained from another location (such as the
> internet). This repository should only contain scripts and documentation
> developed internally that assist with an application's installation process.

## Intune Error Codes
The exit/error/return codes we use often get mangled by Intune when reported up
to the console. To assist with the conversion back and forth, try using the
code snippets below:

**Create Intune Hexadecimal 32-bit unsigned integer error code from integer error code**
```powershell
$ErrorCode = 69000
$ShortCode = ([System.Convert]::ToString($ErrorCode,16)).ToUpper()
if ($ShortCode.Length -ne 4) {
    $ShortCode = $ShortCode.Substring($ShortCode.Length - 4)
}
"$ErrorCode | 0x8007$($ShortCode)"
```

**Create Intune Hexadecimal 32-bit unsigned integer error code from integer error code array**
```powershell
# Simply update array with your app's return codes to get all of the Intune codes back
$ErrorCodes = @(
    69000
    69001
    69002
    69003
    69010
)
foreach ($ErrorCode in $ErrorCodes) {
	$ShortCode = ([System.Convert]::ToString($ErrorCode,16)).ToUpper()
	if ($ShortCode.Length -ne 4) {
		$ShortCode = $ShortCode.Substring($ShortCode.Length - 4)
	}
    "$ErrorCode | 0x8007$($ShortCode)"
}
```

**Convert integer error code to Decimal 16-bit unsigned integer**
```powershell
$ErrorCode = 69000
[uint32]$("0x$([System.Convert]::ToString($ErrorCode,16).Substring(1))")
```
