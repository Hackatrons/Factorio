# location to install the server to
$RootFolder = "D:\docker\factorio"

$ServerPath = Join-Path -Path $RootFolder -ChildPath "server"
$TmpPath = Join-Path -Path $RootFolder -ChildPath "installtmp"

# ports for the server host
$ServerTcpPort = 27015
$ServerUdpPort = 34197

function Refresh-PathEnv {
	$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
}

function Install-Dependencies {
    # install chocolately if not already installed
    $chocoInstalled = Get-Command choco.exe -ErrorAction SilentlyContinue

    if (!$chocoInstalled) {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
    }

    Refresh-PathEnv

    # install docker via chocolately
    choco install docker-cli -y
    choco install docker-desktop -y
    choco install nuget.commandline

    Touch-Folder $TmpPath

    Refresh-PathEnv

    # download the open.nat library
    nuget install "Open.Nat" -OutputDirectory $TmpPath
}

function Uninstall-FactorioServer {
    $image = docker ps -a | sls factoriotools/factorio

    if ($image -eq $null) {
        return
    }

    # remove the old instance
    docker stop factorio
    docker rm factorio
    docker rmi factoriotools/factorio
}

function Install-FactorioServer {
    # create the server folder (and implicitly the parent folders) if it doesn't already exist
    Touch-Folder $ServerPath

    # start the container
    # note that the internal ports are hard coded as the factorio defaults, but the external ports are configurable
    $cmd = "docker run -d -p 34197:${ServerUdpPort}/udp -p 27015:${ServerTcpPort}/tcp -v ${ServerPath}:/factorio --name factorio --restart=always factoriotools/factorio:stable"
    iex $cmd
}

function Open-Ports {
    try {
        # attempt to open the required ports on the router using upnp
        Add-Type -Path $TmpPath\Open.NAT.*\lib\net45\Open.Nat.dll

        $discoverer = new-object Open.Nat.NatDiscoverer
        $devices = $discoverer.DiscoverDeviceAsync() | Await-Task

        $tcpPortMapping = new-object Open.Nat.Mapping("Tcp", $ServerTcpPort, $ServerTcpPort, "Factorio Server TCP")
        $udpPortMapping = new-object Open.Nat.Mapping("Udp", $ServerUdpPort, $ServerUdpPort, "Factorio Server UDP")

        $devices.CreatePortMapAsync($tcpPortMapping) | Await-Task | Out-Null
        $devices.CreatePortMapAsync($udpPortMapping) | Await-Task | Out-Null
    }
    catch [Open.Nat.NatDeviceNotFoundException] {
        Write-Error "Unable to open ports, please manually add the port mappings on your router"
    }
}

function Await-Task {
    param (
        [Parameter(ValueFromPipeline=$true, Mandatory=$true)]
        $task
    )

    process {
        while (-not $task.AsyncWaitHandle.WaitOne(200)) { }
        $task.GetAwaiter().GetResult()
    }
}

function Touch-Folder {
    param ($path)

    if (!(Test-Path $path))
    {
        New-Item -ItemType Directory -Path $path | Out-Null
    }
}

function Write-Step {
    param ($message)

    Write-Host -ForegroundColor Green $message
}

function Main {
    Write-Step "Installing dependencies..."
    Install-Dependencies

    Write-Step "Uninstalling previous factorio server..."
    Uninstall-FactorioServer

    Write-Step "Installing factorio server..."
    Install-FactorioServer

    Write-Step "Attempting to open the required router ports..."
    Open-Ports

    Write-Step "Done, press enter to exit."
    Read-Host
}

# elevate to admin powershell
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    Write-Step "Attempting to elevate to an admin session (required for docker install)"
    $arguments = "& '" +$myinvocation.mycommand.definition + "'"
    Start-Process powershell -Verb runAs -ArgumentList $arguments
    Break
}

Main
