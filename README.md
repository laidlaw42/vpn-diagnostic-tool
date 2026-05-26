# VPN Diagnostic Tool
Simple GUI tool that runs PowerShell network commands and outputs results.

## Build

- Download `vpn_diagnostic_gui.ps1`
- Run Powershell
- `cd` to the directory with `vpn_diagnostic_gui.ps1`
- Run the following commands:

```pwsh
Invoke-PS2EXE `
  -InputFile "vpn_diagnostic_gui.ps1" `
  -OutputFile "VPN Diagnostic Tool.exe" `
  -IconFile "vpn.ico" `
  -NoConsole `
  -STA `
  -Verbose
```

## Usage
- Enter the target address you want to test
- Press `Run Test`
- Results generate in the main window (can be copied) and a CSV (`Network_Diagnostic_Log_$computer.csv`) is generated on the user's Desktop
- Each subsequent test is stored on a new row in the CSV

## Requirements:
- Windows 10+

## Preview
<img width="864" height="611" alt="image" src="https://github.com/user-attachments/assets/f889bc41-dbd4-4a18-8f03-56228a0eb932" />
