param (
    [Parameter(Mandatory=$true)]
    [ValidateSet('Install','Repair','Uninstall')]
    [string]$Mode
)

Function Write-Log {
    <#
    .SYNOPSIS
        Write messages to a log file in CMTrace.exe compatible format or Legacy text file format.
    .DESCRIPTION
        Write messages to a log file in CMTrace.exe compatible format or Legacy text file format and optionally display in the console.
    .PARAMETER Message
        The message to write to the log file or output to the console.
    .PARAMETER Severity
        Defines message type. When writing to console or CMTrace.exe log format, it allows highlighting of message type.
        Options: 1 = Information (default), 2 = Warning (highlighted in yellow), 3 = Error (highlighted in red)
    .PARAMETER Source
        The source of the message being logged.
    .PARAMETER ScriptSection
        The heading for the portion of the script that is being executed. Default is: $script:installPhase.
    .PARAMETER LogType
        Choose whether to write a CMTrace.exe compatible log file or a Legacy text log file.
    .PARAMETER LogFileDirectory
        Set the directory where the log file will be saved.
    .PARAMETER LogFileName
        Set the name of the log file.
    .PARAMETER MaxLogFileSizeMB
        Maximum file size limit for log file in megabytes (MB). Default is 10 MB.
    .PARAMETER WriteHost
        Write the log message to the console.
    .PARAMETER ContinueOnError
        Suppress writing log message to console on failure to write message to log file. Default is: $true.
    .PARAMETER PassThru
        Return the message that was passed to the function
    .PARAMETER DebugMessage
        Specifies that the message is a debug message. Debug messages only get logged if -LogDebugMessage is set to $true.
    .PARAMETER LogDebugMessage
        Debug messages only get logged if this parameter is set to $true in the config XML file.
    .EXAMPLE
        Write-Log -Message "Installing patch MS15-031" -Source 'Add-Patch' -LogType 'CMTrace'
    .EXAMPLE
        Write-Log -Message "Script is running on Windows 8" -Source 'Test-ValidOS' -LogType 'Legacy'
    .NOTES
    .LINK
        http://psappdeploytoolkit.com
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [AllowEmptyCollection()]
        [Alias('Text')]
        [string[]]$Message,
        [Parameter(Mandatory=$false,Position=1)]
        [ValidateRange(1,3)]
        [int16]$Severity = 1,
        [Parameter(Mandatory=$false,Position=2)]
        [ValidateNotNull()]
        [string]$Source = 'Unknown',
        [Parameter(Mandatory=$false,Position=3)]
        [ValidateNotNullorEmpty()]
        [string]$ScriptSection = 'Unknown',
        [Parameter(Mandatory=$false,Position=4)]
        [ValidateSet('CMTrace','Legacy')]
        [string]$LogType = 'CMTrace',
        [Parameter(Mandatory=$false,Position=5)]
        [ValidateNotNullorEmpty()]
        [string]$LogFileDirectory = $script:LogFilePath,
        [Parameter(Mandatory=$false,Position=6)]
        [ValidateNotNullorEmpty()]
        [string]$LogFileName = $script:LogName,
        [Parameter(Mandatory=$false,Position=7)]
        [ValidateNotNullorEmpty()]
        [decimal]$MaxLogFileSizeMB = 2,
        [Parameter(Mandatory=$false,Position=8)]
        [ValidateNotNullorEmpty()]
        [boolean]$WriteHost = $false,
        [Parameter(Mandatory=$false,Position=9)]
        [ValidateNotNullorEmpty()]
        [boolean]$ContinueOnError = $true,
        [Parameter(Mandatory=$false,Position=10)]
        [switch]$PassThru = $false,
        [Parameter(Mandatory=$false,Position=11)]
        [switch]$DebugMessage = $false,
        [Parameter(Mandatory=$false,Position=12)]
        [boolean]$LogDebugMessage = $false
    )

    Begin {
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name

        ## Logging Variables
        #  Log file date/time
        [string]$LogTime = (Get-Date -Format 'HH\:mm\:ss.fff').ToString()
        [string]$LogDate = (Get-Date -Format 'MM-dd-yyyy').ToString()
        If (-not (Test-Path -LiteralPath 'variable:LogTimeZoneBias')) { [int32]$script:LogTimeZoneBias = [timezone]::CurrentTimeZone.GetUtcOffset([datetime]::Now).TotalMinutes }
        [string]$LogTimePlusBias = $LogTime + $script:LogTimeZoneBias
        #  Initialize variables
        [boolean]$ExitLoggingFunction = $false
        If (-not (Test-Path -LiteralPath 'variable:DisableLogging')) { $DisableLogging = $false }
        #  Check if the script section is defined
        [boolean]$ScriptSectionDefined = [boolean](-not [string]::IsNullOrEmpty($ScriptSection))
        #  Get the file name of the source script
        Try {
            If ($script:MyInvocation.Value.ScriptName) {
                [string]$ScriptSource = Split-Path -Path $script:MyInvocation.Value.ScriptName -Leaf -ErrorAction 'Stop'
            }
            Else {
                [string]$ScriptSource = Split-Path -Path $script:MyInvocation.MyCommand.Definition -Leaf -ErrorAction 'Stop'
            }
        }
        Catch {
            $ScriptSource = ''
        }

        ## Create script block for generating CMTrace.exe compatible log entry
        [scriptblock]$CMTraceLogString = {
            Param (
                [string]$lMessage,
                [string]$lSource,
                [int16]$lSeverity
            )
            "<![LOG[$lMessage]LOG]!>" + "<time=`"$LogTimePlusBias`" " + "date=`"$LogDate`" " + "component=`"$lSource`" " + "context=`"$([Security.Principal.WindowsIdentity]::GetCurrent().Name)`" " + "type=`"$lSeverity`" " + "thread=`"$PID`" " + "file=`"$ScriptSource`">"
        }

        ## Create script block for writing log entry to the console
        [scriptblock]$WriteLogLineToHost = {
            Param (
                [string]$lTextLogLine,
                [int16]$lSeverity
            )
            If ($WriteHost) {
                #  Only output using color options if running in a host which supports colors.
                If ($Host.UI.RawUI.ForegroundColor) {
                    Switch ($lSeverity) {
                        3 { Write-Host -Object $lTextLogLine -ForegroundColor 'Red' -BackgroundColor 'Black' }
                        2 { Write-Host -Object $lTextLogLine -ForegroundColor 'Yellow' -BackgroundColor 'Black' }
                        1 { Write-Host -Object $lTextLogLine }
                    }
                }
                #  If executing "powershell.exe -File <filename>.ps1 > log.txt", then all the Write-Host calls are converted to Write-Output calls so that they are included in the text log.
                Else {
                    Write-Output -InputObject $lTextLogLine
                }
            }
        }

        ## Exit function if it is a debug message and logging debug messages is not enabled in the config XML file
        If (($DebugMessage) -and (-not $LogDebugMessage)) { [boolean]$ExitLoggingFunction = $true; Return }
        ## Exit function if logging to file is disabled and logging to console host is disabled
        If (($DisableLogging) -and (-not $WriteHost)) { [boolean]$ExitLoggingFunction = $true; Return }
        ## Exit Begin block if logging is disabled
        If ($DisableLogging) { Return }
        ## Exit function function if it is an [Initialization] message and the toolkit has been relaunched
        If (($AsyncToolkitLaunch) -and ($ScriptSection -eq 'Initialization')) { [boolean]$ExitLoggingFunction = $true; Return }

        ## Create the directory where the log file will be saved
        If (-not (Test-Path -LiteralPath $LogFileDirectory -PathType 'Container')) {
            Try {
                $null = New-Item -Path $LogFileDirectory -Type 'Directory' -Force -ErrorAction 'Stop'
            }
            Catch {
                [boolean]$ExitLoggingFunction = $true
                #  If error creating directory, write message to console
                If (-not $ContinueOnError) {
                    Write-Host -Object "[$LogDate $LogTime] [${CmdletName}] $ScriptSection :: Failed to create the log directory [$LogFileDirectory]. `n$(Resolve-Error)" -ForegroundColor 'Red'
                }
                Return
            }
        }

        ## Assemble the fully qualified path to the log file
        [string]$LogFilePath = Join-Path -Path $LogFileDirectory -ChildPath $LogFileName
    }
    Process {
        ## Exit function if logging is disabled
        If ($ExitLoggingFunction) { Return }

        ForEach ($Msg in $Message) {
            ## If the message is not $null or empty, create the log entry for the different logging methods
            [string]$CMTraceMsg = ''
            [string]$ConsoleLogLine = ''
            [string]$LegacyTextLogLine = ''
            If ($Msg) {
                #  Create the CMTrace log message
                If ($ScriptSectionDefined) { [string]$CMTraceMsg = "[$ScriptSection] :: $Msg" }

                #  Create a Console and Legacy "text" log entry
                [string]$LegacyMsg = "[$LogDate $LogTime]"
                If ($ScriptSectionDefined) { [string]$LegacyMsg += " [$ScriptSection]" }
                If ($Source) {
                    [string]$ConsoleLogLine = "$LegacyMsg [$Source] :: $Msg"
                    Switch ($Severity) {
                        3 { [string]$LegacyTextLogLine = "$LegacyMsg [$Source] [Error] :: $Msg" }
                        2 { [string]$LegacyTextLogLine = "$LegacyMsg [$Source] [Warning] :: $Msg" }
                        1 { [string]$LegacyTextLogLine = "$LegacyMsg [$Source] [Info] :: $Msg" }
                    }
                }
                Else {
                    [string]$ConsoleLogLine = "$LegacyMsg :: $Msg"
                    Switch ($Severity) {
                        3 { [string]$LegacyTextLogLine = "$LegacyMsg [Error] :: $Msg" }
                        2 { [string]$LegacyTextLogLine = "$LegacyMsg [Warning] :: $Msg" }
                        1 { [string]$LegacyTextLogLine = "$LegacyMsg [Info] :: $Msg" }
                    }
                }
            }

            ## Execute script block to create the CMTrace.exe compatible log entry
            [string]$CMTraceLogLine = & $CMTraceLogString -lMessage $CMTraceMsg -lSource $Source -lSeverity $Severity

            ## Choose which log type to write to file
            If ($LogType -ieq 'CMTrace') {
                [string]$LogLine = $CMTraceLogLine
            }
            Else {
                [string]$LogLine = $LegacyTextLogLine
            }

            ## Write the log entry to the log file if logging is not currently disabled
            If (-not $DisableLogging) {
                Try {
                    $LogLine | Out-File -FilePath $LogFilePath -Append -NoClobber -Force -Encoding 'UTF8' -ErrorAction 'Stop'
                }
                Catch {
                    If (-not $ContinueOnError) {
                        Write-Host -Object "[$LogDate $LogTime] [$ScriptSection] [${CmdletName}] :: Failed to write message [$Msg] to the log file [$LogFilePath]. `n$(Resolve-Error)" -ForegroundColor 'Red'
                    }
                }
            }

            ## Execute script block to write the log entry to the console if $WriteHost is $true
            & $WriteLogLineToHost -lTextLogLine $ConsoleLogLine -lSeverity $Severity
        }
    }
    End {
        ## Archive log file if size is greater than $MaxLogFileSizeMB and $MaxLogFileSizeMB > 0
        Try {
            If ((-not $ExitLoggingFunction) -and (-not $DisableLogging)) {
                [IO.FileInfo]$LogFile = Get-ChildItem -LiteralPath $LogFilePath -ErrorAction 'Stop'
                [decimal]$LogFileSizeMB = $LogFile.Length/1MB
                If (($LogFileSizeMB -gt $MaxLogFileSizeMB) -and ($MaxLogFileSizeMB -gt 0)) {
                    ## Change the file extension to "lo_"
                    [string]$ArchivedOutLogFile = [IO.Path]::ChangeExtension($LogFilePath, 'lo_')
                    [hashtable]$ArchiveLogParams = @{ ScriptSection = $ScriptSection; Source = ${CmdletName}; Severity = 2; LogFileDirectory = $LogFileDirectory; LogFileName = $LogFileName; LogType = $LogType; MaxLogFileSizeMB = 0; WriteHost = $WriteHost; ContinueOnError = $ContinueOnError; PassThru = $false }

                    ## Log message about archiving the log file
                    $ArchiveLogMessage = "Maximum log file size [$MaxLogFileSizeMB MB] reached. Rename log file to [$ArchivedOutLogFile]."
                    Write-Log -Message $ArchiveLogMessage @ArchiveLogParams

                    ## Archive existing log file from <filename>.log to <filename>.lo_. Overwrites any existing <filename>.lo_ file. This is the same method SCCM uses for log files.
                    Move-Item -LiteralPath $LogFilePath -Destination $ArchivedOutLogFile -Force -ErrorAction 'Stop'

                    ## Start new log file and Log message about archiving the old log file
                    $NewLogMessage = "Previous log file was renamed to [$ArchivedOutLogFile] because maximum log file size of [$MaxLogFileSizeMB MB] was reached."
                    Write-Log -Message $NewLogMessage @ArchiveLogParams
                }
            }
        }
        Catch {
            ## If renaming of file fails, script will continue writing to log file even if size goes over the max file size
        }
        Finally {
            If ($PassThru) { Write-Output -InputObject $Message }
        }
    }
}

function Start-CustomProcess {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$Path,
        [string]$Arguments,
        [switch]$ServiceUI
    )
    try {
        if (Test-Path -Path $Path -PathType 'Leaf') {
            $Psi = New-Object -TypeName System.Diagnostics.ProcessStartInfo
            $Psi.CreateNoWindow = $true
            $Psi.UseShellExecute = $false
            $Psi.RedirectStandardOutput = $true
            $Psi.RedirectStandardError = $true
            if ($ServiceUI) {
                if (Test-Path -Path "$PSScriptRoot\ServiceUI.exe" -PathType 'Leaf') {
                    $Psi.FileName = "$PSScriptRoot\ServiceUI.exe"
                    if ($Arguments) {
                        $Psi.Arguments = @(
                            '-process:explorer.exe'
                            "`"$Path`""
                            "$Arguments"
                        )
                    }
                    else {
                        $Psi.Arguments = @(
                            '-process:explorer.exe'
                            "`"$Path`""
                        )
                    }
                }
                else {
                    throw "Failed to locate '$PSScriptRoot\ServiceUI.exe'."
                }
            }
            else {
                $Psi.FileName = $Path
                if ($Arguments) {
                    $Psi.Arguments = @("$Arguments")
                }
                else {
                    $Psi.Arguments = @()
                }
            }
            $Process = New-Object System.Diagnostics.Process
            $Process.StartInfo = $Psi
            Write-Log -Message "Starting Process with the following info: FileName: '$($Psi.FileName)', Arguments: '$($Psi.Arguments)', Working Directory: '$($Psi.WorkingDirectory)'" -Source 'System.Diagnostics.Process' -ScriptSection 'Start-CustomProcess'
            $null = $Process.Start()
            $Output = $Process.StandardOutput.ReadToEnd()
            Write-Log -Message "Waiting for Process Name '$($Process.ProcessName)', ID '$($Process.Id)' to end." -Source 'System.Diagnostics.Process' -ScriptSection 'Start-CustomProcess'
            $null = $Process.WaitForExit()
            Write-Log -Message "Process Name '$($Process.ProcessName)', ID '$($Process.Id)' has exited." -Source 'System.Diagnostics.Process' -ScriptSection 'Start-CustomProcess'
            Write-Log -Message "Process Output:`n$Output" -Source 'System.Diagnostics.Process' -ScriptSection 'Start-CustomProcess'
            return $Process.ExitCode
        }
        else {
            throw "Failed to locate '$Path'."
        }
    }
    catch {
        Write-Log -Message "Failed to start '$Path'. Error: `n$($_)" -Source 'Test-Path' -ScriptSection 'Start-CustomProcess' -Severity 3
        Write-Log -Message $LogDash -Source $ScriptSection
        return 69902
    }
    finally {
        $null = $Process.Dispose()
    }
}

function Remove-InvalidFileNameChars {
    param (
        [Parameter(Mandatory=$true,
        Position=0,
        ValueFromPipeline=$true,
        ValueFromPipelineByPropertyName=$true)]
        [String]$Name
    )

    try {
        $InvalidChars = [IO.Path]::GetInvalidFileNameChars() -join ''
        $Re = "[{0}]" -f [RegEx]::Escape($InvalidChars)
        return ($Name -replace $Re)
    }
    catch {
        Write-Log -Message "Problem converting string with escapable characters. Error: `n$($_)" -Source 'Remove-InvalidFileNameChars' -ScriptSection $ScriptSection -Severity 3
        Write-Log -Message $LogDash -Source $ScriptSection
        return 69902
    }
}

function Confirm-ESP {
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
                            Write-Log -Message "ESP detected as running: Null or Empty value received from registry location '$AutoPilotStartTimeKey '." -Source 'Confirm-ESP' -ScriptSection $ScriptSection -Severity 2
                        }
                        elseif ($($AutoPilotStartTimeValue.Count) -gt 1) {
                            Write-Log -Message "ESP detected as running: Multiple Date/Time values were returned. Count: '$($AutoPilotStartTimeValue.Count)'" -Source 'Confirm-ESP' -ScriptSection $ScriptSection -Severity 2
                        }
                        else {
                            $AutoPilotStartTime = $AutoPilotStartTimeValue.PSChildName
                        }

                        $FormattedTime = [datetime]::Parse($AutoPilotStartTime)
                        if ( $CurrentTime -ge $($FormattedTime.AddHours(1)) ) {
                            $AccountSetupNotRunning = $true
                        }
                        else {
                            Write-Log -Message "ESP detected as running: AutoPilot is still within the 1 hour allowance. Time that AutoPilot started '$AutoPilotStartTime', Time that this script ran '$CurrentTime'" -Source 'Confirm-ESP' -ScriptSection $ScriptSection -Severity 2
                        }
                    }
                    catch  {
                        Write-Log -Message "ESP detected as running: Time that AutoPilot started '$AutoPilotStartTime', Time that this script ran '$CurrentTime'" -Source 'Confirm-ESP' -ScriptSection $ScriptSection -Severity 2
                    }
                }

                if ($DevicePrepNotRunning -and $DeviceSetupNotRunning -and $AccountSetupNotRunning) {
                    $CategoryCount = 0
                }
                else {
                    $CategoryCount = 1
                }
            }
            else {
                $CategoryCount = 0
            }
        }
        else {
            $CategoryCount = 0
        }
        return $CategoryCount
    }
    catch {
        Write-Log -Message "Problem determining the ESP status. Error: `n$($_)" -Source 'Confirm-ESP' -ScriptSection $ScriptSection -Severity 3
        Write-Log -Message $LogDash -Source $ScriptSection
        exit 69902
    }
}

function Add-PowerUtil {
    $Namespaces = @(
        'System.Threading'
        'System.Threading.Tasks'
    )

    Add-Type -ErrorAction 'Stop' -Name 'PowerUtil' -Namespace 'Windows' -UsingNamespace $Namespaces -MemberDefinition @'
[Flags]
public enum EXECUTION_STATE : uint
{
    ES_AWAYMODE_REQUIRED = 0x00000040,
    ES_CONTINUOUS = 0x80000000,
    ES_DISPLAY_REQUIRED = 0x00000002,
    ES_SYSTEM_REQUIRED = 0x00000001
    // Legacy flag, should not be used.
    // ES_USER_PRESENT = 0x00000004
}
[DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
static extern uint SetThreadExecutionState(EXECUTION_STATE esFlags);

private static AutoResetEvent _event = new AutoResetEvent(false);

public static void PreventPowerSave()
{
    (new TaskFactory()).StartNew(() =>
        {
            SetThreadExecutionState(
                EXECUTION_STATE.ES_CONTINUOUS
                | EXECUTION_STATE.ES_DISPLAY_REQUIRED
                | EXECUTION_STATE.ES_SYSTEM_REQUIRED);
            _event.WaitOne();

        },
        TaskCreationOptions.LongRunning);
}

public static void Shutdown()
{
    _event.Set();
}
'@
}

try {
    if (Test-Path -Path "$PSScriptRoot\*-AppSettings.json" -PathType 'Leaf') {
        $Data = Get-Content -Path "$PSScriptRoot\*-AppSettings.json" -Raw | ConvertFrom-Json -ErrorAction 'Stop'
    }
    else {
        $Data = Get-Content -Path "$PSScriptRoot\*.txt" -Raw | ConvertFrom-Json -ErrorAction 'Stop'
    }
}
catch {
    exit 69900
}

try {
    $JsonFileValues = @(
        'Name'
        'Version'
        'Vendor'
    )

    foreach ($Item in $JsonFileValues) {
        if ([string]::IsNullOrEmpty($($Data.$Item))) {
            exit 69901
        }
    }
}
catch {
    exit 69901
}

#region Initialization
try {
    [string]$ScriptSection = 'Initialization'
    [string]$LogDash = '-' * 79
    [string]$LogName = (Remove-InvalidFileNameChars -Name "$($Data.Vendor)_$($Data.Name)_$($Data.Version)_$($Mode).log") -replace ' ',''
    [string]$LogFilePath = "$env:ProgramData\Logs\Software"

    #This MUST be changed each time this script is modified
    [string]$ConfigureFileVersion = '2.2.0.0'

    Write-Log -Message "Starting 'Configure.ps1' version: '$ConfigureFileVersion'" -Source 'Write-Log' -ScriptSection $ScriptSection
    Write-Log -Message "Starting $($Mode) process of $($Data.Name) $($Data.Version)" -Source 'Write-Log' -ScriptSection $ScriptSection

    $ExplorerProcesses = @(Get-CimInstance -ClassName 'Win32_Process' -Filter "Name like 'explorer.exe'" -ErrorAction 'SilentlyContinue')
    [int]$ESPCount = 0
    $ESPCount = Confirm-ESP

    # Import PowerUtil to be used as needed
    Add-PowerUtil
}
catch {
    Write-Log -Message 'There was an unexpected problem in the Initialization phase' -Source 'Write-Log' -ScriptSection $ScriptSection -Severity 3
    Write-Log -Message "Error Message: `n$($_)" -Source 'Write-Log' -ScriptSection $ScriptSection -Severity 3
    Write-Log -Message $LogDash -Source 'Write-Log' -ScriptSection $ScriptSection
    exit 69902
}
#endregion Initialization

#region Silent Processing
try {
    Write-Log -Message 'Preventing computer from going to sleep while app is installing.' -Source 'PowerUtil-PreventPowerSave' -ScriptSection $ScriptSection
    # Keep system awake, keep display on (prevent Modern Standby), provide reason as the current script command line
    [Windows.PowerUtil]::PreventPowerSave()

    if (($ExplorerProcesses.Count -eq 0) -or ($ESPCount -ne 0)) {
        if ($ExplorerProcesses.Count -eq 0) {
            Write-Log -Message "No user present, will attempt silent '$($Mode)'" -Source 'Get-CimInstance' -ScriptSection $ScriptSection
        }
        elseif ($ESPCount -ne 0) {
            Write-Log -Message "Enrollment Status Page detected, will attempt silent '$($Mode)'" -Source 'Get-CimInstance' -ScriptSection $ScriptSection
        }
        $ScriptSection = 'SilentProcessing'
        try {
            [string]$PowerShellPath = (Get-Command -Name 'powershell.exe').Source
            $DeployArgs = @(
                '-ExecutionPolicy Bypass'
                '-NoProfile'
                '-NoLogo'
                '-WindowStyle Hidden'
                "-File `"`"$PSScriptRoot\Deploy-Application.ps1`"`" -DeploymentType $($Mode) -DeployMode Silent"
            )
            Write-Log -Message "Performing silent '$($Mode)' with the following arguments '$DeployArgs'" -Source 'Start-CustomProcess' -ScriptSection $ScriptSection
            $ExitCode = Start-CustomProcess -Path $PowerShellPath -Arguments ($DeployArgs -join ' ')
        }
        catch {
            if ([string]::IsNullOrEmpty($ExitCode)) {
                Write-Log -Message "ExitCode was Null or Empty in silent '$($Mode)'" -Source 'Start-CustomProcess' -ScriptSection $ScriptSection -Severity 3
                Write-Log -Message "Error Message: `n$($_)" -Source 'Start-CustomProcess' -ScriptSection $ScriptSection -Severity 3
                Write-Log -Message $LogDash -Source 'Write-Log' -ScriptSection $ScriptSection
                $ExitCode = 69902
            }
            Write-Log -Message "Error occurred during '$($Mode)'" -Source 'Start-CustomProcess' -ScriptSection $ScriptSection -Severity 3
            Write-Log -Message "Error Message: `n$($_)" -Source 'Start-CustomProcess' -ScriptSection $ScriptSection -Severity 3
            throw $($_)
        }
    }
    #endregion Silent Processing
    #region Interactive Processing
    else {
        foreach ($TargetProcess in $ExplorerProcesses) {
            $Username = (Invoke-CimMethod -InputObject $TargetProcess -MethodName GetOwner).User
            Write-Log -Message "'$Username' logged in running explorer PID: '$($TargetProcess.ProcessId)'" -Source 'Invoke-CimMethod' -ScriptSection $ScriptSection
        }

        if ($UserName -ne 'defaultuser0') {
            Write-Log -Message "'$Username' appears to be normal user; launching process interactively." -Source 'Invoke-CimMethod' -ScriptSection $ScriptSection
            $ScriptSection = 'InteractiveProcessing'
            try {
                Write-Log -Message 'Running Deploy-Application.ps1 via vbscript from ServiceUI' -Source 'Start-CustomProcess' -ScriptSection $ScriptSection
                [string]$PowerShellPath = (Get-Command -Name 'powershell.exe').Source
                [string]$CScriptPath = (Get-Command -Name 'wscript.exe').Source
                $DeployArgs = @(
                    '-ExecutionPolicy Bypass'
                    '-NoProfile'
                    '-NoLogo'
                    '-WindowStyle Hidden'
                    "-File `"`"$PSScriptRoot\Deploy-Application.ps1`"`" -DeploymentType $($Mode)"
                )
                #Running VB Script to prevent command window from popping up during interactive install using ServiceUI
                $VBSStuff = @"
Set objShell = CreateObject("Wscript.Shell")
Set args = Wscript.Arguments
iReturn = objShell.Run("$PowerShellPath $($DeployArgs -join ' ')",0,True)
wscript.quit iReturn
"@
                $VBSStuff | Out-File -FilePath "$PSScriptRoot\ps-run.vbs" -Encoding 'ascii'
                $VBSArgs = @(
                    "//E:vbscript"
                    "\`"$PSScriptRoot\ps-run.vbs\`""
                )

                Write-Log -Message "Verifying that file '$PSScriptRoot\ps-run.vbs' is present on the system." -Source 'Test-Path' -ScriptSection $ScriptSection
                if (Test-Path -Path "$PSScriptRoot\ps-run.vbs" -PathType 'Leaf') {
                    Write-Log -Message "Starting CustomProcess function with path '$CScriptPath' and with the following arguments '$($VBSArgs -join ' ')' " -Source 'Start-CustomProcess' -ScriptSection $ScriptSection
                    $ExitCode = Start-CustomProcess -Path $CScriptPath -Arguments ($VBSArgs -join ' ') -ServiceUI
                }
                else {
                    Write-Log -Message "File '$PSScriptRoot\ps-run.vbs' was not present on the system." -Source 'Test-Path' -ScriptSection $ScriptSection -Severity 3
                    Write-Log -Message $LogDash -Source 'Write-Log' -ScriptSection $ScriptSection
                    $ExitCode = 69902
                }
            }
            catch {
                if ([string]::IsNullOrEmpty($ExitCode)) {
                    Write-Log -Message "ExitCode was Null or Empty in Interactive '$($Mode)'." -Source 'Start-CustomProcess' -ScriptSection $ScriptSection -Severity 3
                    Write-Log -Message "Error Message: `n$($_)" -Source 'Start-CustomProcess' -ScriptSection $ScriptSection -Severity 3
                    Write-Log -Message $LogDash -Source 'Write-Log' -ScriptSection $ScriptSection
                    $ExitCode = 69902
                }
                Write-Log -Message 'Error occurred attempting to launch ServiceUI' -Source 'Start-CustomProcess' -ScriptSection $ScriptSection -Severity 3
                Write-Log -Message "Error Message: `n$($_)" -Source 'Start-CustomProcess' -ScriptSection $ScriptSection -Severity 3
                throw $($_)
            }
        }
        else {
            $ScriptSection = 'SilentProcessing'
            Write-Log -Message "'$Username' is defaultuser0; launching process silently as we must still be in ESP." -Source 'Invoke-CimMethod' -ScriptSection $ScriptSection
            try {
                [string]$PowerShellPath = (Get-Command -Name 'powershell.exe').Source
                $DeployArgs = @(
                    '-ExecutionPolicy Bypass'
                    '-NoProfile'
                    '-NoLogo'
                    '-WindowStyle Hidden'
                    "-File `"`"$PSScriptRoot\Deploy-Application.ps1`"`" -DeploymentType $($Mode) -DeployMode Silent"
                )
                Write-Log -Message "Performing silent '$($Mode)' with the following arguments '$DeployArgs'" -Source 'Start-CustomProcess' -ScriptSection $ScriptSection
                $ExitCode = Start-CustomProcess -Path $PowerShellPath -Arguments ($DeployArgs -join ' ')
            }
            catch {
                if ([string]::IsNullOrEmpty($ExitCode)) {
                    Write-Log -Message "ExitCode was Null or Empty in silent '$($Mode)' for defaultuser0." -Source 'Start-CustomProcess' -ScriptSection $ScriptSection -Severity 3
                    Write-Log -Message $LogDash -Source 'Write-Log' -ScriptSection $ScriptSection
                    $ExitCode = 69902
                }
                Write-Log -Message "Error occurred during $($Mode)" -Source 'Start-CustomProcess' -ScriptSection $ScriptSection -Severity 3
                Write-Log -Message "Error Message: `n$($_)" -Source 'Start-CustomProcess' -ScriptSection $ScriptSection -Severity 3
                throw $($_)
            }
        }
    }
}
catch {
    Write-Log -Message 'There was an unexpected problem in the Processing phase' -Source 'Write-Log' -ScriptSection $ScriptSection -Severity 3
    Write-Log -Message "Error Message: `n$($_)" -Source 'Write-Log' -ScriptSection $ScriptSection -Severity 3
    Write-Log -Message $LogDash -Source 'Write-Log' -ScriptSection $ScriptSection
    exit 69902
}
finally {
    Write-Log -Message "Returning to default sleep state policy. Computer may have turned off at '$(Get-Date)' depending on state." -Source 'PowerUtil-Shutdown' -ScriptSection $ScriptSection
    # Clear the power requests.
    [Windows.PowerUtil]::Shutdown()
}

#endregion Interactive Processing
try {
    $ScriptSection = 'Post-Processing'
    Write-Log -Message "$($Mode) Exit Code = $($ExitCode)" -Source 'Write-Log' -ScriptSection $ScriptSection
    exit $ExitCode
}
catch {
    Write-Log -Message 'There was an unexpected problem in the Post-Processing phase' -Source 'Write-Log' -ScriptSection $ScriptSection -Severity 3
    Write-Log -Message "Error Message: `n$($_)" -Source 'Write-Log' -ScriptSection $ScriptSection -Severity 3
    Write-Log -Message $LogDash -Source 'Write-Log' -ScriptSection $ScriptSection
    exit 69902
}
finally {
    Write-Log -Message $LogDash -Source 'Write-Log' -ScriptSection $ScriptSection
}
