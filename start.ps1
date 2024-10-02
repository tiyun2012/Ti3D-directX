# Import the module
$modulePath = ".\\powershellModule.psm1"
$logFile = ".\setup.log"
$ErrorLog=".\Error.log"
# powershellModule\Reset-Module $modulePath
# import  powershellModule 
try {
    Write-Progress -Activity "1: -----importing module:  $modulePath" -Status "start importing" -PercentComplete 0
    Import-Module $modulePath -Verbose
    Write-Progress -Activity "importing module $modulePath" -Status "done" -PercentComplete 100
    }
catch {
    Write-Error "Failed to import module: $_"
    return
}
# make third party root directory
[string]$thirdPartyRoot=".\ThirdParty"
$message="checking the existing directory: $thirdPartyRoot"
Write-Host $message -ForegroundColor DarkGreen
if (-not(powershellModule\Test-FolderExistence -FolderName $thirdPartyRoot))
    {
        Write-Host "making  $thirdPartyRoot" -ForegroundColor Cyan
        Write-Output "Creating folder: $thirdPartyRoot"
        New-Item -ItemType Directory -Path $thirdPartyRoot
    }
else
{
    Write-Host "The directory already exists: $thirdPartyRoot" -ForegroundColor Green
}

#clean errorlog
powershellModule\Write-ProgressLog -Message '' -logFile $ErrorLog -clean $true

Write-Host "--- Checking Dear ImGui Module-----" -ForegroundColor Yellow
$imguiZip = "$thirdPartyRoot\imgui.zip"
$imguiUri = "https://github.com/ocornut/imgui/archive/refs/heads/master.zip"

# Check if the zip file already exists
$testImguiFileExisting = powershellModule\Test-FileExistence -FilePath $imguiZip
if ($testImguiFileExisting) 
{
    Write-Output "$imguiZip already exists in the current working directory"
} else 
{
    try
    {
        powershellModule\Invoke-WebFile -Url $imguiUri -DestinationPath $imguiZip
    }
    catch
    {
        Write-Error "Failed to download: $_"
        return
    }


}

# Extract specific Dear ImGui files
$imguiRoot = "$thirdPartyRoot\imgui"
$imguiList = @("imgui_widgets.cpp","imgui_demo.cpp","backends/imgui_impl_win32.h","imgui_draw.cpp","imgui.h",
             "imgui.cpp", "backends/imgui_impl_win32.cpp", "backends/imgui_impl_dx12.cpp","imstb_truetype.h",
             "imgui_tables.cpp","imgui_internal.h","imconfig.h","imstb_rectpack.h","imstb_textedit.h","backends/imgui_impl_dx12.h")
powershellModule\Expand-SpecificFilesFromZip -zipFilePath $imguiZip -destinationPath $imguiRoot -filesTracked $imguiList




Write-Host "------------Settings successfully completed.---------------------------" -ForegroundColor Green




