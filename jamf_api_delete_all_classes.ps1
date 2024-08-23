# Use the Jamf Pro API to delete all classes

$jamfUrl = "https://your_jamf_server:8443"

$ErrorActionPreference = "Stop"

$jamfCred = Get-Credential

$url = "$jamfUrl/JSSResource/classes"

function checkAuthToken {
  # https://stackoverflow.com/questions/24672760/powershells-invoke-restmethod-equivalent-of-curl-u-basic-authentication
  if (!$authTokenData) {
    Write-Host 'Getting new authorization token... ' -NoNewline
    $base64creds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($jamfCred.GetNetworkCredential().UserName):$($jamfCred.GetNetworkCredential().Password)"))
    $script:authTokenData = Invoke-RestMethod -Uri "$jamfUrl/api/v1/auth/token" -Headers @{Authorization=("Basic $base64creds")} -Method Post
    #Write-Host "$authTokenData"
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

# START

checkAuthToken

$jamfClassesXml = Invoke-RestMethod -Uri "$jamfUrl/JSSResource/classes" -Headers $jamfApiHeadersXml

Write-Host "$($jamfClassesXml.classes.size) classes found"
Write-Host "----------------------------------------"

$confirmation = (Read-Host 'Delete ALL classes? (Y/N) [N]').ToLower()
if ($confirmation -eq 'y') {
  foreach ($class in $jamfClassesXml.classes.class) {
    Write-Host "Deleting class $($class.id)..." -NoNewline
    Invoke-RestMethod -Uri "$jamfUrl/JSSResource/classes/id/$($class.id)" -Headers $jamfApiHeadersXml -Method Delete | Out-Null
    if ($? -eq $true) {
      Write-Host ' Done.'
    } else {
      Write-Host ' Error.'
    }
    checkAuthToken
  }
}

Write-Host 'Killing authorization token... ' -NoNewline
Invoke-RestMethod -Uri "$jamfUrl/api/v1/auth/invalidate-token" -Headers $jamfApiHeaders -Method Post | Out-Null
Write-Host 'Done.'
