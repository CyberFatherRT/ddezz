#!/bin/bash

source .env

function log() {
    echo "${@}" >&2
}

function get_ip() {
    local current_ip=$(curl -s ifconfig.me/ip)
    local excluded_ips=(${EXCLUDED_IPS//,/ })

    for ip in ${excluded_ips[@]}; do
        if [[ "${current_ip}" == "${ip}" ]]; then
            log "Your ip \"$current_ip\" in excluded list"
            return 1
        fi
    done

    echo $current_ip
    return 0
}

function get_zone_id() {
    local zone=$1
    local response=

    response=$(
        curl -s -X GET 'https://api.cloudflare.com/client/v4/zones' -H "Authorization: Bearer ${CF_API_TOKEN}" |
            jq -r ".result.[] | select(.name == \"${zone}\") | .id"
    )

    log Get zone_id for $zone - $response

    echo $response
    return 0
}

function get_dns_ids() {
    local zone_id=$1
    local dns_names=(${DOMAINS//,/ })
    local reponse=
    declare -a dns_record_ids=()

    response=$(curl -s -X GET https://api.cloudflare.com/client/v4/zones/"${1}"/dns_records -H "Authorization: Bearer ${CF_API_TOKEN}")

    for dns_name in "${dns_names[@]}"; do
        local dns_record=$(echo "${response}" | jq ".result.[] | select(.name == \"${dns_name}\") | .id" -r)

        log Get dns_record_id for ${dns_name} - ${dns_record}

        dns_record_ids+=($dns_record)
    done

    echo ${dns_record_ids[@]}
    return 0
}

function set_A_record() {
    local ip="${1}"
    local zone_id="${2}"
    local dns_record_id="${3}"

    echo
    log Setting A record for $dns_record_id to $ip...

    local response=$(curl -s "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records/${dns_record_id}" \
        -X PATCH \
        -H 'Content-Type: application/json' \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -d "{
                \"content\": \"${ip}\",
                \"type\": \"A\"
            }")

    echo $response | jq -e '.success == true'

    if [[ $? -eq 0 ]]; then
        log Success
        log
    else
        log Failed
        log Reason - $response
    fi

    return 0
}

IP=$(get_ip)
if [[ $? -eq 1 ]]; then exit; fi

zone_id=$(get_zone_id $ZONE)
dns_record_ids=($(get_dns_ids $zone_id))

for dns_record in "${dns_record_ids[@]}"; do

    set_A_record $IP $zone_id $dns_record
done
