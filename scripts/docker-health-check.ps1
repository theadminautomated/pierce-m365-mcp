param(
    [string]$Url = 'http://localhost:3000/health'
)

try {
    $res = Invoke-RestMethod -UseBasicParsing -Uri $Url -TimeoutSec 5
    if ($res.status -eq 'ok') {
        exit 0
    }
    exit 1
} catch {
    exit 1
}
