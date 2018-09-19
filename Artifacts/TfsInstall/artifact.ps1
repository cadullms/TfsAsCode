Param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("2015")] 
    [string] $version
)

function DownloadToFilePath ($downloadUrl, $targetFile)
{
    Write-Output ("Downloading installation files from URL: $downloadUrl to $targetFile")
    $targetFolder = Split-Path $targetFile

    if((Test-Path -path $targetFile))
    {
        Write-Output "Deleting old target file $targetFile"
        Remove-Item $targetFile -Force | Out-Null
    }

    if(-not (Test-Path -path $targetFolder))
    {
        Write-Output "Creating folder $targetFolder"
        New-Item -ItemType Directory -Force -Path $targetFolder | Out-Null
    }

    #Download the file
    $downloadAttempts = 0
    do
    {
        $downloadAttempts++

        try
        {
            $WebClient = New-Object System.Net.WebClient
            $WebClient.DownloadFile($downloadUrl,$targetFile)
            break
        }
        catch
        {
            Write-Output "Caught exception during download..."
            if ($_.Exception.InnerException){
                Write-Output "InnerException: $($_.InnerException.Message)"
            }
            else {
                Write-Output "Exception: $($_.Exception.Message)"
            }
        }

    } while ($downloadAttempts -lt 5)

    if($downloadAttempts -eq 5)
    {
        Write-Error "Download of $downloadUrl failed repeatedly. Giving up."
    }
}

function InstallTfs($installationFolder)
{
    $tfsInstallerPath = Join-Path $installationFolder 'tfsinstaller.exe'
    DownloadToFilePath $downloadUrl $tfsInstallerPath

    Write-Output "Running install with the following arguments: $argumentList"
    $retCode = Start-Process -FilePath $tfsInstallerPath -ArgumentList $argumentList -Wait -PassThru

    if ($retCode.ExitCode -ne 0 -and $retCode.ExitCode -ne 3010)
    {
        if($version -eq '2017')
        {
            $targetLogs = 'c:\VS2017Logs'
            New-Item -ItemType Directory -Force -Path $targetLogs | Out-Null
            Write-Output ('Temp location is ' + $env:TEMP)
            Copy-Item -path $env:TEMP\dd* -Destination $targetLogs
        }

        Write-Error "Product installation of $tfsInstallerPath failed with exit code: $($retCode.ExitCode.ToString())"    
    }
    else
    {
        Write-Output "Team Foundation Server install succeeded."
    }
}

function ExecProcess($toolPath, $argumentList)
{
    Write-Output "Starting this command: $toolPath $argumentList"
    $retCode = Start-Process -FilePath $toolPath -ArgumentList $argumentList -Wait -PassThru
    if ($retCode.ExitCode -ne 0 -and $retCode.ExitCode -ne 3010) 
    {
        Write-Error "Tool failed. Exit code: $($retCode.ExitCode). Command was: $toolPath $argumentList"
    }
}

function ConfigureTfs ($TfsToolsDir, $installationFolder)
{
    Write-Output "Configuring Team Foundation Server $version"
    # https://blogs.msdn.microsoft.com/devops/2012/10/12/unattended-installation-of-team-foundation-server-20122013/
    # https://docs.microsoft.com/en-us/vsts/tfs-server/command-line/tfsconfig-cmd#identities
    
    $tfsconfigToolPath = "$TfsToolsDir\tfsconfig.exe"
    
    $argumentList = "unattend /create /type:STANDARD /unattendfile:$installationFolder\standard.ini /inputs:StartTrial=false;IsServiceAccountBuiltIn=True;UseReporting=False;UseWss=False"
    ExecProcess -toolPath $tfsconfigToolPath -argumentList $argumentList
    
    $argumentList = "unattend /configure /unattendfile:$installationFolder\standard.ini /continue"
    ExecProcess -toolPath $tfsconfigToolPath -argumentList $argumentList
    
    Write-Output "Configured Team Foundation Server $version."
    
}

# ============ this is our entry point ==================

Write-Output "Installing Team Foundation Server $version"
$installationFolder = Join-path -path $env:ProgramData -childPath "DTLArt_TFS"

if($version -eq '2015' )
{
    $tfsInstallLog = Join-Path $installationFolder "TFSInstall.log"
    $argumentList = "/Quiet /Log $tfsInstallLog"
    $downloadUrl = 'https://download.my.visualstudio.com/db/en_team_foundation_server_express_2015_update_4_x86_x64_web_installer_11701809.exe?t=04011165-51a9-407e-ac68-462d80685ed2&e=1537400301&h=0715ecd3ddbd2c2fdd5162a2fbc8f2f6&su=1'
}
else
{
    Write-Error "Version is not recognized - allowed value is 2015. Specified value: $version"
}

# TODO: Find these paths dynamically with 
# (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\TeamFoundationServer\14.0" -Name "InstallPath").InstallPath
$TfsToolsDir = "C:\Program Files\Microsoft Team Foundation Server 14.0\Tools"
$TfsWebConfigPath = "C:\Program Files\Microsoft Team Foundation Server 14.0\Application Tier\Web Services\web.config"

if (Test-Path $TfsToolsDir)    
{
    Write-Output "Team Foundation Server already installed (found $TfsToolsDir)."
}
else
{
    InstallTfs -InstallationFolder $installationFolder 
}

if (Test-Path $TfsWebConfigPath)
{
    Write-Output "Team Foundation Server already configured (found $TfsWebConfigPath)."
}
else
{
    ConfigureTfs -TfsToolsDir $TfsToolsDir -installationFolder $installationFolder
}