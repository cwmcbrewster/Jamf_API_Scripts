# This script needs to be run with a Jamf Pro account configured with the following minimum permissions:
# Read and Update on Policies

$jamfUrl = "jamf.example.com"
$jamfUser = "api_user"
$jamfPass = "password"

$ErrorActionPreference = "Stop"

function checkAuthToken {
  # https://stackoverflow.com/questions/24672760/powershells-invoke-restmethod-equivalent-of-curl-u-basic-authentication
  if (!$authTokenData) {
    Write-Host 'Getting new authorization token... ' -NoNewline
    $base64creds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("${jamfUser}:${jamfPass}"))
    $script:authTokenData = Invoke-RestMethod -Uri "$jamfUrl/api/v1/auth/token" -Headers @{Authorization=("Basic $base64creds")} -Method Post
    $script:authToken = $authTokenData.token
    $script:authTokenExpireDate = Get-Date "$($authTokenData.expires)"
    Write-Host 'Done.'
  } else {
    # Update token if it expires in 5 minutes or less
    if ($(Get-Date).AddMinutes(5) -gt $authTokenExpireDate) {
      Write-Host 'Renewing authorization token... ' -NoNewline
      $script:authTokenData = Invoke-RestMethod -Uri "$jamfUrl/api/v1/auth/keep-alive" -Headers $jamfApiHeaders -Method Post
      $script:authToken = $authTokenData.token
      $script:authTokenExpireDate = Get-Date "$($authTokenData.expires)"
      Write-Host 'Done.'
    }
  }

  $script:jamfApiHeaders = @{
    Authorization="Bearer $authToken"
    Accept="application/json"
  }

  $script:jamfApiHeadersXml = @{
    Authorization="Bearer $authToken"
    Accept="application/xml"
  }
}

Function setJamfScriptParam {
  $jamfPolicy = Invoke-RestMethod -Uri "$jamfUrl/JSSResource/policies/id/$jamfPolicyNum/subset/General&Scripts" -Headers $jamfApiHeadersXml -Method Get
  $jamfPolicyScriptCount = $jamfPolicy.policy.scripts.size
  $jamfPolicyScripts = $jamfPolicy.policy.scripts.script
  Write-Host "Number of scripts for policy ${jamfPolicyNum}: $jamfPolicyScriptCount"
  ForEach ($jamfPolicyScript in $jamfPolicyScripts) {
    $scriptName = $jamfPolicyScript.name
    $scriptParam = "parameter" + $jamfScriptParamNum
    #Write-Host $scriptParam
    if ($($jamfPolicyScript.id) -eq $jamfScriptId -and $($jamfPolicyScript.name) -eq "$jamfPolicyScriptName") {
    Write-Host "Current $scriptParam for script $jamfScriptId in policy ${jamfPolicyNum}:"
      Write-Host "$($jamfPolicyScript.$scriptParam)"
      $jamfPolicyScript.$scriptParam = "$new"
      Write-Host "Script $($jamfPolicyScript.id): Setting $scriptParam."
    } else {
      Write-Host "Script $($jamfPolicyScript.id): No changes."
    }
  }
  Invoke-RestMethod -Uri "$jamfUrl/JSSResource/policies/id/$jamfPolicyNum" -Headers $jamfApiHeadersXml -Method Put -Body $jamfPolicy | Out-Null
}

# Start

# Force TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

checkAuthToken

# Set script parameter for policy 500
$jamfPolicyNum = 500
$jamfScriptId = 100
$jamfScriptParamNum = 2
$jamfPolicyScriptName = 'myscript.sh'
$new = '1234'
setJamfScriptParam

# Kill auth token
Write-Host 'Killing authorization token... ' -NoNewline
Invoke-RestMethod -Uri "$jamfUrl/api/v1/auth/invalidate-token" -Headers $jamfApiHeaders -Method Post | Out-Null
Write-Host 'Done.'
