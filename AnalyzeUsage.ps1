[CmdletBinding(DefaultParameterSetName = 'Data')]
param (
    [System.Uri]$TrafficDataUrl = 'https://10.0.0.1/traffdata.bak',
    [System.Management.Automation.PSCredential]$Credential,
    [string]$OutTrafficDataFile,

    [parameter(ParameterSetName = 'Summary')]
    [switch]$Summary,

    [parameter(ParameterSetName = 'Csv')]
    [switch]$Csv,
    [parameter(ParameterSetName = 'Csv')]
    [string]$Delimiter = "`t",
    [parameter(ParameterSetName = 'Csv')]
    [switch]$NoTypeInformation,
    [parameter(ParameterSetName = 'Csv')]
    [switch]$NoHeader
)

function main {

    function getTrafficData {

        if (!$TrafficDataUrl.IsAbsoluteUri) {
            # Assume it is relative file path
            $script:TrafficDataUrl = [Uri](Resolve-Path -LiteralPath $TrafficDataUrl.OriginalString -ea Stop).ProviderPath 
        }

        if ($TrafficDataUrl.IsFile) {
            Get-Content -Path $TrafficDataUrl.LocalPath
            return
        }

        # Read traffic data from server.
        # Use curl.exe instead of Invoke-WebRequest because connection may be
        # insecure (https w/ incorrect certificate) which Invoke-WebRequest does
        # not allow.
        if (!(Get-Command 'curl.exe' -ea Ignore)) {
            $resp = Invoke-WebRequest -Uri $TrafficDataUrl -Credential $Credential
            if ($resp) {
                $resp.Content -split "`n"
            }
        }
        else {
            if (!$Credential) {
                $script:Credential = Get-Credential -Message $TrafficDataUrl -ea Stop
            }
            $cred = $Credential.GetNetworkCredential()
            $global:LASTEXITCODE = 0
            $source = curl.exe --url $TrafficDataUrl --user ($cred.Username + ':' + $cred.Password) --insecure --fail --silent --show-error *>&1
            if ($LASTEXITCODE -ne 0) {
                if (!$source) {
                    $source = "Failed to retrieve traffic data from server ($LASTEXITCODE)."
                }
                Write-Error "$source"
                return
            }
            $source
        }
    }

    function parseTrafficData {
        param(
            [parameter(ValueFromPipeline)]
            [string[]]$source
        )
        process {
            foreach ($line in $source) {
                if ($line -match '^traff-(?<month>\d+)-(?<year>\d+)=(?<usage>.+) \[(?<totalin>\d+):(?<totalout>\d+)\]') {
                    $start = (Get-Date -Year $Matches.year -Month $Matches.month -Day 1).Date
                    foreach ($v in $Matches.usage -split ' ') {
                        $i, $o = $v -split ':'
                        # convert units from MB to GB
                        $i = [long]$i * 1MB / 1GB
                        $o = [long]$o * 1MB / 1GB
                        [pscustomobject]@{
                            Date  = $start
                            In    = $i
                            Out   = $o
                            Total = $i + $o
                        }
                        $start = $start.AddDays(1)
                    }
                }
            }
        }
    }

    $source = getTrafficData
    if ($OutTrafficDataFile) {
        $source | Out-File -Path $OutTrafficDataFile -Encoding UTF8
    }

    # discard first and last (assumes they are partial days)
    # discard days with zero usage
    $usage = $source | parseTrafficData |
        Sort-Object Date |
        Select-Object -Skip 1 | Select-Object -SkipLast 1 |
        Where-Object Total -gt 0

    if ($Summary) {
        function median([array]$source, [string]$property) {
            $i = $source.Length / 2
            if ($source.Length % 2 -eq 1) {
                # Odd number of values. Return middle value
                $source[[math]::Floor($i)].$property
            }
            else {
                # Even number of values. Return average of 2 middle values
                ($source[$i - 1].$property + $source[$i].$property) / 2
            }
        }
    
        function measure1([array]$source, [string]$property) {
            $source | Measure-Object $property -Average -Maximum -Minimum -Sum |
                Add-Member 'Median' (median $source $property) -PassThru
        }

        function summarize([array]$usage) {
            $in = measure1 $usage 'In'
            $out = measure1 $usage 'Out'
            $total = measure1 $usage 'Total'
            'Range:   {1:d} thru {2:d} ({0} days):' -f $usage.Length, $usage[0].Date, $usage[-1].Date
            'Total:   {0:F1} ({1:F1} in, {2:F1} out)' -f $total.Sum, $in.Sum, $out.Sum
            'Average: {0:F1} ({1:F1} in, {2:F1} out)' -f $total.Average, $in.Average, $out.Average
            'Median:  {0:F1} ({1:F1} in, {2:F1} out)' -f $total.Median, $in.Median, $out.Median
            'Max:     {0:F1} ({1:F1} in, {2:F1} out)' -f $total.Maximum, $in.Maximum, $out.Maximum
            'Min:     {0:F1} ({1:F1} in, {2:F1} out)' -f $total.Minimum, $in.Minimum, $out.Minimum
        }

        foreach ($g in $usage | group { $_.Date.ToString('yyyy-MM') }) {
            '{0:MMMM yyyy}' -f $g.group[0].Date
            summarize $g.group
            ''
        }

        'Everything'
        summarize $usage
    }
    elseif ($Csv) {
        $usage | ConvertTo-Csv -Delimiter $Delimiter -NoTypeInformation:$NoTypeInformation |
            Select-Object -Skip (0 + $NoHeader.ToBool())
    }
    else {
        $usage
    }
}
main