function write-DRMMDiag ($messages) {
    write-host  '<-Start Diagnostic->'
    foreach ($Message in $Messages) { $Message }
    write-host '<-End Diagnostic->'
} 
function write-DRRMAlert ($message) {
    write-host '<-Start Result->'
    write-host "Alert=$message"
    write-host '<-End Result->'
}

function Test-RegistryKey {
    [OutputType('bool')]
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Key
    )

    $ErrorActionPreference = 'Stop'

    if (Get-Item -Path $Key -ErrorAction Ignore) {
        $true
    }
}

function Test-RegistryValue {
    [OutputType('bool')]
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Key,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Value
    )

    $ErrorActionPreference = 'Stop'

    if (Get-ItemProperty -Path $Key -Name $Value -ErrorAction Ignore) {
        $true
    }
}

function Test-RegistryValueNotNull {
    [OutputType('bool')]
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Key,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Value
    )

    $ErrorActionPreference = 'Stop'

    if (($regVal = Get-ItemProperty -Path $Key -Name $Value -ErrorAction Ignore) -and $regVal.($Value)) {
        $true
    }
}



$tests = @(
    { Test-RegistryKey -Key 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending' }
    { Test-RegistryKey -Key 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootInProgress' }
    { Test-RegistryKey -Key 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired' }
    { Test-RegistryKey -Key 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending' }
    { Test-RegistryKey -Key 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\PostRebootReporting' }
    { Test-RegistryValueNotNull -Key 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Value 'PendingFileRenameOperations' }
    { Test-RegistryValueNotNull -Key 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Value 'PendingFileRenameOperations2' }
    { 
        # Added test to check first if key exists, using "ErrorAction ignore" will incorrectly return $true
        'HKLM:\SOFTWARE\Microsoft\Updates' | Where-Object { test-path $_ -PathType Container } | ForEach-Object {            
            (Get-ItemProperty -Path $_ -Name 'UpdateExeVolatile' | Select-Object -ExpandProperty UpdateExeVolatile) -ne 0 
        }
    }
    { Test-RegistryValue -Key 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Value 'DVDRebootSignal' }
    { Test-RegistryKey -Key 'HKLM:\SOFTWARE\Microsoft\ServerManager\CurrentRebootAttemps' }
    { Test-RegistryValue -Key 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon' -Value 'JoinDomain' }
    { Test-RegistryValue -Key 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon' -Value 'AvoidSpnSet' }
    {
        # Added test to check first if keys exists, if not each group will return $Null
        # May need to evaluate what it means if one or both of these keys do not exist
        ( 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' | Where-Object { test-path $_ } | %{ (Get-ItemProperty -Path $_ ).ComputerName } ) -ne 
        ( 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' | Where-Object { Test-Path $_ } | %{ (Get-ItemProperty -Path $_ ).ComputerName } )
    }
    {
        # Added test to check first if key exists
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Services\Pending' | Where-Object { 
            (Test-Path $_) -and (Get-ChildItem -Path $_) } | ForEach-Object { $true }
    }
)

foreach ($test in $tests) {
    if (& $test) {
        $RebootPending = $true
        break
    }
}

#$registryPath = "HKLM:\Software\CentraStage"
#$ValueName = "RebootPending_Date"
#$DateUpdateNeeded = $null
#if ((Get-Item $registryPath -EA Ignore).Property -contains $ValueName) {
#    $DateRegister = Get-ItemProperty -Path HKLM:\SOFTWARE\CentraStage -Name "RebootPending_Date"
#    $DateUpdateNeeded = $DateRegister.'RebootPending_Date'    
#}

$BootTimes = Get-CimInstance -ClassName win32_operatingsystem | select csname, lastbootuptime
foreach ($BootTime in $BootTimes){    
    $LastBootTime = $BootTime.lastbootuptime
}


if ($RebootPending){
    #if ($null -ne $DateUpdateNeeded) {
        $CalcDat = Get-Date
        $CalcDat = $CalcDat.AddDays(-30)
        $CalcDat = ($CalcDat).toString("yyyy-MM-dd")        
        $LastBootTime = ($LastBootTime).toString("yyyy-MM-dd")    
        #If ($DateUpdateNeeded -lt $CalcDat) {
        If ($LastBootTime -lt $CalcDat) {
            $errors = "Server reboot was longer than 30 days ago, reboot pending"
        }
    #}else{    
    #    $Value = Get-Date -Format "yyyy-MM-dd"
    #    New-ItemProperty -Path $registryPath -Name $ValueName -Value $value -PropertyType String -Force | Out-Null
    #}
}

if (!$errors) { 
    write-DRRMAlert "Healthy - No reboot needed"
}
else { 
    write-DRRMAlert "Unhealthy - Reboot needed"
    write-DRMMDiag $Errors
    exit 1
}
