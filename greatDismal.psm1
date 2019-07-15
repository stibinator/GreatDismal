function greatDismal{
    param (
    [string[]]$adjectives = @(),
    [string[]]$nouns = @(),
    [string]$dismalFolder = (join-path $env:APPDATA "\great dismal\"),
    [string]$logfile = (join-path $dismalFolder "log.txt"),
    [switch]$showpic,
    [switch]$showLog,
    [switch]$noLog,
    [switch]$install,
    [switch]$uninstall,
    [switch]$checkForUpdates
    )
    
    write-host "logfile at $logfile"
    $thisVersion = "0.1.0";
    $lastUpdate = $false;
    $shouldUpdate = $false;
    if (test-path $logfile){
        (Get-Content $logfile)|Where-Object{$_ -match "([^-]*)->\s*UpdateCheck"}|ForEach-Object{$lastUpdate = $Matches[1]}
        if ($lastUpdate){
            # check every week, future versions might slow this down a bit
            $shouldUpdate = (get-date $Matches[1]) -lt ((get-date).AddDays(-7))
        } else {
            $shouldUpdate = $true;
        }
    } 
    if ($shouldUpdate) {
        checkForUpdates -version $thisVersion -logfile $logfile;
    }

    # do the stuffs
    # installation hoo-hah
    if (! (test-path $dismalFolder)){mkdir $dismalFolder}
    $dismalPic = Join-Path $dismalFolder "greatDismal.jpg"
    
    if ($install){ 
        install-GD -scriptPath $scriptPath -logfile $logfile -nolog $nolog
    } 
    
    if ($showpic) {
        #user wants to see the current pic
        Invoke-Item $dismalPic
    } elseif ($showLog){
        #user wants to see the log
        Get-Content $logfile
    } elseif ($uninstall){
        #user wants to see the log
        uninstall -logfile $logfile -dismalFolder $dismalFolder -scriptPath (join-path $scriptPath  "greatDismal.ps1");
    }else {
        #get the pic and set the screen
        get-picFortheDay -logFile $logfile -nolog $nolog -dismalPic $dismalPic -scriptPath $scriptPath;
    }
}

function get-picFortheDay {
    param (
    [string[]]$adjectives = @(),
    [string[]]$nouns = @(),
    [string]$dismalPic,
    [string]$scriptPath,
    [string]$logfile,
    [bool]$nolog
    )
    Write-Host "getting some fresh depair for you"
    
    $key = "48efbaf66f9bf4b1bf2d0b04c46b02b1"
    $scrt = "9f5ab5c8abc77684"
    if ($adjectives.Length -eq 0){
        $adjectives = @(
        "dull", "ugly", "boring",
        "depressing", "abandoned", "neglected",
        "broken", "dismal", "wrecked",
        "crumbling", "decaying", "rotting",
        "ruined", "brutalist", "gloomy", 
        "dreary", "trashed", "dumped", 
        "stained", "desolate", "miserable"
        );
    }
    if ($nouns.Length -eq 0){
        $nouns=@(
        "landscape", "trash", "rubbish",
        "ruin", "wasteland", "building",
        "streetscape", "junk", "office",
        "apartment block", "dumpster", 
        "cubicle", "freeway", "factory",
        "cell", "dump", "garbage",
        "swamp", "concrete", "bunker",
        "vomit", "grave", "tower", 
        "concrete", "rubble", "field", 
        "paddock", "road", "town", "bin", 
        "puddle", "spill", "despair"
        );
    }
    $attempts = 0;
    while ((! $photogURL) -and ($attempts -lt 64)){
        $picfortheday = @($adjectives[(Get-Random($adjectives.Length))], $nouns[(Get-Random($nouns.Length))]) -join ",";
        $result = Invoke-RestMethod -URi  ("http://api.flickr.com/services/rest/?method=flickr.photos.search&api_key={0}&secret={1}&tags={2}&tag_mode=all&sort=interestingness-desc&media=photos&format=rest&extras=url_k" -f $key, $scrt, $picfortheday) -Method Get
        $pics = $result.rsp.photos.photo;
        if ($pics.length -gt 0){
            log ("looking for pics of {0}, found {1}" -f ($picfortheday.replace(",", " and ")),  $pics.length) -logFile $logfile -nolog $nolog
            $randompics = 0;
            while (($null -eq $photogURL) -and ($randompics -lt $pics.length) ){
                $randoPhoto = Get-Random $pics.Length;
                $photogURL = $pics[$randoPhoto].url_k;
                $randompics++
            }
            if ($null -ne $photogURL){
                log ("found a photo at {0}" -f $photogURL) -logFile $logfile -nolog $nolog
            } else {
                log ("no url found. Trying another search") -logFile $logfile -nolog $nolog
            }
            $photoTitle = $pics[$randoPhoto].title;
        } else {
            log ("{0} - didn't find any pics of {1}" -f (get-date), ($picfortheday.replace(",",  " and "))) -logFile $logfile -nolog $nolog
        }
        $attempts++;
    }
    (New-Object Net.webclient).DownloadFile($photogURL, $dismalPic)
    log ("downloaded `"{0}`"" -f $photoTitle) -logFile $logfile -nolog $nolog
    
    Set-LockscreenWallpaper -LockScreenImageValue $dismalPic -logfile $logfile;
}

function checkForUpdates {
    param(
        [string]$Version,
        [string]$logfile
    )
    log -msg "UpdateCheck" -logfile $logfile
    $thisVersion = $Version.split(".");
    $url = "http://www.pureandapplied.com.au/greatdismalcurrentversion";
    $wc = New-Object System.Net.WebClient;
    $currentRelease = ($wc.DownloadString($url)).split(".");
    Write-Host ("current release {0}.{1}, This Version {2}.{3}" -f $currentRelease[0], $currentRelease[1], $thisVersion[0], $thisVersion[1])
    if (($currentRelease[0] -gt $thisVersion[0]) -or ($currentRelease[1] -gt $thisVersion[1])){
        # install the new version
        $newVersion = ("{0}_{1}.psm1" -f $url, $currentRelease)
        $newScript = $wc.DownloadFile($newVersion, $env:TEMP);
        Move-Item $newScript $MyInvocation.ScriptName
    }
}
function Set-LockscreenWallpaper {
    # this was adapted from
    # https://abcdeployment.wordpress.com/2017/04/20/how-to-set-custom-backgrounds-for-desktop-and-lockscreen-in-windows-10-creators-update-v1703-with-powershell/
    # The Script sets custom background Images for the Lock Screen by leveraging the new feature of PersonalizationCSP that is only available in 
    # the Windows 10 v1703 aka Creators Update and later build versions #
    # Applicable only for Windows 10 v1703 and later build versions #
    
    param(
    [string]$LockScreenImageValue,
    [string]$logfile
    )
    
    $RegKeyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"
    
    $LockScreenPath = "LockScreenImagePath"
    $LockScreenStatus = "LockScreenImageStatus"
    $LockScreenUrl = "LockScreenImageUrl"
    $StatusValue = "1"
    
    If (([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")){
        
        IF(!(Test-Path $RegKeyPath))
        
        {
            
            New-Item -Path $RegKeyPath -Force | Out-Null
            
            New-ItemProperty -Path $RegKeyPath -Name $LockScreenStatus -Value $StatusValue -PropertyType DWORD -Force | Out-Null
            New-ItemProperty -Path $RegKeyPath -Name $LockScreenPath -Value $LockScreenImageValue -PropertyType STRING -Force | Out-Null
            New-ItemProperty -Path $RegKeyPath -Name $LockScreenUrl -Value $LockScreenImageValue -PropertyType STRING -Force | Out-Null
            
        }
        
        ELSE {
            
            New-ItemProperty -Path $RegKeyPath -Name $LockScreenStatus -Value $value -PropertyType DWORD -Force | Out-Null
            New-ItemProperty -Path $RegKeyPath -Name $LockScreenPath -Value $LockScreenImageValue -PropertyType STRING -Force | Out-Null
            New-ItemProperty -Path $RegKeyPath -Name $LockScreenUrl -Value $LockScreenImageValue -PropertyType STRING -Force | Out-Null
        }
    } else {
        log ("Error: not running as Admin, can't set the registry.") -logFile $logfile -nolog $nolog
    }
}

function install-GD {
    param(
    [String]$logfile,
    [bool]$nolog,
    [bool]$phoneHome
    )
    # check to see if user is admin
    if (([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")){
        # is admin, we're good to install
        $scriptPath =  $MyInvocation.ScriptName
        $scriptName = (Get-Item $scriptPath).name;
        $divider = "`n" + ("-" * (Get-Host).ui.rawui.windowsize.width) + "`n"; # trick to make a row of dashes the width of the window
        write-host ($divider) -foregroundColor "yellow"
        Write-Host "This will install GreatDismal on your machine and it will download a random dismal login screen every time you log in" -ForegroundColor DarkYellow
        Write-Host "Note that the contents of the pictures are beyond the control of the developer, and may be " -NoNewline -ForegroundColor DarkYellow
        Write-Host "unsafe for work." -ForegroundColor DarkYellow -BackgroundColor DarkRed
        write-host ($divider) -foregroundColor "yellow"
        # if the script is not in the usual directory, copy it there
        $installDir = (join-path ($env:PSModulePath)[0] "GreatDismal")
        if (! ((split-path -parent $ScriptPath) -eq $installDir)){
            Write-Host $installDir;
            if (!(test-path $installDir)){mkdir $installDir}
            $installPath = join-path $installDir $scriptName;
            Copy-Item $scriptPath $installPath;
            $scriptPath = $installPath;
        }
        
        # define the workstation unlock as the trigger
        $stateChangeTrigger = Get-CimClass -Namespace ROOT\Microsoft\Windows\TaskScheduler -ClassName MSFT_TaskSessionStateChangeTrigger
        $trigger = New-CimInstance -CimClass $stateChangeTrigger -Property @{
            StateChange = 8  # TASK_SESSION_STATE_CHANGE_TYPE.TASK_SESSION_UNLOCK (taskschd.h)
        } -ClientOnly
        
        # Create a task scheduler event
        $argument = "-WindowStyle Hidden -command `"& '{0}'{1}`"" -f (join-path $scriptPath "greatDismal.ps1"), $(if ($phoneHome){" -checkForUpdates"} else {""});
        $action = New-ScheduledTaskAction -id "GreatDismal" -execute 'Powershell.exe' -Argument $argument
        $settings = New-ScheduledTaskSettingsSet -Hidden -StartWhenAvailable -RunOnlyIfNetworkAvailable
        Write-Host "for this script to work it needs elevated privileges" -BackgroundColor DarkBlue
        $Credential = Test-Credential
        if ($Credential){
            # actually install the shiz
            Write-Host "Username checks out." -ForegroundColor Green
            log "Unregistering existing scheduled task"
            Unregister-ScheduledTask -TaskName "greatDismal" -ErrorAction SilentlyContinue
            Register-ScheduledTask `
            -TaskName "greatDismal" `
            -User $Credential.username `
            -Action $action `
            -Settings $settings `
            -Trigger $trigger -RunLevel Highest `
            -Password $Credential.GetNetworkCredential().Password `
            -taskPath "\pureandapplied\"
        }
        if ($? -and (Get-ScheduledTask -TaskName "GreatDismal" -ErrorAction SilentlyContinue)){
            log "GreatDismal is installed" -colour "Green" -logFile $logfile -nolog $nolog
        } else {
            throw "Bollocks. Something went wrong. Computers suck."
        }
    }  else {
        # not admin
        Write-Host "You need run this script as an Admin to install it" -BackgroundColor Red -ForegroundColor Yellow
        throw "Computer says no."
    }
}

function uninstall {
    param(
    [string]$logfile,
    [string]$dismalFolder
    )
    if (([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")){
        $RegKeyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"
        remove-item -Path $RegKeyPath -Force -Recurse| Out-Null;
        Unregister-ScheduledTask -TaskName "greatDismal";
        Remove-Item  $dismalFolder -Recurse;
        $scriptPath = $MyInvocation.ScriptName;
        Remove-item $scriptPath
    } else {
        Write-host "you need to run this script as admin to uninstall it" -BackgroundColor Red -ForegroundColor Yellow
        throw "Computer says no."
    }
    
}
function Test-Credential {
    # check password, allowing multiple attemps
    $againWithThePassword = $true;
    $usernameChecksOut = $false;
    Add-Type -AssemblyName System.DirectoryServices.AccountManagement
    $DS = New-Object System.DirectoryServices.AccountManagement.PrincipalContext('machine',$env:COMPUTERNAME)
    
    while ((! $usernameChecksOut) -and $againWithThePassword){
        $Credential = Get-Credential
        if ($null -eq $Credential){
            Write-Warning "You didn't give me any Credentials. I can't help you if you won't help me."
            $againWithThePassword = ((read-host "Again with the password? Y/n").ToLower() -ne "n")
        } else {
            $usernameChecksOut = $DS.ValidateCredentials($Credential.UserName, $Credential.GetNetworkCredential().Password)
            if ($usernameChecksOut){
                return $Credential
            } else {
                Write-Warning "Username and / or password is incorrect. Soz.";
                $againWithThePassword = ((read-host "Again with the password? Y/n").ToLower() -eq "n")
            }
        }
        if (! $againWithThePassword){
            return $false
        }
        Start-Sleep 1
    }
}

function log {
    param (
    [string]$Msg,
    [string]$colour = "White",
    [string]$logfile, 
    [bool]$nolog
    )

    if ((-not $nolog) -and ($null -ne $logfile)){
        $date = Get-date -f "dd/MM/yyyy HH:mm:ss"
        if (! (test-path $logfile )){set-content $logfile "The Great Dismal Log"}
        if ((get-item $logfile).length -gt 64kb){
            $oldlog = (Get-Content $logfile)[-20..-1]
            Set-Content $logfile ("The Great Dismal Log`n" + $date + "-> " + "Trimmed log")
            Add-Content $logfile $oldlog
        }
        add-content $logfile ("" + $date + "-> " + $msg)
    }
    Write-Host $Msg -foregroundColor $colour
}
