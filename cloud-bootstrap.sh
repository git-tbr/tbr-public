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

GetInstanceId() {
    local provider
    provider=$(GetCloudProvider)

    case "$provider" in
        "OCI")
            curl -s -H "Authorization: Bearer Oracle" http://169.254.169.254/opc/v2/instance/ | jq -r '.id'
            ;;
        "AWS")
            local aws_token
            aws_token=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null)
            curl -s -H "X-aws-ec2-metadata-token: $aws_token" http://169.254.169.254/latest/meta-data/instance-id
            ;;
        "GCP")
            curl -s -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/instance/id
            ;;
        "AZURE")
            curl -s -H "Metadata: true" "http://169.254.169.254/metadata/instance/compute/vmId?api-version=2021-02-01&format=text"
            ;;
        *)
            echo "local-vm-$(hostname)"
            ;;
    esac
}

GetSecret() {
    local secret_identifier="$1"
    
    if [ -z "$secret_identifier" ]; then
        echo "Erro: Identificador do segredo não fornecido." >&2
        return 1
    fi

    local provider
    provider=$(GetCloudProvider)

    case "$provider" in
        "OCI")
            oci secrets secret-bundle get \
                --secret-id "$secret_identifier" \
                --auth instance_principal \
                --output json 2>/dev/null | jq -r '.data."secret-bundle-content".content' | base64 --decode
            ;;
        "AWS")
            aws secretsmanager get-secret-value \
                --secret-id "$secret_identifier" \
                --query "SecretString" \
                --output text 2>/dev/null
            ;;
        "GCP")
            gcloud secrets versions access latest \
                --secret="$secret_identifier" 2>/dev/null
            ;;
        "AZURE")
            az keyvault secret show \
                --id "$secret_identifier" \
                --query "value" \
                --output tsv 2>/dev/null
            ;;
        *)
            echo "Erro: Provedor de nuvem desconhecido ou local. Não é possível buscar o segredo." >&2
            return 1
            ;;
    esac
}

GetRegion() {
    local provider
    provider=$(GetCloudProvider)

    case "$provider" in
        "OCI")
            curl -s -H "Authorization: Bearer Oracle" http://169.254.169.254/opc/v2/instance/ | jq -r '.region'
            ;;
        "AWS")
            local aws_token
            aws_token=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null)
            curl -s -H "X-aws-ec2-metadata-token: $aws_token" http://169.254.169.254/latest/meta-data/placement/region
            ;;
        "GCP")
            curl -s -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/instance/zone | sed 's|.*/||' | sed 's/-[a-z]$//'
            ;;
        "AZURE")
            curl -s -H "Metadata: true" "http://169.254.169.254/metadata/instance/compute/location?api-version=2021-02-01&format=text"
            ;;
        *)
            echo "local"
            ;;
    esac
}

GetPrivateIp() {
    local provider
    provider=$(GetCloudProvider)

    case "$provider" in
        "OCI")
            curl -s -H "Authorization: Bearer Oracle" http://169.254.169.254/opc/v2/vnics/ | jq -r '.[0].privateIp'
            ;;
        "AWS")
            local aws_token
            aws_token=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null)
            curl -s -H "X-aws-ec2-metadata-token: $aws_token" http://169.254.169.254/latest/meta-data/local-ipv4
            ;;
        "GCP")
            curl -s -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/ip
            ;;
        "AZURE")
            curl -s -H "Metadata: true" "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/privateIpAddress?api-version=2021-02-01&format=text"
            ;;
        *)
            hostname -I | awk '{print $1}'
            ;;
    esac
}

GetPublicIp() {
    local provider
    provider=$(GetCloudProvider)

    case "$provider" in
        "OCI")
            curl -s -H "Authorization: Bearer Oracle" http://169.254.169.254/opc/v2/vnics/ | jq -r '.[0].publicIp'
            ;;
        "AWS")
            local aws_token
            aws_token=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null)
            curl -s -H "X-aws-ec2-metadata-token: $aws_token" http://169.254.169.254/latest/meta-data/public-ipv4
            ;;
        "GCP")
            curl -s -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip
            ;;
        "AZURE")
            curl -s -H "Metadata: true" "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2021-02-01&format=text"
            ;;
        *)
            curl -s https://ifconfig.me
            ;;
    esac
}

GetInstanceType() {
    local provider
    provider=$(GetCloudProvider)
    case "$provider" in
        "OCI")   curl -s -H "Authorization: Bearer Oracle" http://169.254.169.254/opc/v2/instance/ | jq -r '.shape' ;;
        "AWS")   local t; t=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null); curl -s -H "X-aws-ec2-metadata-token: $t" http://169.254.169.254/latest/meta-data/instance-type ;;
        "GCP")   curl -s -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/instance/machine-type | sed 's|.*/||' ;;
        "AZURE") curl -s -H "Metadata: true" "http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2021-02-01&format=text" ;;
        *)       echo "local" ;;
    esac
}

TuneSystemForHighThroughput() {
    ulimit -n 65535
    cat << "EOF" > /etc/sysctl.d/99-streaming-performance.conf
# Aumenta a quantidade máxima de conexões pendentes na fila
net.core.somaxconn = 1024
# Aumenta os buffers de memória de recepção e envio de pacotes
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
# Habilita o reuso de conexões TCP em estado TIME_WAIT
net.ipv4.tcp_tw_reuse = 1
EOF
    sysctl --system >/dev/null 2>&1
}

GetCloudTags() {
    local provider
    provider=$(GetCloudProvider)

    case "$provider" in
        "OCI")
            curl -s -H "Authorization: Bearer Oracle" http://169.254.169.254/opc/v2/instance/ | jq -r '
                (.freeformTags, (.definedTags | to_entries[].value)) 
                | to_entries[] 
                | "\(.key)=\(.value)"
            ' 2>/dev/null
            ;;
        "AWS")
            local aws_token
            aws_token=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null)
            curl -s -H "X-aws-ec2-metadata-token: $aws_token" http://169.254.169.254/latest/meta-data/tags/instance/ | while read -r tag; do
                local val
                val=$(curl -s -H "X-aws-ec2-metadata-token: $aws_token" "http://169.254.169.254/latest/meta-data/tags/instance/$tag")
                echo "${tag}=${val}"
            done 2>/dev/null
            ;;
        "GCP")
            curl -s -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/instance/attributes/ | while read -r label; do
                local val
                val=$(curl -s -H "Metadata-Flavor: Google" "http://169.254.169.254/computeMetadata/v1/instance/attributes/$label")
                echo "${label}=${val}"
            done 2>/dev/null
            ;;
        "AZURE")
            curl -s -H "Metadata: true" "http://169.254.169.254/metadata/instance/compute/tags?api-version=2021-02-01&format=text" | tr ';' '\n' | tr ':' '=' 2>/dev/null
            ;;
        *)
            echo ""
            ;;
    esac
}
