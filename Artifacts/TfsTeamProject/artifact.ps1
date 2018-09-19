Param(
    [Parameter(Mandatory=$true)]
    [string] $tpcUrl,
    [Parameter(Mandatory=$true)]
    [string] $name,
    [Parameter(Mandatory=$true)]
    [ValidateSet("Scrum","Agile","CMMI")]
    [string] $processTemplate,
    [Parameter(Mandatory=$true)]
    [ValidateSet("Git","TFVC")]
    [string] $versionControlType
)

# ============ this is our entry point ==================
Write-Output "Creating team project $name"

$url = "$tpcUrl/_apis/projects?api-version=2.0"
$projects = ((Invoke-WebRequest -Uri $url -UseDefaultCredentials).Content | ConvertFrom-Json).value

$projectExists = ($projects -and ($projects | Where-Object { $_.Name -eq $name }))
if ($projectExists)
{
    Write-Output "Project $name already exists."
    return
}

switch ($processTemplate)
{
    "Scrum" { $processTemplateId = "6b724908-ef14-45cf-84f8-768b5384da45" }
    "Agile" { $processTemplateId = "adcc42ab-9882-485e-a3ed-7678f01f66bc" }
    "CMMI"  { $processTemplateId = "27450541-8e31-4150-9947-dc59f998fc01" }
}

$body = "{
  ""name"": ""$name"",
  ""capabilities"": {
    ""versioncontrol"": {
      ""sourceControlType"": ""$versionControlType""
    },
    ""processTemplate"": {
      ""templateTypeId"": ""$processTemplateId""
    }
  }
}"

$url = "$tpcUrl/_apis/projects?api-version=2.0"
$result = (Invoke-WebRequest -Uri $url -UseDefaultCredentials -Method Post -Body $body -ContentType "application/json")
$content = ($result.Content | ConvertFrom-Json)
$projectId = $content.id
$projectState = $content.status

$i = 0
while($i -lt 360 -and $projectState -ne "WellFormed")
{
    Sleep -Seconds 1
    $url = "$tpcUrl/_apis/projects/$($name)?api-version=2.0"
    $result = (Invoke-WebRequest -Uri $url -UseDefaultCredentials)
    $content = ($result.Content | ConvertFrom-Json)
    $projectState = $content.state
    $i++
}

if ($projectState -eq "WellFormed")
{
    Write-Output "Successfully created project $name."
}
else
{
    Write-Error "Project creation started, but after some waiting it is still in state $projectState. That does not feel right..."
}