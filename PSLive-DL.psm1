#Requires -Version 5
function Invoke-PSLiveWatchdog {
    [CmdletBinding()]
    param (
        [int]
        $Interval
    )
    
    begin {
        
    }
    
    process {
        
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
        $Format = 'mp4'
    )
    
    begin {
        $streamAvailable = Get-StreamAvailability -Url $Url
        if ($null -ne $streamAvailable.ExternalError) {
            throw [System.InvalidOperationException]::new($streamAvailable.ExternalError)
        }
        if (-not $streamAvailable.IsOnline) {
            throw [System.InvalidOperationException]::new("Stream is not online; $($streamAvailable.Error)")
        }
    }
    
    process {
        $job = Start-Job -ScriptBlock {
            Invoke-Streamlink -Url $args[0] -Format $args[1]
        } -ArgumentList $Url, $Format -InitializationScript { Import-Module PSLive-DL.psm1 }
        while ($job.State -eq "Running") {
            Write-Progress -Activity "Recording livestream for $url..." -PercentComplete (Get-Random -Minimum 0 -Maximum 100)
            Start-Sleep -Seconds 2
        }
    }
    
    end {
        
    }
}

function Get-StreamAvailability($Url) {
    $returnResponse = [PSCustomObject]@{
        IsOnline      = $false
        ExternalError = $null
        Error         = $null
        Streams       = $null
    }
    $response = Invoke-Streamlink -Url $Url -Json
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
    return $returnResponse
}
function Test-IsFilenameValid($Filename) {
    if ($null -eq $null) {
        return $false
    }
    $invalids = [System.IO.Path]::GetInvalidFileNameChars() + [System.IO.Path]::GetInvalidPathChars()
    foreach ($invalid in $invalids) {
        if ($Filename.Contains($invalid)) {
            return $false
        }
    }
    return $true
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
        $Format = "mp4"
    )
    
    begin {
        $sl = Get-Streamlink
    }
    
    process {
        $psi = [System.Diagnostics.ProcessStartInfo]::new($sl)
        $psi.RedirectStandardError = $true
        $psi.RedirectStandardOutput = $true
        if ($null -ne $ArgumentList -and $ArgumentList.Length -gt 0) {
            $psi.ArgumentList = $ArgumentList
        }
        $psi.Arguments += " $(Get-CommonArgs)"
        $psi.Arguments += " --url $Url"
        if ($Json) {
            $psi.Arguments += " --json"
        }
        if (-not $OutputName) {
            $OutputName = [System.DateTimeOffset]::UtcNow.ToString("yyyy-MM-dd_HH.mm.ss-") + [System.IO.Path]::GetFileName($Url)
        }
        $psi.Arguments += " --output $OutputName." + $Format
        if ($Format) {
            $psi.Arguments += " --ffmpeg-fout $Format"
        }
        $p = [System.Diagnostics.Process]::new()
        $p.StartInfo = $psi
        $p.Start() > $null
        $stdout = $p.StandardOutput.ReadToEnd()
        $stderr = $p.StandardError.ReadToEnd()
        $p.WaitForExit()
    }
    
    end {
        return [PSCustomObject]@{
            StandardOutput = $stdout
            StandardError  = $stderr
        }
    }
}
function Get-CommonArgs {
    $ffmpeg = Get-FFMpeg
    return "--ffmpeg-ffmpeg", "`"$ffmpeg`"", "--http-timeout", 5, "--stream-timeout", 5, "--http-stream-timeout", 5
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
Export-ModuleMember -Function New-PSLiveRecording, Get-StreamAvailability