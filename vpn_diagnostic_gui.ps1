# Enforce STA mode if run directly from a console shortcut
# Requires -STA

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ==============================
# CONFIG
# ==============================
$computer = $env:COMPUTERNAME
$logDir = "$env:USERPROFILE\Desktop\"

if (!(Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir | Out-Null
}

$logFile = "$logDir\Network_Diagnostic_Log_$computer.csv"
$script:lastResultText = ""
$script:cancelRequested = $false  

# ==============================
# FORM
# ==============================
$form = New-Object System.Windows.Forms.Form
$form.Text = "Network Diagnostic Tool"
$form.Size = New-Object System.Drawing.Size(880, 650)
$form.StartPosition = "CenterScreen"

# ==============================
# TARGET INPUT
# ==============================
$targetLabel = New-Object System.Windows.Forms.Label
$targetLabel.Text = "Target:"
$targetLabel.Location = New-Object System.Drawing.Point(20, 20)
$targetLabel.AutoSize = $true

$targetBox = New-Object System.Windows.Forms.TextBox
$targetBox.Location = New-Object System.Drawing.Point(110, 16)
$targetBox.Size = New-Object System.Drawing.Size(220, 20) 
$targetBox.Text = "google.com.au"

# ==============================
# BUTTONS
# ==============================
$runButton = New-Object System.Windows.Forms.Button
$runButton.Text = "Run Test"
$runButton.Size = New-Object System.Drawing.Size(120, 40)
$runButton.Location = New-Object System.Drawing.Point(350, 10)

$stopButton = New-Object System.Windows.Forms.Button
$stopButton.Text = "Stop Test"
$stopButton.Size = New-Object System.Drawing.Size(120, 40)
$stopButton.Location = New-Object System.Drawing.Point(480, 10)
$stopButton.Enabled = $false 

$copyButton = New-Object System.Windows.Forms.Button
$copyButton.Text = "Copy Results"
$copyButton.Size = New-Object System.Drawing.Size(120, 40)
$copyButton.Location = New-Object System.Drawing.Point(610, 10)

# ==============================
# STATUS + LIGHT
# ==============================
$status = New-Object System.Windows.Forms.Label
$status.Text = "Idle"
$status.Location = New-Object System.Drawing.Point(750, 22)
$status.AutoSize = $true

$light = New-Object System.Windows.Forms.Label
$light.Text = "●"
$light.Font = New-Object System.Drawing.Font("Arial", 28)
$light.ForeColor = "Gray"
$light.Location = New-Object System.Drawing.Point(820, 10)
$light.AutoSize = $true

# ==============================
# PROGRESS BAR
# ==============================
$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(20, 60)
$progress.Size = New-Object System.Drawing.Size(830, 18)
$progress.Minimum = 0
$progress.Maximum = 100

# ==============================
# OUTPUT BOX
# ==============================
$output = New-Object System.Windows.Forms.TextBox
$output.Multiline = $true
$output.ScrollBars = "Vertical"
$output.Font = New-Object System.Drawing.Font("Consolas", 10) 
$output.Location = New-Object System.Drawing.Point(20, 90)
$output.Size = New-Object System.Drawing.Size(830, 500)

# ==============================
# LIGHT CONTROL
# ==============================
function Set-Light($color) {
    switch ($color) {
        "Green"  { $light.ForeColor = "Green" }
        "Yellow" { $light.ForeColor = "Orange" }
        "Red"    { $light.ForeColor = "Red" }
        default  { $light.ForeColor = "Gray" }
    }
}

# ==============================
# COPY FUNCTION
# ==============================
function Copy-Results {
    if ($script:lastResultText) {
        try {
            $tempBox = New-Object System.Windows.Forms.TextBox
            $tempBox.Multiline = $true
            $tempBox.Text = $script:lastResultText
            $tempBox.SelectAll()
            $tempBox.Copy()
            $tempBox.Dispose()
            
            $status.Text = "Copied"
        }
        catch {
            $status.Text = "Copy Error"
        }
    }
}

# ==============================
# STOP FUNCTION
# ==============================
function Stop-NetworkTest {
    $script:cancelRequested = $true
    $status.Text = "Stopping..."
    $stopButton.Enabled = $false
}

# ==============================
# MAIN TEST
# ==============================
function Run-NetworkTest {
    $target = $targetBox.Text.Trim()

    if ([string]::IsNullOrWhiteSpace($target)) {
        [System.Windows.Forms.MessageBox]::Show("Please enter a valid target address before running the test.", "Target Required", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }

    $script:cancelRequested = $false
    $runButton.Enabled = $false
    $stopButton.Enabled = $true
    
    $status.Text = "Running..."
    $progress.Value = 10
    $output.Clear()
    Set-Light "Gray"
    $form.Refresh()

    $runId = [guid]::NewGuid().ToString()
    $timestamp = Get-Date
    $computer = $env:COMPUTERNAME

    # ==========================
    # DNS
    # ==========================
    $dnsResult = "Not resolved"
    try {
        $dns = [System.Net.Dns]::GetHostEntry($target)
        if ($dns.AddressList.Count -gt 0) {
            $dnsResult = $dns.AddressList[0].IPAddressToString
        }
    } catch {}

    # ==========================
    # PUBLIC IP
    # ==========================
    try {
        $publicIP = Invoke-RestMethod "https://api.ipify.org" -TimeoutSec 5
    } catch {
        $publicIP = "Unavailable"
    }

    # ==========================
    # ADAPTER 
    # ==========================
    $adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.HardwareInterface -eq $true } | Select-Object -First 1
    if (-not $adapter) {
        $adapter = Get-NetAdapter | Where-Object Status -eq "Up" | Select-Object -First 1
    }
    $interfaceName = if ($adapter) { $adapter.Name } else { "Unknown" }
    $linkSpeed = if ($adapter) { $adapter.LinkSpeed } else { "Unknown" }

    # ==========================
    # OS & UPTIME
    # ==========================
    $os = (Get-CimInstance Win32_OperatingSystem).Caption
    $bootTime = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    $uptimeSpan = (Get-Date) - $bootTime
    $uptime = "{0} Days, {1} Hours, {2} Mins" -f $uptimeSpan.Days, $uptimeSpan.Hours, $uptimeSpan.Minutes

    $progress.Value = 25

    # ==========================
    # RELIABLE PING TEST (PACED INTERFACE LOOP)
    # ==========================
    $sent = 50
    $actualSent = 0
    $pingResults = @()

    for ($i = 1; $i -le $sent; $i++) {
        if ($script:cancelRequested) {
            break
        }

        $actualSent++
        $ping = Test-Connection -ComputerName $target -Count 1 -ErrorAction SilentlyContinue
        if ($ping) { $pingResults += $ping }

        $progress.Value = 25 + [math]::Round(($i / $sent) * 30)
        [System.Windows.Forms.Application]::DoEvents() 

        if ($i -lt $sent -and -not $script:cancelRequested) {
            Start-Sleep -Milliseconds 200
        }
    }

    if ($actualSent -eq 0) { $actualSent = 1 }

    $received = $pingResults.Count
    $lost = $actualSent - $received
    $lossPercent = [math]::Round(($lost / $actualSent) * 100, 0)

    $times = $pingResults | ForEach-Object { $_.ResponseTime }

    if ($times.Count -gt 0) {
        $min = ($times | Measure-Object -Minimum).Minimum
        $max = ($times | Measure-Object -Maximum).Maximum
        $avg = [math]::Round(($times | Measure-Object -Average).Average, 0)
    } else {
        $min = 0
        $max = 0
        $avg = 0
    }

    $jitter = if ($times.Count -gt 1) { $max - $min } else { 0 }

    $progress.Value = 55

    # ==========================
    # METRICS
    # ==========================
    if ($lossPercent -eq 0) { $lossCategory="None" }
    elseif ($lossPercent -le 2) { $lossCategory="Low" }
    elseif ($lossPercent -le 10) { $lossCategory="Medium" }
    else { $lossCategory="High" }

    if ($avg -lt 30) { $latencyClass="Excellent" }
    elseif ($avg -lt 80) { $latencyClass="Good" }
    elseif ($avg -lt 150) { $latencyClass="Poor" }
    else { $latencyClass="Critical" }

    # ==========================
    # DIAGNOSIS
    # ==========================
    if ($script:cancelRequested) {
        $diagnosis = "Test aborted prematurely by user"
        Set-Light "Yellow"
    }
    elseif ($lossPercent -gt 5) {
        $diagnosis = "Packet loss detected"
        Set-Light "Red"
    }
    elseif ($avg -gt 100) {
        $diagnosis = "High latency"
        Set-Light "Yellow"
    }
    else {
        $diagnosis = "Healthy connection"
        Set-Light "Green"
    }

    $progress.Value = 80

    # ==========================
    # GENERATE INTEGRATED METRIC REPORT
    # ==========================
    $outputString = [System.Text.StringBuilder]::new()
    [void]$outputString.AppendLine("Diagnostic Report $(if ($script:cancelRequested) { '[PARTIAL RUN]' })")
    [void]$outputString.AppendLine("--------------------------------------------------")
    [void]$outputString.AppendLine("Run ID:          $runId")
    [void]$outputString.AppendLine("Time:            $timestamp")
    [void]$outputString.AppendLine("Computer:        $computer")
    [void]$outputString.AppendLine("Target:          $target")
    [void]$outputString.AppendLine("OS:              $os")
    [void]$outputString.AppendLine("Uptime:          $uptime`r`n")
    
    [void]$outputString.AppendLine("NETWORK UTILITIES:")
    [void]$outputString.AppendLine("DNS Resolution:  $dnsResult")
    [void]$outputString.AppendLine("Public IP:       $publicIP")
    [void]$outputString.AppendLine("Interface:       $interfaceName")
    [void]$outputString.AppendLine("Link Speed:      $linkSpeed`r`n")

    [void]$outputString.AppendLine("PING PERFORMANCE METRICS:")
    [void]$outputString.AppendLine("Pings Sent:      $actualSent")
    [void]$outputString.AppendLine("Pings Received:  $received")
    [void]$outputString.AppendLine("Loss Percent:    $lossPercent% ($lossCategory)")
    [void]$outputString.AppendLine("Avg Latency:     $avg ms ($latencyClass)")
    [void]$outputString.AppendLine("Min Latency:     $min ms")
    [void]$outputString.AppendLine("Max Latency:     $max ms")
    [void]$outputString.AppendLine("Jitter:          $jitter ms`r`n")

    [void]$outputString.AppendLine("DIAGNOSIS:")
    [void]$outputString.AppendLine($diagnosis)

    $output.Text = $outputString.ToString()
    $script:lastResultText = $outputString.ToString()

    # ==========================
    # CSV LOG
    # ==========================
    $schema = @(
        "RunId","Time","Computer","Target","OS","Uptime",
        "DNS","PublicIP","Interface","LinkSpeed",
        "LossPercent","LossCategory",
        "AvgLatency","MinLatency","MaxLatency",
        "Jitter","LatencyClass","Diagnosis"
    )

    $row = [PSCustomObject]([ordered]@{
        RunId=$runId
        Time=$timestamp
        Computer=$computer
        Target=$target
        OS=$os
        Uptime=$uptime
        DNS=$dnsResult
        PublicIP=$publicIP
        Interface=$interfaceName
        LinkSpeed=$linkSpeed
        LossPercent=$lossPercent
        LossCategory=$lossCategory
        AvgLatency=$avg
        MinLatency=$min
        MaxLatency=$max
        Jitter=$jitter
        LatencyClass=$latencyClass
        Diagnosis=$diagnosis
    })

    try {
        $row | Select-Object $schema | Export-Csv $logFile -NoTypeInformation -Encoding UTF8 -Append
    }
    catch {
        Start-Sleep -Milliseconds 500
        $row | Select-Object $schema | Export-Csv $logFile -NoTypeInformation -Encoding UTF8 -Append
    }

    $progress.Value = 100

    $runButton.Enabled = $true
    $stopButton.Enabled = $false

    if ($script:cancelRequested) {
        $status.Text = "Stopped"
        Set-Light "Yellow"
    } else {
        $status.Text = "Complete"
        if ($lossPercent -gt 5) { Set-Light "Red" }
        elseif ($avg -gt 100) { Set-Light "Yellow" }
        else { Set-Light "Green" }
    }
}

# ==============================
# EVENTS
# ==============================
$runButton.Add_Click({ Run-NetworkTest })
$stopButton.Add_Click({ Stop-NetworkTest })
$copyButton.Add_Click({ Copy-Results })

# ==============================
# INITIALIZE PRE-RUN DISPLAY
# ==============================
try {
    $initOs = (Get-CimInstance Win32_OperatingSystem).Caption
    $initBoot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    $initSpan = (Get-Date) - $initBoot
    $initUptime = "{0} Days, {1} Hours, {2} Mins" -f $initSpan.Days, $initSpan.Hours, $initSpan.Minutes
    
    $output.Text = "System Environment Initialized.`r`nComputer: $computer`r`nOS:       $initOs`r`nUptime:   $initUptime`r`n`r`nReady to analyze network targets..."
} catch {}

# ==============================
# UI BUILD
# ==============================
$form.Controls.Add($targetLabel)
$form.Controls.Add($targetBox)
$form.Controls.Add($runButton)
$form.Controls.Add($stopButton)
$form.Controls.Add($copyButton)
$form.Controls.Add($status)
$form.Controls.Add($light)
$form.Controls.Add($progress)
$form.Controls.Add($output)

[void]$form.ShowDialog()
