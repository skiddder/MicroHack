$ErrorActionPreference = 'Stop'
$source = Join-Path (Split-Path $PSScriptRoot -Parent) 'lab'
$files = @(
    'k3s-master-setup.sh',
    'k3s-worker-setup.sh',
    'scripts\enable-winrm.ps1',
    'scripts\setup-wsl-tools.sh',
    'ansible\playbook-workstation.yml',
    'ansible\requirements.yml'
)
foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath (Join-Path $source $file) -PathType Leaf)) {
        throw "Cannot package missing fallback lab asset '$file'."
    }
}
$archivePath = Join-Path $PSScriptRoot 'lab-assets.zip'
$stream = [IO.File]::Open($archivePath, [IO.FileMode]::Create)
$archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in $files) {
        $entry = $archive.CreateEntry($file.Replace('\', '/'))
        $entry.LastWriteTime = [DateTimeOffset]::new(2020, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
        $entryStream = $entry.Open()
        try {
            $bytes = [IO.File]::ReadAllBytes((Join-Path $source $file))
            $entryStream.Write($bytes, 0, $bytes.Length)
        } finally {
            $entryStream.Dispose()
        }
    }
} finally {
    $archive.Dispose()
    $stream.Dispose()
}
Write-Host 'Packaged the unchanged fallback assets into lab-assets.zip.'
