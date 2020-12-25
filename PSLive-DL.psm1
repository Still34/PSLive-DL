#Requires -Version 5
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
        Write-Verbose $result.StandardOutput
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
        $OutputName,
        [Parameter(ParameterSetName = "Record")]
        [ValidateSet('mkv', 'mp4')]
        [string]
        $Format = "mp4",
        [ValidateScript( { return Test-Path $_ })]
        [string]
        $CookieJar
    )
    
    begin {
        $sl = Get-Streamlink
    }
    
    process {
        $psi = [System.Diagnostics.ProcessStartInfo]::new($sl)
        $psi.RedirectStandardError = $true
        $psi.RedirectStandardOutput = $true
        $psi.Arguments += (Get-CommonArgs)
        $psi.Arguments += " --url $Url"
        if ($Json) {
            $psi.Arguments += " --json"
        }
        else {
            if (-not $OutputName) {
                $OutputName = [System.DateTimeOffset]::Now.ToString("yyyy-MM-dd_HH.mm.ss-") + [System.IO.Path]::GetFileName($Url)
            }
            $OutputName = Repair-Filename $OutputName
            $psi.Arguments += " --output $OutputName." + $Format
            if ($Format) {
                $psi.Arguments += " --ffmpeg-fout $Format"
            }
        }
        if ($CookieJar) {
            $cookieArgs = Convert-CookieJarToArgs $CookieJar
            $psi.Arguments += " $($cookieArgs)"
        }
        $p = [System.Diagnostics.Process]::new()
        $p.StartInfo = $psi
        $p.Start() > $null
        if ($Json) {
            $stdout = $p.StandardOutput.ReadToEnd()
            $stderr = $p.StandardError.ReadToEnd()
            $p.WaitForExit()
        }
        else {
            $activity = "Recording $url since $([DateTime]::Now)..."
            $i = 0
            while (!$p.HasExited) {
                if ($i -ge 100) {
                    $i = 0
                }
                $i++
                Write-Progress -Activity $activity -Status "Recording..." -PercentComplete $i
                Start-Sleep -Seconds 2
            }
            Write-Progress -Activity $activity -Completed
            $stdout = $p.StandardOutput.ReadToEnd()
            $stderr = $p.StandardError.ReadToEnd()
        }
    }
    
    end {
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
    return "--ffmpeg-ffmpeg", "`"$ffmpeg`"", "--http-timeout", 5, "--stream-timeout", 5, "--http-stream-timeout", 5, "--default-stream", "best", "--force"
}
function Get-FFMpeg {
    $sl = Get-Command ffmpeg -ErrorAction SilentlyContinue -CommandType Application
    if ($null -eq $sl) {
        throw [System.IO.FileNotFoundException]::new("ffmpeg is not available. Please ensure ffmpeg has already been downloaded and configured.")
    }
    else {
        return $sl.Source
    }
}

function Get-Streamlink {
    $sl = Get-Command streamlink -ErrorAction SilentlyContinue -CommandType Application
    if ($null -eq $sl) {
        throw [System.IO.FileNotFoundException]::new("Streamlink is not available. Please ensure streamlink has already been downloaded and configured.")
    }
    else {
        return $sl.Source
    }
}
Export-ModuleMember -Function New-PSLiveRecording, Get-StreamAvailability, Invoke-Streamlink, Invoke-PSLiveWatchdog