[CmdletBinding()]
Param(
    [String] $version,
    [String] $adminUsername,
    [String] $adminPassword, #TODO: I got this from https://github.com/Azure/azure-devtestlab/blob/2a670c730def9fd63b0a7c6fda9301b473b04e92/Artifacts/windows-vsts-build-agent/vsts-agent-install.ps1, but it would be better to find an option with end-to-end-encryption
    [boolean] $enableBasicAuthentication=$false
)

function DownloadToFilePath ($downloadUrl, $targetFile)
{
    Write-Output ("Downloading installation files from URL: $downloadUrl to $targetFile")
    $targetFolder = Split-Path $targetFile

    if ((Test-Path -path $targetFile))
    {
        Write-Output "Deleting old target file $targetFile"
        Remove-Item $targetFile -Force | Out-Null
    }

    if (-not (Test-Path -path $targetFolder))
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
            $WebClient.DownloadFile($downloadUrl, $targetFile)
            break
        }
        catch
        {
            Write-Output "Caught exception during download..."
            if ($_.Exception.InnerException)
            {
                Write-Output "InnerException: $($_.InnerException.Message)"
            }
            else
            {
                Write-Output "Exception: $($_.Exception.Message)"
            }
        }

    } while ($downloadAttempts -lt 5)

    if ($downloadAttempts -eq 5)
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
        if ($version.startsWith('2017'))
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

function ExecuteSql($sql)
{
    $cred = New-Object PSCredential($adminUsername, (ConvertTo-SecureString $adminPassword -Force -AsPlainText))
    return Invoke-Command -ComputerName . -HideComputerName -Credential $cred -ScriptBlock {param ($sql) invoke-sqlcmd -server . -Query $sql} -ArgumentList $sql
}

function GrantSysAdminRole([String] $accountName)
{
    $existingLogins = ExecuteSql -sql "SELECT Name, SysAdmin FROM sys.syslogins where name = '$accountName'"
    if (-not $existingLogins -or $existingLogins.Count -eq 0)
    {
        ExecuteSql -sql "CREATE LOGIN [$accountName] FROM WINDOWS; ALTER SERVER ROLE [SysAdmin] ADD MEMBER [$accountName];"
    }
    elseif ($existingLogins.SysAdmin -eq 0) 
    {
        ExecuteSql -sql "ALTER SERVER ROLE [SysAdmin] ADD MEMBER [$accountName];"
    }
}

function GrantBuiltInAccountsSysAdminPrivileges()
{
    foreach ($systemAccount in @("NT AUTHORITY\Network Service","NT AUTHORITY\Local Service","NT AUTHORITY\System"))
    {
        GrantSysAdminRole -accountName $systemAccount
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

    GrantBuiltInAccountsSysAdminPrivileges

    $tfsconfigToolPath = "$TfsToolsDir\tfsconfig.exe"
    
    Write-Output "On failure, logs will be saved at C:\ProgramData\Microsoft\Team Foundation\Server Configuration\Logs"

    # https://blogs.msdn.microsoft.com/devops/2012/10/12/unattended-installation-of-team-foundation-server-20122013/
    $argumentList = "unattend /create /type:STANDARD /unattendfile:$installationFolder\standard.ini $tfsUnattendInputs"
    ExecProcess -toolPath $tfsconfigToolPath -argumentList $argumentList
    
    $argumentList = "unattend /configure /unattendfile:$installationFolder\standard.ini /continue"
    ExecProcess -toolPath $tfsconfigToolPath -argumentList $argumentList
    
    Write-Output "Configured Team Foundation Server $version."
}

function EnableBasicAuthForTfs()
{
    if ((Get-WindowsFeature Web-Basic-Auth).InstallState -ne "Installed")
    {
        Write-Output "Basic Authentication feature for IIS is not installed. Installing it now."
        Install-WindowsFeature Web-Basic-Auth | Out-Null
    }

    Write-Output "Enabling basic authentication for Team Foundation Server site."
    Set-WebConfigurationProperty -Filter "/system.webServer/security/authentication/basicAuthentication" -Name "Enabled" -Value "True" -PSPath "IIS:`\" -Location "Team Foundation Server/tfs"
    Write-Output "Successfully enabled basic authentication."
}

# ============ this is our entry point ==================

if ($adminUsername -notmatch ".+\\.+") 
{
    Write-Error "Account name $adminUsername does not contain a domain. Domain is required for the name (in form '<domain>\<accountname>'), for local accounts use '.' (e.g. '.\vmuser')."
}

Write-Output "Installing Team Foundation Server $version"
$installationFolder = Join-path -path $env:ProgramData -childPath "DTLArt_TFS"

if ($version -eq '2015 Update 4.1' )
{
    $tfsInstallLog = Join-Path $installationFolder "TFSInstall.log"
    $argumentList = "/Quiet /Log $tfsInstallLog"
    $downloadUrl = 'https://go.microsoft.com/fwlink/?LinkId=844068'
    $TfsToolsDir = "C:\Program Files\Microsoft Team Foundation Server 14.0\Tools"
    $TfsWebConfigPath = "C:\Program Files\Microsoft Team Foundation Server 14.0\Application Tier\Web Services\web.config"
    $tfsUnattendInputs = "/inputs:StartTrial=false;IsServiceAccountBuiltIn=True;UseReporting=False;UseWss=False"
}
elseif ($version -eq '2017 Update 3') {
    $tfsInstallLog = Join-Path $installationFolder "TFSInstall.log"
    $argumentList = "/Quiet /Log $tfsInstallLog"
    $downloadUrl = 'https://go.microsoft.com/fwlink/?LinkId=857134' 
    $TfsToolsDir = "C:\Program Files\Microsoft Team Foundation Server 15.0\Tools"
    $TfsWebConfigPath = "C:\Program Files\Microsoft Team Foundation Server 15.0\Application Tier\Web Services\web.config"
    $tfsUnattendInputs = "/inputs:StartTrial=false;IsServiceAccountBuiltIn=True;UseReporting=False;UseWss=False"
}
elseif ($version -eq '2018 Update 3.1') {
    $tfsInstallLog = Join-Path $installationFolder "TFSInstall.log"
    $argumentList = "/Quiet /Log $tfsInstallLog"
    $downloadUrl = 'https://go.microsoft.com/fwlink/?LinkId=2008534' 
    $TfsToolsDir = "C:\Program Files\Microsoft Team Foundation Server 2018\Tools"
    $TfsWebConfigPath = "C:\Program Files\Microsoft Team Foundation Server 2018\Application Tier\Web Services\web.config"
    $tfsUnattendInputs = "/inputs:StartTrial=false;IsServiceAccountBuiltIn=True;UseReporting=False"
}
else
{
    Write-Error "Version is not recognized - allowed values are '2015 Update 4.1', '2017 Update 3' and '2018 Update 3'. Specified value: $version"
}

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

if ($enableBasicAuthentication)
{
    EnableBasicAuthForTfs
}

Write-Output "Done."