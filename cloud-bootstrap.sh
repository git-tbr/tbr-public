#!/bin/bash

GetCloudProvider() {

    if curl -s -m 2 -H "Authorization: Bearer Oracle" http://169.254.169.254/opc/v2/instance/ > /dev/null 2>&1; then
        echo "OCI"
        return 0
    fi

    if curl -s -m 2 -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/instance/id > /dev/null 2>&1; then
        echo "GCP"
        return 0
    fi

    if curl -s -m 2 -H "Metadata: true" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" > /dev/null 2>&1; then
        echo "AZURE"
        return 0
    fi

    local aws_token
    aws_token=$(curl -s -m 2 -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 5" 2>/dev/null)
    if [ -n "$aws_token" ] && curl -s -m 2 -H "X-aws-ec2-metadata-token: $aws_token" http://169.254.169.254/latest/meta-data/instance-id > /dev/null 2>&1; then
        echo "AWS"
        return 0
    fi

    echo "UNKNOWN"
    return 1

}