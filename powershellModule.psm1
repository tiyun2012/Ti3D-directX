Add-Type -AssemblyName System.IO.Compression.FileSystem

function Copy-Folders {
    param (
        [string]$SourcePath,
        [string]$DestinationPath,
        [string[]]$FoldersToCopy
    )

    foreach ($folder in $FoldersToCopy) {
        $sourceFolderPath = Join-Path -Path $SourcePath -ChildPath $folder
        $destinationFolderPath = Join-Path -Path $DestinationPath -ChildPath $folder

        if (-not (Test-Path -Path $sourceFolderPath -PathType Container)) {
            Write-Error "Source folder '$sourceFolderPath' does not exist."
            return $false
        }

        Write-Output "Copying $sourceFolderPath to $destinationFolderPath"
        try {
            Copy-Item -Path $sourceFolderPath -Destination $destinationFolderPath -Recurse -Force
            Write-Output "Copied $folder successfully."
        } catch {
            Write-Error "Failed to copy folder '$folder': $_"
            return $false
        }
    }

    return $true
}
function Expand-Rar {
    param (
        [string]$RarFilePath,
        [string]$ExtractToPath
    )

    Write-Output "Extracting $RarFilePath to $ExtractToPath"
    try {
        # Load necessary namespaces
        $reader = [SharpCompress.Readers.Rar.RarReader]::Open([System.IO.File]::OpenRead($RarFilePath))
        while ($reader.MoveToNextEntry()) {
            if (-not $reader.Entry.IsDirectory) {
                $entryPath = Join-Path -Path $ExtractToPath -ChildPath $reader.Entry.Key
                $entryDirectory = [System.IO.Path]::GetDirectoryName($entryPath)

                if (-not (Test-Path -Path $entryDirectory)) {
                    New-Item -Path $entryDirectory -ItemType Directory | Out-Null
                }

                Write-Output "Extracting $entryPath"
                $reader.WriteEntryToFile($entryPath)
            }
        }
        Write-Output "Extraction completed."
        return $true
    } catch {
        Write-Error "Failed to extract rar file: $_"
        return $false
    }
}
function Expand-Zip {
    param (
        [string]$ZipFilePath,
        [string]$ExtractToPath
    )

    Write-Output "Extracting $ZipFilePath to $ExtractToPath"
    try {
        [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipFilePath, $ExtractToPath)
        Write-Output "Extraction completed."
        return $true
    } catch {
        Write-Error "Failed to extract zip file: $_"
        return $false
    }
}
function Expand-SpecificFilesFromZip {
    param (
        [string]$zipFilePath,       # Path to the ZIP file
        [string]$destinationPath,   # Where to extract the files
        [string[]]$filesTracked     # List of files to extract
    )

    # Check if the ZIP file exists
    $testZipFileExisting = Test-FileExistence -FilePath $zipFilePath
    if (-not $testZipFileExisting) {
        Write-Error "The ZIP file '$zipFilePath' does not exist."
        return $null
    }

    # Open the zip archive
    $zipArchive = [System.IO.Compression.ZipFile]::OpenRead($zipFilePath)

    # Loop through each file to extract
    foreach ($file in $filesTracked) {
        $outputFilePath = Join-Path $destinationPath $file

        # Check if the file already exists
        $testExistingFile = Test-FileExistence -FilePath $outputFilePath
        if ($testExistingFile) {
            Write-Host "$outputFilePath already exists" -ForegroundColor Green
            continue
        } else {
            Write-Warning "$outputFilePath doesn't exist"
        }

        # Look for the exact file name match in the zip entries
        $entryFound = $false
        foreach ($entry in $zipArchive.Entries) {
            $name_=$entry.FullName
            if ($name_.EndsWith($file.Replace('\', '/').Replace('//','/') )){
                $entryFound = $true
                Write-Host "Extracting $($entry.FullName) to $destinationPath" -ForegroundColor Yellow

                # Create directory structure if necessary
                $outputDir = [System.IO.Path]::GetDirectoryName($outputFilePath)
                if (-not (Test-Path $outputDir)) {
                    New-Item -Path $outputDir -ItemType Directory | Out-Null
                }

                # Extract the file
                # Write the entry content to the output file using the provided method
                $entryStream = $entry.Open()
                $outputStream = [System.IO.File]::Create($outputFilePath)
                try {
                    $buffer = New-Object byte[] 8192  # Use a buffer to copy the data
                    while (($bytesRead = $entryStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                        $outputStream.Write($buffer, 0, $bytesRead)
                    }
                } finally {
                    $entryStream.Close()
                    $outputStream.Close()
                }
                break
            }
        }

        if (-not $entryFound) {
            Write-Host "File '$file' not found in the archive." -ForegroundColor Red
        }
    }

    $zipArchive.Dispose()  # Clean up
}

function Invoke-WebFile {
    param (
        [string]$Url,
        [string]$DestinationPath
    )

    Write-Output "Downloading file from $Url to $DestinationPath"
    try {
        Invoke-WebRequest -Uri $Url -OutFile $DestinationPath
        Write-Output "Download completed."
        return $true
    } catch {
        throw "Failed to download file $_"
        return $false
    }
}

function New-PythonVirtualEnvironment {
    param (
        [string]$venvName=".venv"
    )

    # Step 1: Start the virtual environment creation process
    Write-Progress -Activity "Setting up Python Virtual Environment" -Status "Initializing..." -PercentComplete 0

    # Step 2: Check if the folder for the virtual environment exists
    Write-Progress -Activity "Setting up Python Virtual Environment" -Status "Checking folder existence..." -PercentComplete 20
    if (-not (Test-FolderExistence -FolderName $venvName)) {
        New-Item -ItemType Directory -Path $venvName
    }

    # Step 3: Create the virtual environment
    Write-Progress -Activity "Setting up Python Virtual Environment" -Status "Creating virtual environment..." -PercentComplete 50
    & "python" -m venv $venvName

    # Step 4: Install dependencies (optional step)
    Write-Progress -Activity "Setting up Python Virtual Environment" -Status "Installing dependencies..." -PercentComplete 75
    & ".\$venvName\Scripts\pip.exe" install --upgrade pip

    # Step 5: Finalize the process
    Write-Progress -Activity "Setting up Python Virtual Environment" -Status "Finalizing..." -PercentComplete 100

    Write-Output "Virtual environment setup completed at $venvName."
}

# Function to reload the module
function Reset-Module {
    param (
        [string]$ModulePath=(Join-Path -Path (Get-Location) -ChildPath "powershellModule.psm1")
    )

    # Validate that ModulePath is not null or empty
    if ([string]::IsNullOrWhiteSpace($ModulePath)) {
        Write-Error "ModulePath cannot be null or empty."
        return $false
    }

    # Get the module name from the path
    $moduleName = [System.IO.Path]::GetFileNameWithoutExtension($ModulePath)

    # Validate that moduleName is not null or empty
    if ([string]::IsNullOrWhiteSpace($moduleName)) {
        Write-Error "Failed to determine the module name from the path '$ModulePath'."
        return $false
    }

    # Remove the existing module if loaded
    if (Get-Module -Name $moduleName) {
        Remove-Module -Name $moduleName -Force
        Write-Output "Module '$moduleName' removed successfully."
    }

    # Import the module
    try {
        Import-Module $ModulePath -Force
        Write-Output "Module '$moduleName' imported successfully."
        return $true
    } catch {
        Write-Error "Failed to import module '$moduleName': $_"
        return $false
    }
}

function Trace-Info {
    $callStack = Get-PSCallStack
    if ($callStack.Count -gt 1) {
        $callerFrame = $callStack[1]
        return @{
            errorInfo="the starting breaks at line $($callerFrame.ScriptLineNumber) of the file $($callerFrame.ScriptName)"
            # ScriptName = $callerFrame.ScriptName
            # LineNumber = $callerFrame.ScriptLineNumber
        }
    } else {
        return $null
    }
}

function Get-PythonVersion {
    param (
        [string]$RequiredVersion,
        [string]$PythonPath = $(Get-Command python | Select-Object -ExpandProperty Source)
    )

    # Check if Python is available
    if (-not (Test-Path -Path $PythonPath)) {
        Write-Error "Python executable not found. Please provide a valid Python path."
        return $false
    }

    # Get the Python version $versionOutput='Python 4.12.0'
    $versionOutput = & $PythonPath --version 2>&1
    $versionPattern = "Python\s+(\d+\.\d+)\.\d+"
    if ($versionOutput -match $versionPattern) {
        $installedVersion = $matches[1]
        if ($installedVersion -eq $RequiredVersion) {
            return $true
        } else {
            Write-Output "Installed Python version is $installedVersion, but $RequiredVersion is required."
            return $false
        }
    } else {
        Write-Error "Failed to determine Python version."
        return $false
    }
}
function Install-RequiredPythonModules {
    param (
        [string]$EnvPath,
        [string]$RequirementsFile = ".\requirements.txt",
        [switch]$ForceInstall = $false
    )

    # Step 1: Read the requirements.txt file
    if (-not (Test-Path $RequirementsFile)) {
        Write-Error "Requirements file not found at $RequirementsFile"
        return
    }
    $modules = Get-Content -Path $RequirementsFile

    # Step 2: Activate the virtual environment
    $activateScript = "$EnvPath\Scripts\Activate.ps1"
    if (-not (Test-Path $activateScript)) {
        Write-Error "Virtual environment activation script not found at $activateScript"
        return
    }
    & $activateScript

    # Step 3: Check and install missing modules
    foreach ($module in $modules) {
        Write-Progress -Activity "Checking module $module" -Status "Checking if $module is installed..." -PercentComplete 0

        $isModuleInstalled = & "$EnvPath\Scripts\pip.exe" show $module

        if (-not $isModuleInstalled -or $ForceInstall) {
            Write-Progress -Activity "Installing $module" -Status "Installing $module..." -PercentComplete 50
            & "$EnvPath\Scripts\pip.exe" install $module
        } else {
            Write-Host "$module is already installed."
        }

        Write-Progress -Activity "Module Check Complete" -Status "$module check complete" -PercentComplete 100
    }

    Write-Host "All required modules are installed."
}
function Write-ProgressLog {
    param (
        [string]$Message,
        [string]$logFile,
        [bool]$clean = $false
    )

    try {
        # Clean the log file if $clean is passed as $true
        if ($clean -eq $true) {
            Clear-Content -Path $logFile
            Write-Output "Log file content cleared: $logFile"
        }

        # Append the new message to the log file
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logEntry = "$timestamp - $Message"
        
        Add-Content -Path $logFile -Value $logEntry
        Write-Output "Log entry added: $logEntry"
    } catch {
        Write-Error "Failed to write to log file: $_"
    }
}

# Function to check if a step has been completed
function Test-StepCompleted {
    param(
        [string]$step,
        [string]$logFile = ".\setup.log"
    )
    return Select-String -Path $logFile -Pattern $step -Quiet
}
function Test-FileExistence {
    param (
        [string]$FilePath
    )

    # Check if the file exists
    if (Test-Path -Path $FilePath -PathType Leaf) {
        return $true
    } else {
        return $false
    }
}
function Test-FolderExistence {
    param (
        [string]$FolderName
    )

    # Get the current directory
    $CurrentDirectory = Get-Location

    # Combine the current directory path with the folder name
    $FolderPath = Join-Path -Path $CurrentDirectory -ChildPath $FolderName

    # Check if the folder exists
    if (Test-Path -Path $FolderPath -PathType Container) {
        return $true
    } else {
        return $false
    }
}
function Test-Uri
 {
    param (
        [string]$Uri
    )
    
    $response = Invoke-WebRequest -Uri $uri -Method Head
    if ($response.StatusCode -eq 200) {
        Write-Output "The link is valid: $Uri"
        return $Uri
    } else {
        Write-Error "The link is not valid."
        return $null
    }
}

