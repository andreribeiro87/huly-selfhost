#!/usr/bin/env bash

# Source configuration file (.env first, then huly_v7.conf)
if [ -f ".env" ]; then
    source ".env"
elif [ -f "huly_v7.conf" ]; then
    source "huly_v7.conf"
fi

RECREATE=false
NO_PROMPT=false

for arg in "$@"; do
    case $arg in
        --recreate)
            RECREATE=true
            ;;
        --no-prompt|-y)
            NO_PROMPT=true
            ;;
    esac
done

# Extract domain/server name from HOST_ADDRESS (strip port if present)
RAW_HOST="${HOST_ADDRESS:-localhost}"
SERVER_NAME=$(echo "$RAW_HOST" | awk -F: '{print $1}')
if [ -z "$SERVER_NAME" ] || [ "$SERVER_NAME" == "0.0.0.0" ]; then
    SERVER_NAME="_"
fi

if [ "$RECREATE" == true ] || [ ! -f "nginx.conf" ]; then
    if [ ! -f ".template.nginx.conf" ]; then
        echo -e "\033[1;31mError: .template.nginx.conf not found!\033[0m"
        exit 1
    fi

    echo "Generating container nginx.conf from template..."

    if [[ -n "$SECURE" ]]; then
        if [[ "$EXTERNAL_SSL" == "true" || "$CLOUDFLARE_TUNNEL" == "true" ]]; then
            echo -e "Configuring containerized Nginx for \033[1;32mCloudflare Tunnel / External SSL\033[0m for ${SERVER_NAME} (HTTP port 80, external HTTPS)..."
            REDIRECT_BLOCK=""
            LISTEN_DIRECTIVE="80"
            SSL_DIRECTIVES=""
        else
            echo -e "Configuring containerized Nginx with \033[1;32mSSL/TLS enabled\033[0m for ${SERVER_NAME}..."

            mkdir -p certs
            if [ ! -f "certs/fullchain.pem" ] || [ ! -f "certs/privkey.pem" ]; then
                echo -e "\033[1;33mNotice: SSL certificates not found in ./certs/.\033[0m"
                echo "Generating temporary self-signed certificate so Nginx container can start..."
                openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                    -keyout certs/privkey.pem \
                    -out certs/fullchain.pem \
                    -subj "/CN=${SERVER_NAME}" >/dev/null 2>&1
                echo -e "\033[1;32mCreated temporary self-signed cert in ./certs/.\033[0m"
                echo "Remember to replace ./certs/fullchain.pem and ./certs/privkey.pem with your trusted certificates."
            fi

            REDIRECT_BLOCK="server {
    listen 80;
    server_name ${SERVER_NAME};
    return 301 https://\$host\$request_uri;
}

"
            LISTEN_DIRECTIVE="443 ssl"
            SSL_DIRECTIVES="    http2 on;
    ssl_certificate /etc/nginx/certs/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
"
        fi
    else
        echo -e "Configuring containerized Nginx in \033[1;34mHTTP mode\033[0m for ${SERVER_NAME}..."
        REDIRECT_BLOCK=""
        LISTEN_DIRECTIVE="80"
        SSL_DIRECTIVES=""
    fi

    # Read template and substitute placeholders
    CONFIG_CONTENT=$(cat .template.nginx.conf)
    CONFIG_CONTENT="${CONFIG_CONTENT/__REDIRECT_BLOCK__/$REDIRECT_BLOCK}"
    CONFIG_CONTENT="${CONFIG_CONTENT/__LISTEN__/$LISTEN_DIRECTIVE}"
    CONFIG_CONTENT="${CONFIG_CONTENT/__SSL_DIRECTIVES__/$SSL_DIRECTIVES}"
    CONFIG_CONTENT="${CONFIG_CONTENT/__SERVER_NAME__/$SERVER_NAME}"

    echo "$CONFIG_CONTENT" > nginx.conf
    echo -e "\033[1;32mnginx.conf generated successfully for containerized deployment.\033[0m"
else
    echo "nginx.conf already exists. Updating server_name..."
    sed -i.bak "s|server_name .*;|server_name ${SERVER_NAME};|" ./nginx.conf
    rm -f ./nginx.conf.bak
    echo "Run with --recreate to regenerate nginx.conf from template."
fi

# Check if nginx container is running and reload it if requested
if command -v docker >/dev/null 2>&1 && docker compose ps --services --filter "status=running" 2>/dev/null | grep -q "^nginx$"; then
    if [ "$NO_PROMPT" == true ]; then
        echo -e "\033[1;32mReloading containerized Nginx...\033[0m"
        docker compose exec nginx nginx -s reload
    else
        read -p "Nginx container is running. Reload Nginx configuration now? (Y/n): " RELOAD_CONTAINER
        case "${RELOAD_CONTAINER:-Y}" in  
            [Yy]* )  
                echo -e "\033[1;32mReloading containerized Nginx...\033[0m"
                docker compose exec nginx nginx -s reload
                ;;
            * )
                echo "Configuration saved. You can reload Nginx later with: docker compose exec nginx nginx -s reload"
                ;;
        esac
    fi
else
    echo "Nginx container is not currently running. It will use this config when started with 'docker compose up -d'."
fi
