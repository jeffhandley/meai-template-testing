# Define the valid choices for template configurations
$aiServiceProviders = @("azureopenai", "githubmodels", "ollama", "openai")
$vectorStores = @("local", "azureaisearch", "qdrant")
$useManagedIdentityOptions = @( $true, $false )
$useAspireOptions = @( $true, $false )

# Define the base output directory for the generated projects
$outputBaseDirectory = "Generated"

# Define the paths to the secrets command files
$secretsAzureOpenAI     = Join-Path $PSScriptRoot "MEAI-Template-Secrets-AzureOpenAI.cmd"
$secretsOpenAI          = Join-Path $PSScriptRoot "MEAI-Template-Secrets-OpenAI.cmd"
$secretsGitHub          = Join-Path $PSScriptRoot "MEAI-Template-Secrets-GitHub.cmd"
$secretsAzureAISearch   = Join-Path $PSScriptRoot "MEAI-Template-Secrets-AzureAISearch.cmd"

# Ensure the output directory exists
if (-Not (Test-Path $outputBaseDirectory)) {
    New-Item -ItemType Directory -Path $outputBaseDirectory | Out-Null
}

# Loop over all valid combinations of configurations
foreach ($aiServiceProvider in $aiServiceProviders) {
    foreach ($vectorStore in $vectorStores) {
        foreach ($useManagedIdentity in $useManagedIdentityOptions) {
            foreach ($useAspire in $useAspireOptions) {
                # Skip invalid combinations based on the template's conditions
                if (($useAspire -eq $false -and $vectorStore -eq "qdrant") -or
                    ($useManagedIdentity -and $useAspire -and $vectorStore -eq "qdrant") -or
                    ($useManagedIdentity -and $aiServiceProvider -notin @("azureopenai", "azureaifoundry") -and $vectorStore -ne "azureaisearch")) {
                    continue
                }

                # Create the folder name based on the current combination
                $folderNameParts = @()
                $folderNameParts += $aiServiceProvider
                $folderNameParts += $vectorStore
                if ($useManagedIdentity) {
                    $folderNameParts += "ManagedIdentity"
                }
                if ($useAspire) {
                    $folderNameParts += "Aspire"
                }
                $folderName = $folderNameParts -join "_"

                $outputFolder = Join-Path $outputBaseDirectory $folderName

                # Ensure the folder exists
                if (-Not (Test-Path $outputFolder)) {
                    New-Item -ItemType Directory -Path $outputFolder | Out-Null
                }

                # Build the dotnet new command with the current combination
                $dotnetNewCommand = @(
                    "dotnet new aichatweb",
                    "-o", "`"$outputFolder`"",
                    "--provider", $aiServiceProvider,
                    "--vector-store", $vectorStore,
                    ($useManagedIdentity -eq $true ? "--managed-identity" : ""),
                    ($useAspire -eq $true ? "--aspire" : "")
                ) -join " "

                # Run the dotnet new command
                Write-Host "Running: $dotnetNewCommand"
                Invoke-Expression $dotnetNewCommand

                if ($useAspire) {
                    cd $outputFolder\*AppHost
                }
                else {
                    cd $outputFolder
                }

                if ($aiServiceProvider -eq "azureopenai") {
                    cmd /c $secretsAzureOpenAI
                }
                if ($aiServiceProvider -eq "openai") {
                    cmd /c $secretsOpenAI
                }
                if ($aiServiceProvider -eq "githubmodels") {
                    cmd /c $secretsGitHub
                }

                if ($vectorStore -eq "azureaisearch") {
                    cmd /c $secretsAzureAISearch
                }

                cd -
            }
        }
    }
}

Write-Host "All template combinations have been generated in the '$outputBaseDirectory' directory."
Write-Host "Generating a SLN file for all projects"

# Exclude references when adding the projects to avoid duplication additions and to ensure a clean build
dotnet new sln
Get-ChildItem -Path . -Filter *.csproj -Recurse -File | ForEach-Object { dotnet sln add $_.FullName --include-references False }

Write-Host "Building the solution"
dotnet build
