[CmdletBinding()]
param(
    [ValidateSet('Menu', 'Diagnose', 'Maintenance')]
    [string]$Mode = 'Menu'
)

$ErrorActionPreference = 'Stop'
$ScriptRoot = Split-Path -Parent $PSScriptRoot
$LogDirectory = Join-Path $ScriptRoot 'logs'
$LogFile = $null

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Start-InfraLog {
    if (-not (Test-Path -LiteralPath $LogDirectory)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:LogFile = Join-Path $LogDirectory "infra-check-$timestamp.log"
    "Infra Check | $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Set-Content -LiteralPath $script:LogFile -Encoding UTF8
    Write-Log 'INFO' "Log criado em $script:LogFile"
}

function Write-Log {
    param(
        [Parameter(Mandatory)] [string]$Level,
        [Parameter(Mandatory)] [string]$Message
    )

    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
    Write-Host $line
    if ($script:LogFile) {
        Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
    }
}

function Convert-ToGiB {
    param([double]$Bytes)
    return [Math]::Round($Bytes / 1GB, 2)
}

function Invoke-Diagnosis {
    Write-Log 'INFO' 'Iniciando diagnostico do computador.'

    $computer = Get-CimInstance -ClassName Win32_ComputerSystem
    $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem
    $totalMemory = [double]$computer.TotalPhysicalMemory
    $freeMemory = [double]$operatingSystem.FreePhysicalMemory * 1KB
    $usedMemoryPercent = [Math]::Round((($totalMemory - $freeMemory) / $totalMemory) * 100, 1)

    Write-Log 'INFO' ("Computador: {0} | Sistema: {1}" -f $env:COMPUTERNAME, $operatingSystem.Caption)
    Write-Log 'INFO' ("Memoria: {0} GB total | {1} GB livre | {2}% em uso" -f (Convert-ToGiB $totalMemory), (Convert-ToGiB $freeMemory), $usedMemoryPercent)
    if ($usedMemoryPercent -ge 85) {
        Write-Log 'WARN' 'Uso de memoria elevado. Em equipamentos com 4 GB, feche aplicativos nao essenciais e avalie expansao de memoria.'
    }

    $uptime = (Get-Date) - $operatingSystem.LastBootUpTime
    Write-Log 'INFO' ("Tempo desde a ultima inicializacao: {0} dias, {1} horas" -f [Math]::Floor($uptime.TotalDays), $uptime.Hours)

    Write-Log 'INFO' 'Unidades locais:'
    Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType = 3' | ForEach-Object {
        $freePercent = if ($_.Size -gt 0) { [Math]::Round(($_.FreeSpace / $_.Size) * 100, 1) } else { 0 }
        Write-Log 'INFO' ("  {0} | {1} GB livre de {2} GB ({3}%)" -f $_.DeviceID, (Convert-ToGiB $_.FreeSpace), (Convert-ToGiB $_.Size), $freePercent)
        if ($freePercent -lt 15) {
            Write-Log 'WARN' ("  Pouco espaco livre na unidade {0}." -f $_.DeviceID)
        }
    }

    Write-Log 'INFO' 'Servicos essenciais:'
    $services = @(
        @{ Name = 'Spooler'; Label = 'Spooler de Impressao' },
        @{ Name = 'wuauserv'; Label = 'Windows Update' },
        @{ Name = 'WinDefend'; Label = 'Microsoft Defender' }
    )
    foreach ($serviceInfo in $services) {
        $service = Get-Service -Name $serviceInfo.Name -ErrorAction SilentlyContinue
        if ($null -eq $service) {
            Write-Log 'WARN' ("  {0}: servico nao encontrado." -f $serviceInfo.Label)
        } else {
            Write-Log 'INFO' ("  {0}: {1}" -f $serviceInfo.Label, $service.Status)
        }
    }

    Write-Log 'INFO' 'Processos com maior consumo de memoria:'
    Get-Process | Where-Object { $_.ProcessName -ne 'Idle' } | Sort-Object -Property WorkingSet64 -Descending | Select-Object -First 8 | ForEach-Object {
        Write-Log 'INFO' ("  {0} (PID {1}): {2} MB" -f $_.ProcessName, $_.Id, [Math]::Round($_.WorkingSet64 / 1MB, 1))
    }

    Write-Log 'INFO' 'Processos com maior tempo de CPU:'
    Get-Process | Where-Object { $_.ProcessName -ne 'Idle' } | Sort-Object -Property CPU -Descending | Select-Object -First 8 | ForEach-Object {
        Write-Log 'INFO' ("  {0} (PID {1}): {2} s" -f $_.ProcessName, $_.Id, [Math]::Round($_.CPU, 1))
    }

    try {
        $errors = Get-WinEvent -FilterHashtable @{ LogName = 'System'; Level = 2; StartTime = (Get-Date).AddDays(-1) } -MaxEvents 5
        if ($errors) {
            Write-Log 'WARN' 'Erros recentes do log do Sistema (ultimas 24 horas):'
            foreach ($event in $errors) {
                $summary = ($event.Message -replace '[\r\n]+', ' ').Trim()
                if ($summary.Length -gt 180) { $summary = $summary.Substring(0, 180) + '...' }
                Write-Log 'WARN' ("  Evento {0} | {1}" -f $event.Id, $summary)
            }
        } else {
            Write-Log 'INFO' 'Nenhum erro critico recente encontrado no log do Sistema.'
        }
    } catch {
        Write-Log 'WARN' ("Nao foi possivel consultar os eventos do Sistema: {0}" -f $_.Exception.Message)
    }

    try {
        $startupItems = Get-CimInstance -ClassName Win32_StartupCommand | Select-Object -First 12
        if ($startupItems) {
            Write-Log 'INFO' 'Itens de inicializacao (revise os que nao forem necessarios):'
            foreach ($item in $startupItems) {
                Write-Log 'INFO' ("  {0}" -f $item.Name)
            }
        }
    } catch {
        Write-Log 'WARN' 'Nao foi possivel listar os itens de inicializacao.'
    }

    Write-Log 'INFO' 'Diagnostico concluido.'
}

function Remove-ContentsSafely {
    param([Parameter(Mandatory)] [string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return 0 }

    $removedBytes = 0L
    Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            if (-not $_.PSIsContainer) { $removedBytes += $_.Length }
            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Log 'WARN' ("Nao foi possivel remover {0}: {1}" -f $_.FullName, $_.Exception.Message)
        }
    }
    return $removedBytes
}

function Invoke-SafeMaintenance {
    Write-Log 'INFO' 'Iniciando manutencao segura.'
    Write-Log 'INFO' 'Nenhum servico, antivirus, atualizacao ou arquivo de paginacao sera desativado.'

    $paths = @($env:TEMP, (Join-Path $env:WINDIR 'Temp'))
    $totalRemoved = 0L
    foreach ($path in $paths) {
        Write-Log 'INFO' ("Limpando temporarios: {0}" -f $path)
        $totalRemoved += Remove-ContentsSafely -Path $path
    }

    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        Write-Log 'INFO' 'Lixeira limpa.'
    } catch {
        Write-Log 'WARN' ("Nao foi possivel limpar a Lixeira: {0}" -f $_.Exception.Message)
    }

    Write-Log 'INFO' ("Arquivos temporarios removidos: aproximadamente {0} MB" -f [Math]::Round($totalRemoved / 1MB, 1))
    Write-Log 'INFO' 'Manutencao segura concluida. Execute o diagnostico novamente para comparar o estado do computador.'
}

function Show-Menu {
    do {
        Clear-Host
        Write-Host '=== Infra Check ==='
        Write-Host '1 - Executar diagnostico'
        Write-Host '2 - Executar manutencao segura'
        Write-Host '3 - Diagnostico seguido de manutencao segura'
        Write-Host '0 - Sair'
        $choice = Read-Host 'Escolha uma opcao'

        switch ($choice) {
            '1' { Invoke-Diagnosis; Pause }
            '2' { Invoke-SafeMaintenance; Pause }
            '3' { Invoke-Diagnosis; Invoke-SafeMaintenance; Pause }
            '0' { return }
            default { Write-Host 'Opcao invalida.'; Start-Sleep -Seconds 1 }
        }
    } while ($true)
}

try {
    if (-not (Test-Administrator)) {
        throw 'Execute este script em um PowerShell aberto como Administrador.'
    }

    Start-InfraLog
    switch ($Mode) {
        'Diagnose' { Invoke-Diagnosis }
        'Maintenance' { Invoke-SafeMaintenance }
        'Menu' { Show-Menu }
    }
} catch {
    if ($script:LogFile) {
        Write-Log 'ERROR' $_.Exception.Message
    } else {
        Write-Error $_.Exception.Message
    }
    exit 1
}
