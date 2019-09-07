properties {
    $ProjectRoot = $ENV:BHProjectPath
    if(-not $ProjectRoot) {
        $ProjectRoot = $PSScriptRoot
    }
    $ModulePath = $ENV:BHModulePath
    $Tests = "$ProjectRoot\Tests"
    Get-BuildEnvironment
    $OutputDir = $ENV:BHBuildOutput
    $OutputModDir = Join-Path -Path $OutputDir -ChildPath $ENV:BHProjectName
    $Manifest = Import-PowerShellDataFile -Path $ENV:BHPSModuleManifest
}
task default -depends Test

task Init {
    "`nSTATUS: Testing with PowerShell $psVersion"
    "Build System Details:"
    Get-Item ENV:BH*
    "`n"
} -description 'Initialize build environment'

task Analyze -Depends Compile {
    $analysis = Invoke-ScriptAnalyzer -Path $outputModDir -Verbose:$false
    $errors = $analysis | Where-Object {$_.Severity -eq 'Error'}
    $warnings = $analysis | Where-Object {$_.Severity -eq 'Warning'}
    if (($errors.Count -eq 0) -and ($warnings.Count -eq 0)) {
        '    PSScriptAnalyzer passed without errors or warnings'
    }
    if (@($errors).Count -gt 0) {
        Write-Error -Message 'One or more Script Analyzer errors were found. Build cannot continue!'
        $errors | Format-Table
    }
    if (@($warnings).Count -gt 0) {
        Write-Warning -Message 'One or more Script Analyzer warnings were found. These should be corrected.'
        $warnings | Format-Table
    }
} -description 'Run PSScriptAnalyzer'

task Clean -depends Init {
    Remove-Module -Name $env:BHProjectName -Force -ErrorAction SilentlyContinue
    if (Test-Path -Path $outputDir) {
        Get-ChildItem -Path $outputDir -Recurse | Remove-Item -Force -Recurse
    } else {
        New-Item -Path $outputDir -ItemType Directory > $null
    }
    "    Cleaned previous output directory [$ou -ver    tputDir]"
} -description 'Cleans module output directory'

task Compile -depends Clean {
    New-Item -Path $OutputModDir -ItemType Directory > $null
    # Append items to psm1
    Write-Verbose -Message 'Creating psm1...'
    $psm1 = Copy-Item -Path (Join-Path -Path $ModulePath -ChildPath "$($ENV:BHProjectName).psm1") -Destination (Join-Path -Path $OutputModDir -ChildPath "$($ENV:BHProjectName).psm1") -PassThru
    Get-ChildItem -Path (Join-Path -Path $ModulePath -ChildPath 'Private') -Recurse |
        Get-Content -Raw | Add-Content -Path $psm1 -Encoding UTF8
    Get-ChildItem -Path (Join-Path -Path $ModulePath -ChildPath 'Public') -Recurse |
        Get-Content -Raw | Add-Content -Path $psm1 -Encoding UTF8
    Copy-Item -Path $env:BHPSModuleManifest -Destination $OutputModDir
    "    Created compiled module at [$OutputModDir]"
} -description 'Compiles module from source'

task Build -depends Compile {
    $OutputModDirDataFile = Join-Path -Path $OutputModDir -ChildPath "$($ENV:BHProjectName).psd1"
    Write-Verbose -Message 'Adding exported functions to psd1...'
    Push-Location -Path $OutputDir

    Write-Host "`$BuildDetails.ProjectPath is `"$($BuildDetails.ProjectPath)`"." -ForegroundColor Magenta
    Write-Host "Get-ProjectName is `"$(Get-ProjectName)`"." -ForegroundColor Cyan
    Write-Host "pwd is `"$(Get-Location)`"." -ForegroundColor Green
    #$fuu = Join-Path ($BuildDetails.ProjectPath) (Get-ProjectName)
    #Write-Host "`$fuu is  `"$fuu`"" -ForegroundColor Yellow
    #$Name = Join-Path ($BuildDetails.ProjectPath) (Get-ProjectName)
    write-host $name -ForegroundColor DarkBlue

    Set-ModuleFunction
    Pop-Location
    "    Exported public functions added to output data file at [$OutputModDirDataFile]"
} -description 'Adds exported functions to psd1'

task Test -Depends Init, Analyze, Pester -description 'Run test suite'

task Pester -Depends Build {
    Push-Location
    Set-Location -PassThru $outputModDir
    if (-not $ENV:BHProjectPath) {
        Set-BuildEnvironment -Path $PSScriptRoot\..
    }

    $origModulePath = $env:PSModulePath
    if ( $env:PSModulePath.split($pathSeperator) -notcontains $outputDir ) {
        $env:PSModulePath = ($outputDir + $pathSeperator + $origModulePath)
    }

    Remove-Module $ENV:BHProjectName -ErrorAction SilentlyContinue -Verbose:$false
    Import-Module -Name $outputModDir -Force -Verbose:$false
    $testResultsXml = Join-Path -Path $outputDir -ChildPath 'testResults.xml'
    $testResults = Invoke-Pester -Path $tests -PassThru -OutputFile $testResultsXml -OutputFormat NUnitXml

    if ($testResults.FailedCount -gt 0) {
        $testResults | Format-List
        Write-Error -Message 'One or more Pester tests failed. Build cannot continue!'
    }
    Pop-Location
    $env:PSModulePath = $origModulePath
} -description 'Run Pester tests'
