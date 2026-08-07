$ErrorActionPreference = "SilentlyContinue"

# Path to the Godot console executable used by the user
$godotExe = "C:\Users\LEONARDO\Documents\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe"

# Get all Godot processes running the QuanticNet project (excluding tests/headless lsp)
$runningInstances = Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot_v4.7.1-stable_win64%'" | Where-Object { 
    $_.CommandLine -match "--path C:\\Users\\LEONARDO\\Documents\\godot_quantic_net" -and 
    ($_.CommandLine -match "--client" -or $_.CommandLine -match "--server")
}

if ($runningInstances) {
    Write-Host "Instancias da demo detectadas. Encerrando..." -ForegroundColor Yellow
    foreach ($proc in $runningInstances) {
        Stop-Process -Id $proc.ProcessId -Force
    }
    Write-Host "Demo encerrada." -ForegroundColor Green
} else {
    Write-Host "Nenhuma instancia detectada. Iniciando Demo (1 Server, 2 Clients)..." -ForegroundColor Cyan
    
    # Define working directory
    $cwd = "C:\Users\LEONARDO\Documents\godot_quantic_net"

    # Start Server (Headless)
    # Start-Process -FilePath $godotExe -ArgumentList "--path $cwd --headless -- --server" -WorkingDirectory $cwd
    Start-Process -FilePath $godotExe -ArgumentList "--path $cwd -- --server" -WorkingDirectory $cwd
    
    # Start Client 1 (Normal)
    Start-Process -FilePath $godotExe -ArgumentList "--path $cwd -- --client" -WorkingDirectory $cwd
    
    # Start Client 2 (With Netem)
    # Start-Process -FilePath $godotExe -ArgumentList "--path $cwd -- --client --netem" -WorkingDirectory $cwd
    Start-Process -FilePath $godotExe -ArgumentList "--path $cwd -- --client" -WorkingDirectory $cwd
    
    Write-Host "Demo iniciada com sucesso! Para fechar as janelas, rode este script novamente." -ForegroundColor Green
}
