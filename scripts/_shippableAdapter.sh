#!/bin/bash -e

__initialize() {
  API_URL=$(cat $STATE_FILE | jq -r '.systemSettings.apiUrl')
  API_TOKEN=$(cat $STATE_FILE | jq -r '.systemSettings.serviceUserToken')
  RESPONSE_CODE=404
  RESPONSE_DATA=""
  CURL_EXIT_CODE=0

  touch $API_RESPONSE_FILE
}

__shippable_get() {
  __initialize

  local url="$API_URL/$1"
  {
    RESPONSE_CODE=$(curl \
      -H "Content-Type: application/json" \
      -H "Authorization: apiToken $API_TOKEN" \
      -X GET $url \
      --silent --write-out "%{http_code}\n" \
      --output $API_RESPONSE_FILE)
  } || {
    CURL_EXIT_CODE=$(echo $?)
  }

  if [ $CURL_EXIT_CODE -gt 0 ]; then
    # we are assuming that if curl cmd failed, API is unavailable
    response="curl failed with error code $CURL_EXIT_CODE. API might be down."
    response_status_code=503
  else
    response_status_code="$RESPONSE_CODE"
    response=$(cat $API_RESPONSE_FILE)
  fi

  rm -f $API_RESPONSE_FILE
}

_shippable_get_masterIntegrations() {
  local master_integrations_get_endpoint="masterIntegrations"
  __shippable_get $master_integrations_get_endpoint
}
