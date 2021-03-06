[CmdletBinding()]
Param(
    [Parameter(Position=0, HelpMessage="Build Type (quick, full)")]
    [ValidateSet('quick', 'clean-all', 'full', 'v8', 'js1')]
    [string]$Target = "quick",
    [Parameter(HelpMessage="Configuration (debug, release)")]
    [string]$Configuration = "release",
    [Parameter(HelpMessage="Platform (x64, x86)")]
    [string]$Platform = "x64",
    [Parameter(HelpMessage="Assembly version number (x.y.z.0 where x.y.z is the semantic version)")]
    [string]$Version = "0.0.0.0",
    [Parameter(HelpMessage="Version of Visual Studio to use (2010, 2012, 2013, Windows7.1SDK)")]
    [string]$SpecificVisualStudioVersion = "",
    [Parameter(HelpMessage="True to force network use when connectivity not detected")]
    [bool]$ForceNetwork = $false,
    [Parameter(HelpMessage="Defined symbols to pass to MsBuild")]
    [string]$Defines = ""
)

#Configuration
$productName = "Event Store Open Source"
$companyName = "Event Store LLP"
$copyright = "Copyright 2012 Event Store LLP. All rights reserved."

#Dependency Repositories and Directories
$baseDirectory = Resolve-Path .
$srcDirectory = Join-Path $baseDirectory (Join-Path "src" "EventStore")
$libsDirectory = Join-Path $srcDirectory "libs"

    #Event Store
    $eventStoreSolution = Join-Path $srcDirectory "EventStore.sln"

    #JS1
    $js1Project = Join-Path $srcDirectory (Join-Path "EventStore.Projections.v8Integration" "EventStore.Projections.v8Integration.vcxproj")
    $js1VersionResource = Join-Path $srcDirectory (Join-Path "EventStore.Projections.v8Integration" "EventStore.Projections.v8Integration.rc")

    #V8
    $v8Revision = "18456" # Tag 3.24.10
    $v8Repository = "http://v8.googlecode.com/svn/trunk"
    $v8Directory = Join-Path $baseDirectory "v8"

    #Python
    $pythonRepository = "http://src.chromium.org/svn/trunk/tools/third_party/python_26"
    $pythonRevision = "89111"
    $pythonDirectory = Join-Path (Join-Path $baseDirectory "v8") (Join-Path "third_party" "python_26")

    #GYP
    $gypRepository = "http://gyp.googlecode.com/svn/trunk"
    $gypRevision = "1806"
    $gypDirectory = Join-Path $v8Directory (Join-Path "build" "gyp")

    #ICU
    $icuRepository = "https://src.chromium.org/chrome/trunk/deps/third_party/icu46"
    $icuRevision = "239289"
    $icuDirectory = Join-Path (Join-Path $baseDirectory "v8") (Join-Path "third_party" "icu")

    #Cygwin
    $cygwinRepository = "http://src.chromium.org/svn/trunk/deps/third_party/cygwin"
    $cygwinRevision = "66844"
    $cygwinDirectory = Join-Path $v8Directory (Join-Path "third_party" "cygwin")

#Source scripts

$buildScriptDir = Join-Path $baseDirectory (Join-Path "tools" "powershell")
. (Join-Path $buildScriptDir "build-functions.ps1")
Import-Module (Join-Path $buildScriptDir "EnvironmentVars.dll")

#Clean if neccessary
Function Clean-All() {
    Push-Location $baseDirectory
    Write-Info "Cleaning everything including dependency checkouts"
    Exec { git clean --quiet -xdf }
    Pop-Location
}

Function Clean() {
    Push-Location $baseDirectory
    Write-Info "Cleaning all output"
    Exec { git clean --quiet --exclude .\v8 -xdf }
    Pop-Location
}

Function Clean-OutputOnly() {
    Push-Location $baseDirectory
    Remove-Item -ErrorAction SilentlyContinue -Recurse -Force .\bin
    Pop-Location
}

Function Test-CanRunQuickBuild() {
    $js1Dir = Join-Path $libsDirectory $platform
    $js1Path = Join-Path $js1Dir "js1.dll"

    write-host $js1path

    if ((Test-Path $js1Path) -eq $false) {
        Write-Info "Cannot run a 'quick' build - js1.dll is not found at $js1Dir"
        return $false
    } else {
        Write-Info "Using js1.dll from a previous build, it is likely that the commit hash and version in js1.dll is wrong."
        return $true
    }
}

if ($Target -eq "clean-all") {
    Clean-All
    exit
}

if ($Target -eq "clean") {
    Clean
    exit
}

if (($Target -eq "quick") -and ((Test-CanRunQuickBuild) -eq $false)) {
    Write-Info "Running full build instead"
    $Target = "full"
}

Clean-OutputOnly

#Set up based on platform, configuration and version
if ($platform -eq "x64") {
    # The parameter to pass to Gyp to generate projects for the appropriate architecture
	$gypPlatformParameter = "-Dtarget_arch=x64"

    # The platform name for V8 (as generated by gyp)
    $v8VisualStudioPlatform = "x64"

    # The destination for the built V8 libraries to be copied to
    $v8LibsDestination = Join-Path $libsDirectory "x64"

    # The platform for JS1 (as defined in the project file)
    $js1VisualStudioPlatform = "x64"

    # The platform for the EventStore solution (as defined in the solution)
    $eventStorePlatform = "Any CPU"
} elseif ($platform -eq "x86") {
    # The platform name for V8 (as generated by Gyp)
    $gypPlatformParameter = "-Dtarget_arch=Win32"

    # The parameter to pass to Gyp to generate projects for the appropriate architecture
    $v8VisualStudioPlatform = "Win32"

    # The destination for the built V8 libraries to be copied to
    $v8LibsDestination = Join-Path $libsDirectory "Win32"

    # The platform for JS1 (as defined in the project file)
    $js1VisualStudioPlatform = "Win32"

    # The platform for the EventStore solution (as defined in the solution)
    $eventStorePlatform = "Any CPU"
} else {
    throw "Platform" + $platform + "is not supported."
}

if ($configuration -eq "release") {
    # The configuration name for V8 (as generated by Gyp)
    $v8VisualStudioConfiguration = "Release"

    # The destination V8 is built in (as generated by Gyp)
    $v8OutputDirectory = Join-Path $v8Directory (Join-Path "build" (Join-Path "Release" "lib"))

    # The configuration name for JS1 (as defined in the project file)
    $js1VisualStudioConfiguration = "Release"
} elseif ($configuration -eq "debug") {
    # The configuration name for V8 (as generated by Gyp)
    $v8VisualStudioConfiguration = "Debug"

    # The destination V8 is built in (as generated by Gyp)
    $v8OutputDirectory = Join-Path $v8Directory (Join-Path "build" (Join-Path "Debug" "lib"))

    # The configuration name for JS1 (as defined in the project file)
    $js1VisualStudioConfiguration = "Debug"
} else {
    throw "Configuration $configuration is not supported. If you think it should be, edit the Setup-ConfigurationParameters task to add it."
}

if ($Defines -eq "") {
    $definesCommandLine = ""
} else {
    $definesCommandLine = "/p:AppendedDefineConstants=$Defines"
}

Write-Info "Build Configuration"
Write-Info "-------------------"

Write-Info "Target: $Target"
Write-Info "Platform: $Platform"
Write-Info "Configuration: $Configuration"
Write-Info "Version: $Version"

if ($SpecificVisualStudioVersion -eq "") {
    Write-Info "Visual Studio Version will be autodetected"
} else {
    Write-Info "Specific Visual Studio Version: $SpecificVisualStudioVersion"
}

Write-Info "Additional Defines: $Defines"

Write-Host ""
Write-Host ""

if (($Target -eq "full") -or ($Target -eq "v8") -or ($Target -eq "js1")) {
    #Get dependencies if necessary
    if ($ForceNetwork -or (Test-ShouldTryNetworkAccess))
    {
        $shouldTryNetwork = $true
    } else {
        $shouldTryNetwork = $false
    }

    $dependenciesMet = (Test-SvnRepoIsAtRevision $v8Directory $v8Revision) -and
                       (Test-SvnRepoIsAtRevision $pythonDirectory $pythonRevision) -and
                       (Test-SvnRepoIsAtRevision $gypDirectory $gypRevision) -and
                       (Test-SvnRepoIsAtRevision $cygwinDirectory $cygwinRevision)

    if ($dependenciesMet -eq $false) {
        if ($shouldTryNetwork -eq $true) {
            Get-SvnRepoAtRevision -Verbose "V8" $v8Repository $v8Directory $v8Revision
            Get-SvnRepoAtRevision -Verbose "Python" $pythonRepository $pythonDirectory $pythonRevision
            Get-SvnRepoAtRevision -Verbose "GYP"  $gypRepository $gypDirectory $gypRevision
            Get-SvnRepoAtRevision -Verbose "ICU"  $icuRepository $icuDirectory $icuRevision
            Get-SvnRepoAtRevision -Verbose "CygWin" $cygwinRepository $cygwinDirectory $cygwinRevision
        } else {
            Assert ($false) "No network connectivity is detected and the required dependencies are not available. Specify ForceNetwork = '$true' if you want to try anyway."
        }
    } else {
        Write-Info "All dependencies already met."
        Write-Host ""
    }
}

try {
    #Run build process
    Push-Environment

        #Set up Visual Studio environment
        if ($SpecificVisualStudioVersion -eq "") {
            $visualStudioVersion = Get-GuessedVisualStudioVersion
            Write-Info "No specific version of Visual Studio provided, using $visualStudioVersion"
        } else {
            $visualStudioVersion = $SpecificVisualStudioVersion
            Write-Info "Visual Studio $VisualStudioVersion specified as parameter"
        }

        Import-VisualStudioVars -VisualStudioVersion $visualStudioVersion

        $commitHashAndTimestamp = Get-GitCommitHashAndTimestamp
        $commitHash = Get-GitCommitHash
        $timestamp = Get-GitTimestamp
        $branchName = Get-GitBranchOrTag

        #Build V8
        if ($Target -ne "quick") {
            #Build V8 and JS1
            Push-Location $v8Directory

            $pythonExecutable = Join-Path $pythonDirectory "python.exe"
            $gypFile = Join-Path $v8Directory (Join-Path "build" "gyp_v8")

            if ($VisualStudioVersion -eq "Windows7.1SDK") {
                $vsVersionParameter = "-Gmsvs_version=2010"
            } else {
                $vsVersionParameter = "-Gmsvs_version=$VisualStudioVersion"
            }


            Exec { & $pythonExecutable $gypFile $vsVersionParameter $gypPlatformParameter }

            $v8Solution = Join-Path $v8Directory (Join-Path "tools" (Join-Path "gyp" "v8.sln"))
            Exec { msbuild $v8Solution /p:platform=$v8VisualStudioPlatform /p:configuration=$v8VisualStudioConfiguration }

            Pop-Location

            #Copy V8 to libs
            $v8IncludeDestination = Join-Path $libsDirectory "include"
            $v8IncludeSource = Join-Path $v8Directory "include"

            $shouldCreateV8IncludeDestination = $true
            if (Test-Path $v8IncludeDestination) {
                #If this isn't a junction, we should delete it
                if ((Test-DirectoryIsJunctionPoint $v8IncludeDestination) -eq $false) {
                    Remove-Item -Recurse -Force $v8IncludeDestination
                    $shouldCreateV8IncludeDestination = $true
                } else {
                    $shouldCreateV8IncludeDestination = $fase
                }

            }

            if ($shouldCreateV8IncludeDestination) {
                $createV8IncludeDestination = "mklink /J $v8IncludeDestination $v8IncludeSource"
                Exec { & cmd /c $createV8IncludeDestination }
            }


            $v8LibsDestination = Join-Path $libsDirectory $platform

            Remove-Item -Recurse -Force $v8LibsDestination -ErrorAction SilentlyContinue
            New-Item -ItemType Container -Path $v8LibsDestination

            Push-Location $v8LibsDestination
            $v8Libs = Get-ChildItem -Filter "*.lib" $v8OutputDirectory
            foreach ($lib in $v8Libs) {
                $fullName = $lib.FullName
                if ($lib.Name.Contains($platform)) {
                    $withoutPlatform = $lib.Name.Replace(".$platform", "")
                    $createLibHardLink = "mklink /H $withoutPlatform $fullName"

                    Write-Host $createLibHardLink

                    Exec { & cmd /c $createLibHardLink }
                } else {
                    $name = $lib.Name
                    $createLibHardLink = "mklink /H $name $fullName"

                    Write-Host $createLibHardLink

                    Exec { & cmd /c $createLibHardLink }
                }
            }
            Pop-Location

	    if ($Target -eq "v8") {
	    	exit
	    }

            #Build JS1 (Patch version resource, Build, Revert version resource)
            try {
                Write-Verbose "Patching $js1VersionResource with product information."
                Patch-CppVersionResource $js1VersionResource $Version $Version $branchName $commitHashAndTimestamp $productName $companyName $copyright

                $js1PlatformToolset = Get-PlatformToolsetForVisualStudioVersion -VisualStudioVersion $VisualStudioVersion
                Exec { msbuild $js1Project /p:Configuration=$js1VisualStudioConfiguration /p:Platform=$js1VisualStudioPlatform /p:PlatformToolset=$js1PlatformToolset }
            } finally {
                Write-Verbose "Reverting $js1VersionResource to original state."
                & { git checkout --quiet $js1VersionResource }
            }

	    if ($Target -eq "js1") {
	    	exit
	    }
        }

        #Build Event Store (Patch AssemblyInfo, Build, Revert AssemblyInfo)
        $assemblyInfos = Get-ChildItem -Recurse -Filter AssemblyInfo.cs
        $versionInfoFile = Resolve-Path (Join-Path $srcDirectory (Join-Path "EventStore.Common" (Join-Path "Utils" "VersionInfo.cs"))) -Relative
        try {
            foreach ($assemblyInfo in $assemblyInfos) {
                $path = Resolve-Path $assemblyInfo.FullName -Relative
                Write-Verbose "Patching $path with product information."
                Patch-AssemblyInfo $path $Version $Version $branchName $commitHashAndTimestamp $productName $companyName $copyright
            }
            
            Write-Verbose "Patching $versionInfoFile with product information."
            Patch-VersionInfo -versionInfoFilePath $versionInfoFile -version $Version -commitHash $commitHash -timestamp $timestamp -branch $branchName

            Exec { msbuild $eventStoreSolution /p:Configuration=$configuration /p:Platform=$eventStorePlatform $definesCommandLine }
        } finally {
            foreach ($assemblyInfo in $assemblyInfos) {
                $path = Resolve-Path $assemblyInfo.FullName -Relative
                Write-Verbose "Reverting $path to original state."
                & { git checkout --quiet $path }
            }
            
            Write-Verbose "Reverting $versionInfoFile to original state."
            & { git checkout --quiet $versionInfoFile }
        }
} finally {
    Pop-Environment
}
