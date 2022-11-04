#!/bin/bash
#
# A script to check action history on Azure objects
#
# 20221104      jg@cyberfit.uk  Initial Version

function usage {
  echo
  echo "Usage: $0 <tenant> <subscription> <resourcegroup> <provider> <clientid> <clientsecret> <graph_app_id> <expirydays>"
  echo
  echo "  <tenant>        - the tenant id guid that the nagios app authenticates against"
  echo "                  - this is the tenant in which the app and secret were created"
  echo "  <subscription>  - the subscription id guid that contains the resource to check"
  echo "                  - i.e. the azure sub that the logic app is in"
  echo "  <resourcegroup> - the name of the resource group. text, not a guid"
  echo "  <provider>      - the provider portion of the API URI, to get to the data to check"
  echo "                  - this is the portion of the URI after provider/"
  echo "                  - e.g. Microsoft.Logic/workflows/RaiseToPagerDutyV1.0/runs"
  echo "  <clientid>      - the Nagios application id guid in Azure AD"
  echo "  <clientsecret>  - the token/secret associated with the above app"
  echo "  <graph_app_id>  - the guid ID for the above app, retrieved from the Graph API"
  echo "                  - this is different to the application id guid from Azure AD!"
  echo "  <expirydays>    - the number of days threshold to start warning before the token/secret expiry"
  exit 1
}

# Do we have enough parameters?
if [ -z ${8+x} ]
then
  echo "ERROR: Missing parameters"
  usage
fi

# Check various parameters with some simple regex
guid_regex='^[0-9A-Fa-f\-]{36}$'
numb_regex='^[0-9]+$'

# Tenant ID
if ! [[ $1 =~ $guid_regex ]]
then
  echo "ERROR: tenant GUID $1 is in wrong format"
  usage
else
  tenant_id=$1
fi

# Subscription ID
if ! [[ $2 =~ $guid_regex ]]
then
  echo "ERROR: subscription GUID $2 is in wrong format"
  usage
else
  sub_id=$2
fi

# Resource group
rgroup=$3

# Provider URI section
provider=$4

# Client ID for Azure AD app
if ! [[ $5 =~ $guid_regex ]]
then
  echo "ERROR: clientid GUID $5 is in wrong format"
  usage
else
  client_id=$5
fi

# Client secret for Azure AD app
client_secret=$6

# Graph API ID for Azure AD app
if ! [[ $7 =~ $guid_regex ]]
then
  echo "ERROR: graph_app_id GUID $7 is in wrong format"
  usage
else
  graph_app_id=$7
fi

# Check expiry days is an integer
if ! [[ $8 =~ $numb_regex ]]
then
  echo "ERROR: expirydays value $8 is not a number"
  usage
else
  client_secret_expiry=$8
fi

# Usually don't have to change anything past here
# Get the date in the right format for an OAPI timestamp, URL encoded
date_threshold_text='1 week ago'
date_threshold=$(date +%Y-%m-%dT%H%%3A%M%%3A%S.%NZ -d "$date_threshold_text")
# API version in use
api=2016-06-01
# Filter, URL encoded
filter=Status%20ne%20%27Succeeded%27%20and%20startTime%20ge%20$date_threshold

# Check required supporting tools are available
if [ ! -f /usr/bin/jq ]
then
  echo UNKNOWN - jq binary not installed
  exit 3
fi

if [ ! -f /usr/bin/curl ]
then
  echo UNKNOWN - curl binary not installed
  exit 3
fi

# Perform authentication query against Azure AD to get auth token
tokenjson=$(curl -s -X POST -d "grant_type=client_credentials&client_id=$client_id&client_secret=$client_secret&resource=https://management.azure.com/" https://login.microsoftonline.com/$tenant_id/oauth2/token)

# Check cURL did not leave an exit code
if [ $? -ne 0 ]
then
  echo CRITICAL - cURL had some error getting an auth token from Azure AD
  exit 2
fi

# Extract fields we want from the JSON response
token=$(echo $tokenjson | jq -r .access_token)

# Check we actually got an auth token
if [ $token == "null" ]
then
  echo CRITICAL - Auth token was null, cannot continue. Response from Azure AD:
  echo $tokenjson | jq -r .error_description
  exit 2
fi

# Use our auth token to get data from the Azure REST API
checkjson=$(curl -s -H "Content-Type: application/json" -H "Authorization: Bearer $token" "https://management.azure.com/subscriptions/$sub_id/resourceGroups/$rgroup/providers/$provider?api-version=$api&%24filter=$filter")

# Check cURL ran OK
if [ $? -ne 0 ]
then
  echo CRITICAL - cURL had some error getting the API URI
  exit 2
fi

# Get the value field from JSON response
checkvalue=$(echo $checkjson | jq -r .value)

# If value field is null the query didnt work
if [ $checkvalue == "null" ]
then
  echo CRITICAL - Value was null, cannot continue. Response from Azure:
  echo $checkjson | jq -r .error.message
  exit 2
fi

# Perform authentication query against Graph API to get auth token
tokenjson=$(curl -s -X POST -d "grant_type=client_credentials&client_id=$client_id&client_secret=$client_secret&scope=https%3A%2F%2Fgraph.microsoft.com%2F.default" https://login.microsoftonline.com/$tenant_id/oauth2/v2.0/token)

# Check cURL did not leave an exit code
if [ $? -ne 0 ]
then
  echo CRITICAL - cURL had some error getting an auth token from Graph
  exit 2
fi

# Extract fields we want from the JSON response
token=$(echo $tokenjson | jq -r .access_token)

# Check we actually got an auth token
if [ $token == "null" ]
then
  echo CRITICAL - Auth token was null, cannot continue. Response from Graph:
  echo $tokenjson | jq -r .error_description
  exit 2
fi

# Query the Graph API to see when our app secret will need renewing

expiryjson=$(curl -s -H "Content-Type: application/json" -H "Authorization: Bearer $token" "https://graph.microsoft.com/v1.0/applications/$graph_app_id/passwordCredentials")

# Check cURL did not leave an exit code
if [ $? -ne 0 ]
then
  echo CRITICAL - cURL had some error getting the token info from Graph
  exit 2
fi

# Extract fields we want from the JSON response
expiryDate=$(echo $expiryjson | jq -r .value[].endDateTime | sed 's/Z$//')

# Check we actually got an auth token
if [[ $expiryDate == "null" || $expiryDate == "" ]]
then
  echo CRITICAL - Expiry date is null, cannot continue. Response from Graph:
  echo $tokenjson | jq -r .error_description
  exit 2
fi

# Take expiry date from Graph API and work out number of days left
expires_in=$[$[$(date --date=$expiryDate +%s)-$(date +%s)]/60/60/24]

# If the value field is empty that indicates no unsuccessful runs within the threshold
if [ $checkvalue == "[]" ]
then
  if [ $expires_in -lt $client_secret_expiry ]
  then
    echo WARNING - No failures detected but Azure auth token will expire in $expires_in days, please renew it
    exit 1
  else
    echo OK - no failed runs detected since $date_threshold_text
    exit 0
  fi
else
  echo CRITICAL - failed runs of $provider detected
  exit 2
fi
