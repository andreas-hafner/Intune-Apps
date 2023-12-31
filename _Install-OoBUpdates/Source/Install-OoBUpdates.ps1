#region Initialisation...
<#

.COPYRIGHT
Copyright (c) Microsoft Corporation. All rights reserved. Licensed under the MIT license.
See LICENSE in the project root for license information.

#>
####################################################
####################################################
#Instantiate Vars
####################################################
[CmdLetBinding()]
param(
    [Parameter()]
    [switch] $Install,
    [switch] $UnInstall,
    [switch] $userInstall,
    [string] $tagFile
)

$script:exitCode = 0

#Restart as 64-bit
if (![System.Environment]::Is64BitProcess) {
    # start new PowerShell as x64 bit process, wait for it and gather exit code and standard error output
    $sysNativePowerShell = "$($PSHOME.ToLower().Replace("syswow64", "sysnative"))\powershell.exe"

    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $sysNativePowerShell
    $pinfo.Arguments = "-ex bypass -file `"$PSCommandPath`""
    $pinfo.RedirectStandardError = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.CreateNoWindow = $true
    $pinfo.UseShellExecute = $false
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $pinfo
    $p.Start() | Out-Null

    $exitCode = $p.ExitCode

    $stderr = $p.StandardError.ReadToEnd()

    if ($stderr) { Write-Error -Message $stderr }
}

$script:BuildVer = "1.0"
$script:ProgramFiles = $env:ProgramFiles
$script:ParentFolder = $PSScriptRoot | Split-Path -Parent
$script:ScriptName = $myInvocation.MyCommand.Name
$script:ScriptName = $scriptName.Substring(0, $scriptName.Length - 4)
$script:LogName = $scriptName + "_" + (Get-Date -UFormat "%d-%m-%Y")
If ( $userInstall ) {
    $script:logPath = "$($env:LOCALAPPDATA)\Microsoft\IntuneApps\$scriptName"
}
Else { 
    $script:logPath = "$($env:ProgramData)\Microsoft\IntuneApps\$scriptName" 
}
$script:logFile = "$logPath\$LogName.log"
Add-Type -AssemblyName Microsoft.VisualBasic
$script:EventLogName = "Application"
$script:EventLogSource = "EventSystem"

####################################################
####################################################
#Build Functions
####################################################

Function Start-Log {
    param (
        [string]$FilePath,

        [Parameter(HelpMessage = 'Deletes existing file if used with the -DeleteExistingFile switch')]
        [switch]$DeleteExistingFile
    )
		
    #Create Event Log source if it's not already found...
    If (!([system.diagnostics.eventlog]::SourceExists($EventLogSource))) { New-EventLog -LogName $EventLogName -Source $EventLogSource }

    Try {
        If (!(Test-Path $FilePath)) {
            ## Create the log file
            New-Item $FilePath -Type File -Force | Out-Null
        }
            
        If ($DeleteExistingFile) {
            Remove-Item $FilePath -Force
        }
			
        ## Set the global variable to be used as the FilePath for all subsequent Write-Log
        ## calls in this session
        $script:ScriptLogFilePath = $FilePath
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}

####################################################

Function Write-Log {
    #Write-Log -Message 'warning' -LogLevel 2
    #Write-Log -Message 'Error' -LogLevel 3
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
			
        [Parameter()]
        [ValidateSet(1, 2, 3)]
        [int]$LogLevel = 1,

        [Parameter(HelpMessage = 'Outputs message to Event Log,when used with -WriteEventLog')]
        [switch]$WriteEventLog
    )
    Write-Host
    Write-Host $Message
    Write-Host
    $TimeGenerated = "$(Get-Date -Format HH:mm:ss).$((Get-Date).Millisecond)+000"
    $Line = '<![LOG[{0}]LOG]!><time="{1}" date="{2}" component="{3}" context="" type="{4}" thread="" file="">'
    $LineFormat = $Message, $TimeGenerated, (Get-Date -Format MM-dd-yyyy), "$($MyInvocation.ScriptName | Split-Path -Leaf):$($MyInvocation.ScriptLineNumber)", $LogLevel
    $Line = $Line -f $LineFormat
    Add-Content -Value $Line -Path $ScriptLogFilePath
    If ($WriteEventLog) { Write-EventLog -LogName $EventLogName -Source $EventLogSource -Message $Message  -Id 100 -Category 0 -EntryType Information }
}

####################################################

Function New-IntuneTag {
    <#
    .SYNOPSIS
    .DESCRIPTION
    .EXAMPLE
    .PARAMETER
    .INPUTS
    .OUTPUTS
    .NOTES
    .LINK
#>
    Param (
        [string]$TagFilePath = "$($env:ProgramData)\Microsoft\IntuneApps\$scriptName\",
        [string]$tagName
    )
              
    Begin {
        Write-Log -Message "Starting $($MyInvocation.InvocationName) function..."
    }

    Process {
        # Create a tag file just so Intune knows this was installed
        Write-Log "Creating Intune Tag file path: [$TagFilePath]"

        If (-not (Test-Path $TagFilePath) ) {

            New-Item -Path $TagFilePath -ItemType "directory" -Force | out-null
        }

        # Check if tagName already has .tag at the end
        If ($tagName.Substring(($tagName.Length - 4), 4) -eq ".tag") {
            Write-Log -Message "Using passed in tagName: $tagName"
            $tagFileName = "$TagFilePath\$tagName"
        }
        Else {
            Write-Log -Message "Using default of scriptname: $tagName and appending .tag"
            $tagFileName = "$TagFilePath\$tagName.tag"
        }
        
        Write-Log "Creating Intune Tag file: [$tagFileName]"
                       
        Set-Content -Path $tagFileName -Value "Installed"

        Write-Log -Message "Created Intune Tag file: [$tagFileName]"
                
    }
}

####################################################

Function Remove-IntuneTag {
    <#
    .SYNOPSIS
    .DESCRIPTION
    .EXAMPLE
    .PARAMETER
    .INPUTS
    .OUTPUTS
    .NOTES
    .LINK
#>
    Param (
        [string]$TagFilePath = "$($env:ProgramData)\Microsoft\IntuneApps\$scriptName\",
        [string]$tagName
    )
              
    Begin {
        Write-Log -Message "Starting $($MyInvocation.InvocationName) function..."
    }

    Process {
        # Remove the tag file so Intune knows this was uninstalled
        # Check if tagName already has .tag at the end
        If ($tagName.Substring(($tagName.Length - 4), 4) -eq ".tag") {
            Write-Log -Message "Using passed in tagName: $tagName"
            $tagFileName = "$TagFilePath\$tagName"
        }
        Else {
            Write-Log -Message "Using default of scriptname: $tagName and appending .tag"
            $tagFileName = "$TagFilePath\$tagName.tag"
        }
        
        Write-Log "Removing Intune Tag file: [$tagFileName]"
        
        If (Test-Path $tagFileName) {
            Remove-Item -Path $tagFileName -Force
        }

    }
}

####################################################

Function New-IntuneRegTag {
    <#
    .SYNOPSIS
    .DESCRIPTION
    .EXAMPLE
    .PARAMETER
    .INPUTS
    .OUTPUTS
    .NOTES
    .LINK
#>
    Param (
        [string]$TagRegPath = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\IntuneApps\",
        [string]$tagName
    )
              
    Begin {
        Write-Log -Message "Starting $($MyInvocation.InvocationName) function..."
    }

    Process {
        # Create a registry tag just so Intune knows this was installed
        Write-Log "Creating Intune Tag file path: [$TagRegPath\$tagName]"

        #Get-ItemProperty -Path "HKLM:\SOFTWARE\$TagRegPath" -Name $tagName

        New-Item -Path "Registry::$TagRegPath" -Force

        $returnCode = New-ItemProperty -Path "Registry::$TagRegPath" -Name $tagName -PropertyType String -Value "Installed" -Force
        Write-Log -Message "Return code: $returnCode" 
    }
}

####################################################

Function Remove-IntuneRegTag {
    <#
    .SYNOPSIS
    .DESCRIPTION
    .EXAMPLE
    .PARAMETER
    .INPUTS
    .OUTPUTS
    .NOTES
    .LINK
#>
    Param (
        [string]$TagRegPath = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\IntuneApps\",
        [string]$tagName
    )
              
    Begin {
        Write-Log -Message "Starting $($MyInvocation.InvocationName) function..."
    }

    Process {
        # Remove registry tag just so Intune knows this was uninstalled
        Write-Log "Removing Intune Tag file path: [$TagRegPath\$tagName]"
        
        $returnCode = Remove-ItemProperty -Path "Registry::$TagRegPath" -Name $tagName -Force
        Write-Log -Message "Return code: $returnCode"
    }
}

####################################################

Function New-RegKey {
    param($key)
  
    $key = $key -replace ':', ''
    $parts = $key -split '\\'
  
    $tempkey = ''
    $parts | ForEach-Object {
        $tempkey += ($_ + "\")
        if ( (Test-Path "Registry::$tempkey") -eq $false) {
            New-Item "Registry::$tempkey" | Out-Null
        }
    }
}

####################################################

function IsNull($objectToCheck) {
    if ($objectToCheck -eq $null) {
        return $true
    }

    if ($objectToCheck -is [String] -and $objectToCheck -eq [String]::Empty) {
        return $true
    }

    if ($objectToCheck -is [DBNull] -or $objectToCheck -is [System.Management.Automation.Language.NullString]) {
        return $true
    }

    return $false
}

####################################################

Function Get-XMLConfig {
    <#
.SYNOPSIS
This function reads the supplied XML Config file
.DESCRIPTION
This function reads the supplied XML Config file
.EXAMPLE
Get-XMLConfig -XMLFile PathToXMLFile
This function reads the supplied XML Config file
.NOTES
NAME: Get-XMLConfig
#>

    [cmdletbinding()]

    param
    (
        [Parameter(Mandatory = $true)]
        [string]$XMLFile,

        [bool]$Skip = $false
    )

    Begin {
        Write-Log -Message "$($MyInvocation.InvocationName) function..."
    }

    Process {
            
        If (-Not(Test-Path $XMLFile)) {
            Write-Log -Message "Error - XML file not found: $XMLFile" -LogLevel 3
            Return $Skip = $true
        }
        Write-Log -Message "Reading XML file: $XMLFile"
        [xml]$script:XML_Content = Get-Content $XMLFile

        ForEach ($XMLEntity in $XML_Content.GetElementsByTagName("Azure_Settings")) {
            $script:baseUrl = [string]$XMLEntity.baseUrl
            $script:logRequestUris = [string]$XMLEntity.logRequestUris
            $script:logHeaders = [string]$XMLEntity.logHeaders
            $script:logContent = [string]$XMLEntity.logContent
            $script:azureStorageUploadChunkSizeInMb = [int32]$XMLEntity.azureStorageUploadChunkSizeInMb
            $script:sleep = [int32]$XMLEntity.sleep
        }

        ForEach ($XMLEntity in $XML_Content.GetElementsByTagName("IntuneWin_Settings")) {
            $script:PackageName = [string]$XMLEntity.PackageName
            $script:displayName = [string]$XMLEntity.displayName
            $script:Description = [string]$XMLEntity.Description
            $script:Publisher = [string]$XMLEntity.Publisher
        }

    }

    End {
        If ($Skip) { Return }# Just return without doing anything else
        Write-Log -Message "Returning..."
        Return
    }

}

####################################################

Start-Log -FilePath $logFile -DeleteExistingFile
Write-Host
Write-Host "Script log file path is [$logFile]" -f Cyan
Write-Host
Write-Log -Message "Starting $scriptName version $BuildVer" -WriteEventLog

#region IntuneCodeSample
# === variant 1: use try/catch with ErrorAction stop -> use write-error to signal Intune failed execution
# example:
# try
# {
#     Set-ItemProperty ... -ErrorAction Stop
# }
# catch
# {   
#     Write-Error -Message "Could not write regsitry value" -Category OperationStopped
#     $exitCode = -1
# }

# === variant 2: ErrorVariable and check error variable -> use write-error to signal Intune failed execution
# example:
# Start-Process ... -ErrorVariable err -ErrorAction SilentlyContinue
# if ($err)
# {
#     Write-Error -Message "Could not write regsitry value" -Category OperationStopped
#     $exitCode = -1
# }
#endregion IntuneCodeSample

#endregion Initialisation...
##########################################################################################################
##########################################################################################################

#region Main Script work section
##########################################################################################################
##########################################################################################################
# Main Script work section
##########################################################################################################
##########################################################################################################
$destination = "C:\Program Files\Tools\Install-OoBUpdates"
$schTaskName = "OutOfBandOSUpdates"
$schTaskDescription = "Out of band emergency OS patching"

If ($Install) {
    Write-Log -Message "Performing Install steps..."
    
    New-Item $destination -type directory -Force -ErrorAction SilentlyContinue

    $eventLogName = "OutOfBandOSUpdates"
    $eventLogSource = "OutOfBandOSUpdates"
    $eventSources = @($EventLogSource)

    <# Setup Event Logging #>
    New-Eventlog -LogName $eventLogName -Source $eventLogSource -ErrorAction SilentlyContinue
    foreach ($source in $eventSources) {
        if ([System.Diagnostics.EventLog]::SourceExists($source) -eq $false) {
            [System.Diagnostics.EventLog]::CreateEventSource($source, $eventLogName)
        }
    }

    # Get-ChildItem -Path $PSScriptRoot | Copy-Item -Destination $destination -Recurse -Container
    Copy-Item -Path "$PSScriptRoot\Update-OS.ps1" -Destination $destination -Force
    Copy-Item -Path "$PSScriptRoot\OutOfBandOSUpdatesRebootTaskTrigger.xml" -Destination $destination -Force

    # Enable Scheduled Tasks All History option
    $logName = 'Microsoft-Windows-TaskScheduler/Operational'
    $log = New-Object System.Diagnostics.Eventing.Reader.EventLogConfiguration $logName
    $log.IsEnabled = $true
    $log.SaveChanges()

    # Register Scheduled Task to call the Update-OS.ps1 script when specific Event ID occurs
    $arg = '-NoProfile -Executionpolicy Bypass -WindowStyle Hidden -file "' + $destination + '\Update-OS.ps1"'
    $schTaskAction = New-ScheduledTaskAction -Execute 'Powershell.exe' -Argument $arg
    $schTaskPrin = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount
    $schTaskTrig = Import-Clixml "$PSScriptRoot\OutOfBandOSUpdatesRebootTaskTrigger.xml"
    $schTaskSett = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 0) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -DontStopOnIdleEnd
    Register-ScheduledTask -Action $schTaskAction -Trigger $schTaskTrig -Settings $schTaskSett -Principal $schTaskPrin -TaskName $schTaskName -Description $schTaskDescription

    If ( ! ( IsNull($tagFile) ) ) {
            Write-Log -Message "Using tagFile name: $tagFile"
            New-IntuneTag -TagFilePath "$logPath" -tagName $tagFile
        }
        Else { 
            Write-Log -Message "Using default tagFile name: $scriptName"
            New-IntuneTag -TagFilePath "$logPath" -tagName $scriptName
        }
}
ElseIf ($UnInstall) {
    Write-Log -Message "Performing Uninstall steps..."

    <# Remove Scheduled Task #>
    Unregister-ScheduledTask -TaskName $schTaskName -Confirm:$false -InformationAction SilentlyContinue
    Remove-Item -Path $destination -Recurse -Force -Confirm:$false

    If ( ! ( IsNull ( $tagFile ) ) ) {
        Write-Log -Message "Removing tagFile name: $tagFile"
        Remove-IntuneTag -TagFilePath "$logPath" -tagName $tagFile
    }
    Else { 
        Write-Log -Message "Removing default tagFile name: $scriptName"
        Remove-IntuneTag -TagFilePath "$logPath" -tagName $scriptName 
    }
}


Write-Log "$scriptName completed." -WriteEventLog
exit $exitCode

##########################################################################################################
##########################################################################################################
#endregion Main Script work section