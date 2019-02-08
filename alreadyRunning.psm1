Function Test-IfAlreadyRunning {
    <#
    .SOURCE
    https://gist.github.com/mark0203/0b09d793e9fcbaf1ed330b852a998f58
    .SYNOPSIS
        Kills CURRENT instance if this script already running.
    .DESCRIPTION
        Kills CURRENT instance if this script already running.
        Call this function VERY early in your script.
        If it sees itself already running, it exits.

        Uses WMI because any other methods because we need the commandline 
    .PARAMETER ScriptName
        Name of this script
        Use the following line *OUTSIDE* of this function to get it automatically
        $ScriptName = $MyInvocation.MyCommand.Name
    .EXAMPLE
        $ScriptName = $MyInvocation.MyCommand.Name
        Test-IfAlreadyRunning -ScriptName $ScriptName
    .NOTES
        $PID is a Built-in Variable for the current script''s Process ID number
    .LINK
    #>
        [CmdletBinding()]
        Param (
            [Parameter(Mandatory=$true)]
            [ValidateNotNullorEmpty()]
            [String]$ScriptName
        )
        #Get array of all powershell scripts currently running
        $PsScriptsRunning = get-wmiobject win32_process | where{$_.processname -eq 'powershell.exe'} | select-object commandline,ProcessId

        #Get name of current script
        #$ScriptName = $MyInvocation.MyCommand.Name #NO! This gets name of *THIS FUNCTION*

        #enumerate each element of array and compare
        ForEach ($PsCmdLine in $PsScriptsRunning){
            [Int32]$OtherPID = $PsCmdLine.ProcessId
            [String]$OtherCmdLine = $PsCmdLine.commandline
            #Are other instances of this script already running?
            If (($OtherCmdLine -match $ScriptName) -And ($OtherPID -ne $PID) ){
		Add-content $logFile -value "$(Get-Date -format HH:mm:ss) - Error - PID [$OtherPID] eis already running task : [$ScriptName]"
                Exit
            }
        }
    } #Function Test-IfAlreadyRunning
