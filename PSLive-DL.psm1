#Requires -Version 5
<#
.SYNOPSIS
    Initiates a watchdog to monitor the desired channel.
.DESCRIPTION
    Initiates a watchdog service to automatically detect whenever the desired channel goes live. When the channel is live, the function will automatically begin recording the stream; when the channel has stopped streaming, the function will return to its monitoring state, thus repeating the cycle.
.PARAMETER Url
    The channel to monitor (e.g., "twitch.tv/DarkViperAU", "https://www.youtube.com/c/dhctv", "https://www.youtube.com/watch?v=I2PF1SCi9qY")
.PARAMETER Interval
    The interval in seconds to repeat the monitoring process.
.PARAMETER Format
    The format to record the stream in.
.PARAMETER CookieJar
    The location to a cookies.txt file. This is required if the channel is locked behind a member pay-wall and that your account has access to said channel. The cookies.txt file must comply to the specs listed here: https://docs.funnelback.com/collections/collection-types/web/web-crawler-settings/cookies_txt.html. The cookies.txt must also each be delimited by a tab character ("\t"). Firefox users can use the extension here to easily generate a cookies.txt for use of this module: https://addons.mozilla.org/ja/firefox/addon/cookies-txt/
.OUTPUTS
    None
#>
function Invoke-PSLiveWatchdog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $Url,
        [int]
        $Interval = 60,
        [ValidateSet('mkv', 'mp4')]
        [string]
        $Format = 'mp4',
        [string]
        $CookieJar
    )
    
    begin {
        $activity = "Watching for stream $url online status..."
    }
    
    process {
        $i = 0
        while ($true) {
            while (!(Get-StreamAvailability -Url $Url -CookieJar $CookieJar).IsOnline) {
                if ($i -ge 100) {
                    $i = 0
                }
                $i++
                Write-Progress -Activity $activity -Status "Press CTRL+C to exit the watchdog." -PercentComplete $i
                Start-Sleep -Seconds $Interval
            }
            New-PSLiveRecording -Url $Url -Format $Format -SkipCheck -CookieJar $CookieJar
        }
    }
    
    end {
        
    }
}
function Update-EnvVars {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine) + ";" + [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::User) 
}
function Install-PSLiveDependencies {
    [CmdletBinding()]
    param (
        
    )
    
    begin {
        $installSL = Get-Streamlink -ErrorAction SilentlyContinue
        $installFFMPEG = Get-FFMpeg -ErrorAction SilentlyContinue
        $installSL = [string]::IsNullOrEmpty($installSL)
        Write-Verbose "Install streamlink: $installSL"
        $installFFMPEG = [string]::IsNullOrEmpty($installFFMPEG)
        Write-Verbose "Install ffmpeg: $installFFMPEG"
    }
    
    process {
        if (-not ($installSL -or $installFFMPEG)) {
            Write-Host "Dependencies met. No installation required."
            return
        }
        $activity = "Installing dependencies..."
        if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) {
            if ($installFFMPEG) {
                Write-Progress -Activity $activity -Status "Installing ffmpeg..." -PercentComplete 45
                if ($installSL) {
                    $title = 'Install ffmpeg?'
                    $message = 'ffmpeg is available as an optional install in the streamlink installer. If you do not plan on using ffmpeg outside of streamlink, you may skip this dependency.'
                    $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", 'Yes'
                    $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", 'No'
                    $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
                    $ffmpegPrompt = $host.ui.PromptForChoice($title, $message, $options, 0) 
                }
                if ($null -eq $ffmpegPrompt -or $ffmpegPrompt -eq 0) {
                    Deploy-FFMpeg
                }
                else {
                    Write-Warning "ffmpeg installation aborted."
                }
            }
            if ($installSL) {
                Write-Progress -Activity $activity -Status "Installing streamlink..." -PercentComplete 90
                Deploy-Streamlink
            }
        }
        else {
            Write-Error "Automatic dependency installation is only supported on Windows for now. Please install ffmpeg and streamlink separetely!"
        }
        Write-Progress -Activity $activity -Completed
    }
    
    end {
        Write-Host "Dependency setup complete!" -ForegroundColor Green
    }
}
function New-PSLiveBin {
    $targetPath = "$env:USERPROFILE\.pslive\bin"
    if ($targetPath) {
        return (Get-Item $targetPath)
    }
    $binPath = New-Item -ItemType Directory -Path $targetPath -Force
    $userEnvVars = [System.Environment]::GetEnvironmentVariable("PATH", [System.EnvironmentVariableTarget]::User)
    if ($userEnvVars -notcontains $binPath.FullName) {
        [System.Environment]::SetEnvironmentVariable("PATH", $userEnvVars + ";$binPath", [System.EnvironmentVariableTarget]::User)
        Update-EnvVars
    }
    return $binPath
}
function Deploy-Streamlink {
    $iwr = Invoke-WebRequest "https://api.github.com/repos/streamlink/streamlink/releases" -UseBasicParsing
    if ($iwr.StatusCode -eq 200) {
        $response = (($iwr).Content | ConvertFrom-Json) | 
        Select-Object -First 1 | 
        Select-Object -exp assets | 
        Where-Object { 
            $_.Name -match ".*\.exe"
        }
        if (($response | Measure-Object).Count -eq 1) {
            $fileName = [System.IO.Path]::GetFileName($response.browser_download_url)
            $slTempFile = Join-Path ([System.IO.Path]::GetTempPath()) $fileName
            Invoke-WebRequest -Uri $response.browser_download_url -OutFile $slTempFile -UseBasicParsing
            Start-Process $slTempFile -Wait
            Update-EnvVars
            Write-Host ("Installed " + (. streamlink --version) + "!") -ForegroundColor Green
        }
        else {
            throw [System.InvalidOperationException]::new("Failed to obtain the URL for streamlink.")
        }
    }
    else {
        throw [System.Net.WebException]::new("GitHub cannot be reached at the moment.")
    }
}
function Deploy-FFMpeg {
    $iwr = Invoke-WebRequest "https://api.github.com/repos/btbn/ffmpeg-builds/releases" -UseBasicParsing
    $binPath = New-PSLiveBin
    if ($iwr.StatusCode -eq 200) {
        $response = (($iwr).Content | ConvertFrom-Json) | 
        Select-Object -First 1 | 
        Select-Object -exp assets | 
        Where-Object { 
            $_.Name -match "n[\d]\.[\d]\.[\d]-.*-gpl.*shared.*\.zip"
        }
        if (($response | Measure-Object).Count -eq 1) {
            $ffmpegTempFile = Join-Path ([System.IO.Path]::GetTempPath()) "ffmpeg-temp.zip"
            Invoke-WebRequest -Uri $response.browser_download_url -OutFile $ffmpegTempFile -UseBasicParsing
            Expand-Archive $ffmpegTempFile -DestinationPath $binPath -Force
            Get-ChildItem -Path $binPath -Recurse -Filter "bin" | 
            Select-Object -first 1 | 
            Get-ChildItem | 
            ForEach-Object { 
                move-item -Path $_.FullName -Destination $binPath
            }
            $version = ((. (Join-Path $binPath "ffprobe.exe")  -v 0 -of json -show_program_version) | convertfrom-json).program_version.version
            Write-Host "Installed ffmpeg ($version) to $binPath!" -ForegroundColor Green 
        }
        else {
            throw [System.InvalidOperationException]::new("Failed to obtain the URL for nightly ffmpeg build.")
        }
    }
    else {
        throw [System.Net.WebException]::new("GitHub cannot be reached at the moment.")
    }
}
function New-PSLiveRecording {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $Url,
        [ValidateSet('mkv', 'mp4')]
        [string]
        $Format = 'mp4',
        [switch]
        $SkipCheck,
        [string]
        $CookieJar
    )
    
    begin {
        if (!$SkipCheck) {
            $activity = "Checking if the channel is live..."
            Write-Progress -Activity $activity -PercentComplete 25 
            $streamAvailable = Get-StreamAvailability -Url $Url -CookieJar $CookieJar
            Write-Progress -Activity $activity -Completed
            if ($null -ne $streamAvailable.ExternalError) {
                throw [System.InvalidOperationException]::new($streamAvailable.ExternalError)
            }
            if (-not $streamAvailable.IsOnline) {
                throw [System.InvalidOperationException]::new("Stream is not online; $($streamAvailable.Error)")
            }
        }
    }
    
    process {
        $result = Invoke-Streamlink -Url $Url -Format $Format -CookieJar $CookieJar
    }
    
    end {
        if ($result.StandardOutput) {
            Write-Verbose $result.StandardOutput
        }
    }
}
function Get-StreamAvailability {
    [CmdletBinding()]
    param (
        [string]
        $Url,
        [string]
        $CookieJar
    )
    
    begin {
        $returnResponse = [PSCustomObject]@{
            IsOnline      = $false
            ExternalError = $null
            Error         = $null
            Streams       = $null
        }
    }
    
    process {
        $response = Invoke-Streamlink -Url $Url -Json -CookieJar $CookieJar
        if ($response.StandardError) {
            $returnResponse.ExternalError = $response.StandardError
            return $returnResponse
        }

        $result = $response.StandardOutput | ConvertFrom-Json
        if ($result.error) {
            $returnResponse.Error = $result.error
        }
        else {
            $returnResponse.IsOnline = $true
            if ($result.streams) {
                $returnResponse.Streams = $result | Select-Object -exp Streams
            }
        }
        Write-Verbose $result
    }
    
    end {
        return $returnResponse
    }
}
function Repair-Filename($Filename) {
    return $Filename.Split([System.IO.Path]::GetInvalidFileNameChars()) -join '-'
}
function Invoke-Streamlink {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $Url,
        [switch]
        $Json,
        [Parameter(ParameterSetName = "Record")]
        [string]
        $OutputDirectory = "$env:USERPROFILE\.pslive\",
        [Parameter(ParameterSetName = "Record")]
        [string]
        $OutputName,
        [Parameter(ParameterSetName = "Record")]
        [ValidateSet('mkv', 'mp4')]
        [string]
        $Format = "mp4",
        [string]
        $CookieJar
    )
    
    begin {
        $sl = Get-Streamlink
        if ($null -eq $sl) {
            throw [System.IO.FileNotFoundException]::new("Streamlink not found. Please configure the required dependencies via Install-PSLiveDependencies.")
        }
        $OutputName = [System.IO.Path]::GetFileName($OutputName)
        if (!(Test-Path $OutputDirectory)) {
            $OutputDirectory = (New-Item -Path $OutputDirectory -ItemType Directory -Force).FullName
        }
    }
    
    process {
        $slArgs += Get-CommonArgs
        $slArgs += " --url $Url"
        if ($Json) {
            $slArgs += " --json"
            $psi = [System.Diagnostics.ProcessStartInfo]::new($sl)
            $psi.Arguments = $slArgs
            $psi.RedirectStandardError = $true
            $psi.RedirectStandardOutput = $true
            $p = [System.Diagnostics.Process]::new()
            $p.StartInfo = $psi
            $p.Start() > $null
            $stdout = $p.StandardOutput.ReadToEnd()
            $stderr = $p.StandardError.ReadToEnd()
            $p.WaitForExit()
        }
        else {
            # prepare output file
            if (-not $OutputName) {
                $OutputName = [System.DateTimeOffset]::Now.ToString("yyyy-MM-dd_HH.mm.ss-") + [System.IO.Path]::GetFileName($Url)
            }
            $OutputName = Repair-Filename $OutputName
            if ([string]::IsNullOrEmpty($OutputName)) {
                throw [InvalidOperationException]::new("Stream filename cannot be null or empty.")
            }
            $OutputName = "$OutputName.$Format"
            $outputPath = Join-Path $OutputDirectory $OutputName
            $slArgs += " --output `"$outputPath`""
            if ($Format) {
                $slArgs += " --ffmpeg-fout $Format"
            }

            # prepare CookieJar
            if (!([string]::IsNullOrEmpty($CookieJar))) {
                $cookieArgs = Convert-CookieJarToArgs $CookieJar
                $slArgs += " $($cookieArgs)"
            }
            
            $activity = "Recording $url since $([DateTime]::Now)..."
            Write-Progress -Activity $activity -Status "Close the newly created (minimized) Streamlink window to stop recording." -PercentComplete 45

            # A bit of a hack:
            #   Spawn a new window on purpose, so the stream output can be properly terminated by the user
            #   While we could capture CTRL+C, it is not wise to do so for long-running tasks, as we still have a remux job afterwards.
            Start-Process $sl -ArgumentList $slArgs -Wait -WindowStyle Minimized

            # Post-recording
            if (!(Test-Path $outputPath)) {
                throw [System.IO.FileNotFoundException]::new("Streamlink failed to create an expected output.")
            }
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($OutputName)
            $remuxedOutputPath = Join-Path $OutputDirectory "$baseName-final.$Format"
            Write-Progress -Activity $activity -Status "Remuxing..." -PercentComplete 90
            Start-Process -FilePath (Get-FFMpeg) -ArgumentList "-i", "`"$outputPath`"", "-c", "copy", "`"$remuxedOutputPath`"" -Wait -NoNewWindow
            Remove-Item $outputPath -Force
            Write-Host "Finished capture!" -ForegroundColor Green
        }
    }
    
    end {
        Write-Progress -Activity $activity -Completed
        return [PSCustomObject]@{
            StandardOutput = $stdout
            StandardError  = $stderr
        }
    }
}
function Convert-CookieJarToArgs($Path) {
    if (-not (Test-Path $Path)) {
        throw [FileNotFoundException]::new("$Path cannot be found; unable to parse the specified cookie jar.")
    }
    $cookieJarContent = Get-Content $Path -Raw
    $cookieJarContent = [regex]::Replace($cookieJarContent, '^#.*$', '', [System.Text.RegularExpressions.RegexOptions]::Multiline)
    $cookieJarContent = ("Domain`tTailmatch`tPath`tSecure`tExpires`tName`tValue`n" + $cookieJarContent) | ConvertFrom-Csv -Delimiter "`t"
    return ($cookieJarContent | ForEach-Object { "--http-cookie " + "`"" + $_.name + "=" + $_.value + "`"" }) -join " "
}
function Get-CommonArgs {
    $ffmpeg = Get-FFMpeg
    if ($null -eq $ffmpeg) {
        throw [System.IO.FileNotFoundException]::new("ffmpeg not found. Please configure the required dependencies via Install-PSLiveDependencies.")
    }
    return "--ffmpeg-ffmpeg", "`"$ffmpeg`"", "--http-timeout", 5, "--stream-timeout", 5, "--http-stream-timeout", 5, "--default-stream", "best", "--force"
}
function Get-FFMpeg {
    $sl = Get-Command ffmpeg -ErrorAction SilentlyContinue -CommandType Application | Select-Object -First 1
    if ($null -eq $sl) {
        if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) {
            $installReg = Get-ChildItem Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\ | Get-ItemProperty | Where-Object { $_.DisplayName -match "streamlink" }
            if ($installReg.InstallLocation) {
                $src = get-childitem -path $installreg.InstallLocation -filter ffmpeg.exe -recurse
                if ($src) {
                    return $src.FullName
                }
            }
        }
        return $null
    }
    else {
        return $sl.Source
    }
}

function Get-Streamlink {
    $sl = Get-Command streamlink -ErrorAction SilentlyContinue -CommandType Application | Select-Object -First 1
    if ($null -eq $sl) {
        return $null
    }
    else {
        return $sl.Source
    }
}