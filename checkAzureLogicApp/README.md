# checkAzureLogicApp

A script to check the run history of a logic app in Azure
It can probably be used for checking event history on nearly any kind of Azure object

Requires you to create an application in Azure AD and create a token under that application. That application must then have enough permissions granted to review the event history you want to monitor.

# Usage
Usage: ./checkAzureLogicApp.sh <tenant> <subscription> <resourcegroup> <provider> <clientid> <clientsecret> <graph_app_id> <expirydays>

  <tenant>        - the tenant id guid that the nagios app authenticates against
                  - this is the tenant in which the app and secret were created
  <subscription>  - the subscription id guid that contains the resource to check
                  - i.e. the azure sub that the logic app is in
  <resourcegroup> - the name of the resource group. text, not a guid
  <provider>      - the provider portion of the API URI, to get to the data to check
                  - this is the portion of the URI after provider/
                  - e.g. Microsoft.Logic/workflows/RaiseToPagerDutyV1.0/runs
  <clientid>      - the Nagios application id guid in Azure AD
  <clientsecret>  - the token/secret associated with the above app
  <graph_app_id>  - the guid ID for the above app, retrieved from the Graph API
                  - this is different to the application id guid from Azure AD!
  <expirydays>    - the number of days threshold to start warning before the token/secret expiry
