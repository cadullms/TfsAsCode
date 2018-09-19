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

# ============ this is our entry point ==================

Write-Output "Installing Team Foundation Server $version"
$logFolder = Join-path -path $env:ProgramData -childPath "DTLArt_TFS"

if($version -eq '2015' )
{
    $tfsInstallLog = Join-Path $logFolder "TFSInstall.log"
    $argumentList = "/Quiet /Log $tfsInstallLog"
    $downloadUrl = 'https://download.my.visualstudio.com/db/en_team_foundation_server_express_2015_update_4_x86_x64_web_installer_11701809.exe?t=04011165-51a9-407e-ac68-462d80685ed2&e=1537400301&h=0715ecd3ddbd2c2fdd5162a2fbc8f2f6&su=1'
}
else
{
    Write-Error "Version is not recognized - allowed value is 2015. Specified value: $version"
}

$localFile = Join-Path $logFolder 'tfsinstaller.exe'
DownloadToFilePath $downloadUrl $localFile

Write-Output "Running install with the following arguments: $argumentList"
$retCode = Start-Process -FilePath $localFile -ArgumentList $argumentList -Wait -PassThru

if ($retCode.ExitCode -ne 0 -and $retCode.ExitCode -ne 3010)
{
    if($version -eq '2017')
    {
        $targetLogs = 'c:\VS2017Logs'
        New-Item -ItemType Directory -Force -Path $targetLogs | Out-Null
        Write-Output ('Temp location is ' + $env:TEMP)
        Copy-Item -path $env:TEMP\dd* -Destination $targetLogs
    }

    Write-Error "Product installation of $localFile failed with exit code: $($retCode.ExitCode.ToString())"    
}
else
{
    Write-Output "Team Foundation Server install succeeded."
}

Write-Output "Configuring Team Foundation Server $version"
# https://blogs.msdn.microsoft.com/devops/2012/10/12/unattended-installation-of-team-foundation-server-20122013/
# https://docs.microsoft.com/en-us/vsts/tfs-server/command-line/tfsconfig-cmd#identities

$tfsconfigPath = "$TfsToolsDir\tfsconfig.exe"
$TfsToolsDir = "C:\Program Files\Microsoft Team Foundation Server 14.0\Tools"

Write-Output "Starting tfsconfig unattend create with this command: $tfsconfigPath $argumentList"
$argumentList = "unattend /create /type:STANDARD /unattendfile:$logFolder\standard.ini /inputs:StartTrial=false;IsServiceAccountBuiltIn=True;UseReporting=False;UseWss=False"
$retCode = Start-Process -FilePath $tfsconfigPath -ArgumentList $argumentList -Wait -PassThru
if ($retCode.ExitCode -ne 0 -and $retCode.ExitCode -ne 3010) 
{
    throw "Team Foundation Server configuration failed. Exit code: $($retCode.ExitCode). Command was: $tfsconfigPath $argumentList"
}

Write-Output "Starting tfsconfig unattend configure with this command: $tfsconfigPath $argumentList"
$argumentList = "unattend /configure /unattendfile:$logFolder\standard.ini /continue"
$retCode = Start-Process -FilePath $tfsconfigPath -ArgumentList $argumentList -Wait -PassThru
if ($retCode.ExitCode -ne 0 -and $retCode.ExitCode -ne 3010) 
{
    throw "Team Foundation Server configuration failed. Exit code: $($retCode.ExitCode). Command was: $tfsconfigPath $argumentList"
}

Write-Output "Configured Team Foundation Server $version."

