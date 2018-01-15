function main {
    # Format is like: 'traff-12-2017=5289:16351 6949:16870 ... 35834:7740 [269745:411982]'
    $usage = Get-Content -Path '.\traffdata.bak' -Encoding UTF8 | % {
        if ($_ -match '^traff-(?<month>\d+)-(?<year>\d+)=(?<usage>.+) \[(?<totalin>\d+):(?<totalout>\d+)\]') {
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
    } | 
        sort Date |
        # discard days with zero usage
    where Total -gt 0 |
        # discard first and last (assumes they are partial days)
    select -Skip 1 | select -SkipLast 1

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
main