##########################################################################
#
# 1. Ensure all projects - excluding Tests - output XML documentation
# 2. Ensure all projects include the StyleCop target
#
##########################################################################

Clear-Host

Import-Module ./SharedFunctions.psm1

function Update-DocumentationProperty ($xml, $configuration) {
    $buildOutput = $xml | Select-Xml "./dns:Project/dns:PropertyGroup[contains(@Condition,'$configuration')]" -Namespace $xmlns | Select-Object -ExpandProperty "Node"
    $documentation = $buildOutput | Select-Xml "./dns:DocumentationFile" -Namespace $xmlns | Select-Object -ExpandProperty "Node"
    if (($documentation -eq $null) -or ($documentation.InnerText -eq "")) {
        $outputPath = $buildOutput | Select-Xml "./dns:OutputPath" -Namespace $xmlns | Select-Object -ExpandProperty "Node" | Select-Object -ExpandProperty "InnerText"
        $documentation = if ($documentation -ne $null) { $documentation } else { $xml.CreateNode("element", "DocumentationFile", "$($xmlns.dns)") }
        $documentation.InnerText = "$outputPath$($assemblyName).XML"
        $buildOutput.AppendChild($documentation) | Out-Null
    }
}

function Update-ProjectHintPaths ($xml, $match) {
    $xpath = "./dns:Project/dns:ItemGroup/dns:Reference/dns:HintPath[contains(translate(., 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), '\bin\$($match)\')]"
    $hintPaths = $xml | Select-Xml $xpath -Namespace $xmlns | Select-Object -ExpandProperty "Node"
    Foreach ($hint in $hintPaths) {
        Write-Host $hint.InnerText
        $hint.InnerText = $hint.InnerText -replace "\\bin\\$($match)\\", "\bin\`$(Configuration)\"
        Write-Host $hint.InnerText
    }
}

if ($PSVersionTable.PSVersion.Major -lt 3) {
    Write-Error "This script requires PowerShell v3.0 or greater. You can download it as part of the Windows Management Framework from the Microsoft site."
    Write-Warning "See: http://www.microsoft.com/en-us/download/details.aspx?id=34595"
    Exit
}

$basePath = Get-Location
Set-Location ..\Source\Server

$projFiles = Get-ChildItem -Include *.csproj -recurse | ? { $_.FullName -notlike "*\.Third Party*" -and $_.FullName -notlike "*\.Tools*" }
$xml = New-Object xml
$projFiles | ForEach-Object {
    Write-Output "Processing file: {$_}"
    $xml.Load($_)
    $xmlns = @{ dns = "http://schemas.microsoft.com/developer/msbuild/2003" }
    $styleCopTarget = $xml | Select-Xml "./dns:Project/dns:Import[contains(@Project,'StyleCop.targets')]" -Namespace $xmlns | Select-Object -ExpandProperty "Node"
    if ($styleCopTarget -eq $null) {
        $styleCopTarget = $xml.CreateNode("element", "Import", "$($xmlns.dns)")
        $styleCopTarget.Attributes.Append($xml.CreateAttribute("Project"))  | Out-Null
        $styleCopTarget.Attributes["Project"].Value = "..\..\.Third Party\MSBuildExtensions\Stylecop\v4.7\StyleCop.targets"
        $projectNode = $xml | Select-Xml "./dns:Project" -Namespace $xmlns | Select-Object -ExpandProperty "Node"
        $projectNode.AppendChild($styleCopTarget) | Out-Null
    }

    # $assemblyName = $xml | Select-Xml "./dns:Project/dns:PropertyGroup/dns:AssemblyName" -Namespace $xmlns | Select-Object -ExpandProperty "Node" | Select-Object -ExpandProperty "InnerText"
    Update-ProjectHintPaths $xml "debug"
    Update-ProjectHintPaths $xml "release"

    if (-not $_.FullName.EndsWith(".Test.csproj") -and -not $_.FullName.EndsWith(".Tests.csproj") -and -not $_.FullName.EndsWith(".Mock.csproj")) {
        Update-DocumentationProperty $xml 'Debug'
        Update-DocumentationProperty $xml 'Release'
    }

    $xml.Save($_)
}

Set-Location $basePath
