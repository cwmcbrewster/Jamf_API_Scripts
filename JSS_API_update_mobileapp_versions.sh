#!/bin/bash

#loosly based on work by https://github.com/bumbletech

####Change these variables for your enviornment####
JSSurl='https://yourjss:8443'
apiUser='user'
apiPass='pass'

###############################################
### Don't edit past this line. Or whatever. ###
###############################################

#check to see if variables have been changed
if [ "$JSSurl" == "https://yourjss:8443" ] || [ "$apiUser" == "user" ] || [ "$apiPass" == "pass" ]; then
  echo "One of the variables needed for your JSS and accounts is set to the default. Open this script in a text editor and check the variables for JSSurl, apiReadOnlyUser & apiReadOnlyPass and try again."
  echo "Exiting..."
  exit 1
fi

#check for jq
if [ ! -f /usr/local/bin/jq ]
then
  echo "jq (https://stedolan.github.io/jq/) could not be found. jq is needed to parse iTunes API results. Please install jq and try again."
  echo "If you use Homebrew, run 'brew install jq'."
  echo "Exiting..."
  exit 1
fi

#set the path for the JSS to check
JSSapiPath="${JSSurl}/JSSResource/mobiledeviceapplications"

#get list of bundleIDs for JSS apps
jamfAppsXml=$(curl -s -H "Accept: text/xml" -u ${apiUser}:"${apiPass}" ${JSSapiPath} | xpath '//mobile_device_applications/mobile_device_application' 2>&1 | awk -F'<mobile_device_application>|</mobile_device_application>' '{print $2}' | grep .)

function check_for_updates () {

#loop through each line of the XML out put so both the bundleID and the JSS app ID of an can be worked with

while read xml_string; do

  #set the app info from the JSS
  id=$(echo "$xml_string" | awk -F'<id>|</id>' '{print $2}')
  app_bundle_id=$(echo "$xml_string" | awk -F'<bundle_id>|</bundle_id>' '{print $2}')
  jamf_version=$(echo "$xml_string" | awk -F'<version>|</version>' '{print $2}')
  itunes_lastknown_url_raw=$(curl -s -H "Accept: text/xml" -u ${apiUser}:"${apiPass}" ${JSSapiPath}/id/$id/subset/General | xpath '//mobile_device_application/general/itunes_store_url' 2>&1 | awk -F'<itunes_store_url>|</itunes_store_url>' '{print $2}' | grep .)
  #XML can't deal with "&". replace the escape text.
  itunes_lastknown_url="${itunes_lastknown_url_raw/&amp;/&}"
  #itunesAdamId=$(echo $itunes_lastknown_url | sed -e 's/.*\/id\(.*\)?.*/\1/')
  itunesAdamId=$(echo ${itunes_lastknown_url} | grep -o -E 'id\d{9,}' | awk -F'id' '{print $2}')

  #define itunes api lookup path with bundleID from JSS
  itunes_api_url="https://uclient-api.itunes.apple.com/WebObjects/MZStorePlatform.woa/wa/lookup?version=2&id=${itunesAdamId}&p=mdm-lockup&caller=MDM&platform=itunes&cc=us&l=en"

  #json results from itunes lookup
  itunes_data=$(curl -s -H "Accept: application/JSON" -X GET "${itunes_api_url}")
  bundleId=$(/usr/local/bin/jq -r ".results.\"${itunesAdamId}\".bundleId" <<< "${itunes_data}")
  appleVersion=$(/usr/local/bin/jq -r ".results.\"${itunesAdamId}\".offers[].version.display" <<< "${itunes_data}" 2>/dev/null)

  #check if app's bundleID matches what's on the JSS. If it's blank, there's no record on the iTunes store.
  if [[ -z $id ]]; then
    #do nothing. This is just a blank line in the data parsed from the jss
    :
  elif [[ ${app_bundle_id} != ${bundleId} ]]; then
    echo "Apple bundle ID:${app_bundle_id} | Jamf App ID:${id} | status:NO LONGER AVAILABLE"
  elif [[ ${jamf_version} != ${appleVersion} ]]; then
    echo "Apple bundle ID:${app_bundle_id} | Jamf App ID:${id} | status:VERSION MISMATCH"
    read -p "Press Y to update ${app_bundle_id} from version ${jamf_version} to version ${appleVersion} [Y]: " continue </dev/tty
    continue=${continue:-Y}
    if [[ "${continue}" =~ [Y|y] ]]; then
      versionData="<mobile_device_application><general><version>${appleVersion}</version></general></mobile_device_application>"
      curl -s -H "Content-Type: text/xml" -u ${apiUser}:"${apiPass}" "${JSSapiPath}/id/${id}/subset/General" -d "${versionData}" -X PUT
      echo ""
    fi
  elif [[ -n ${id} ]]; then
    echo "Apple bundle ID:${app_bundle_id} | Jamf App ID:${id} | status:CURRENT"
  fi

done <<< "${jamfAppsXml}"

}

echo "This may take a while depending on the number of apps in your jss"
echo "Checking $(echo "${jamfAppsXml}" | wc -l | awk '{print $1}') apps..."

check_for_updates

echo ""
echo "All done!"
