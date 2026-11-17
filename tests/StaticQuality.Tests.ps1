#Requires -Version 5.1
# Pester 5: static checks only. The scripts under test are NOT executed.
BeforeAll {
    $script:RepositoryRoot = Split-Path -Parent $PSScriptRoot
}
Describe 'PowerShell static quality checks' {
    It 'parses every ps1 without syntax errors' {
        $files = @(Get-ChildItem -LiteralPath $script:RepositoryRoot -Filter '*.ps1' -File -Recurse)
        $files.Count | Should -BeGreaterThan 0
        foreach ($file in $files) {
            $tokens = $null
            $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
            $errors | Should -BeNullOrEmpty -Because "PowerShell parser failed for $($file.FullName)"
        }
    }
    It 'does not contain common hard-coded token prefixes or PEM private keys' {
        foreach ($file in Get-ChildItem -LiteralPath $script:RepositoryRoot -Filter '*.ps1' -File -Recurse) {
            $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop
            $content | Should -Not -Match 'ghp_[A-Za-z0-9]{30,}'
            $content | Should -Not -Match 'AIza[0-9A-Za-z_-]{25,}'
            $content | Should -Not -Match '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'
        }
    }
}
