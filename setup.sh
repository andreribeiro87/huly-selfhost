#!/usr/bin/env bash
CONFIG_FILE="huly_v7.conf"

# Parse command line arguments
RESET_VOLUMES=false
SECRET=false
QUICK=false
NO_START=false

for arg in "$@"; do
    case $arg in
        --secret)
            SECRET=true
            ;;
        --reset-volumes)
            RESET_VOLUMES=true
            ;;
        --quick)
            QUICK=true
            ;;
        --no-start)
            NO_START=true
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --secret         Generate a new secret key"
            echo "  --reset-volumes  Reset all volume paths to default Docker named volumes"
            echo "  --quick          Quick setup with defaults (localhost:8087, no SSL, auto-start)"
            echo "  --no-start       Generate configuration and nginx.conf without starting containers"
            echo "  --help           Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

if [ "$RESET_VOLUMES" == true ]; then
    echo -e "\033[33m--reset-volumes flag detected: Resetting all volume paths to default Docker named volumes.\033[0m"
    sed -i \
        -e '/^VOLUME_ELASTIC_PATH=/s|=.*|=|' \
        -e '/^VOLUME_FILES_PATH=/s|=.*|=|' \
        -e '/^VOLUME_CR_DATA_PATH=/s|=.*|=|' \
        -e '/^VOLUME_CR_CERTS_PATH=/s|=.*|=|' \
        -e '/^VOLUME_REDPANDA_PATH=/s|=.*|=|' \
        "$CONFIG_FILE"
    exit 0
fi

# Quick mode: use all defaults, skip prompts
if [ "$QUICK" == true ]; then
    echo -e "\033[1;34m🚀 Quick setup mode - using defaults for fast verification\033[0m"
    _HOST_ADDRESS="localhost:8087"
    _HTTP_PORT="8087"
    _HTTPS_PORT=""
    _SECURE=""
    _EXTERNAL_SSL=""
    _VOLUME_ELASTIC_PATH=""
    _VOLUME_FILES_PATH=""
    _VOLUME_CR_DATA_PATH=""
    _VOLUME_CR_CERTS_PATH=""
    _VOLUME_REDPANDA_PATH=""
    _EMAIL_FROM="${EMAIL_FROM}"
    _SMTP_HOST="${SMTP_HOST}"
    _SMTP_PORT="${SMTP_PORT:-587}"
    _SMTP_USERNAME="${SMTP_USERNAME}"
    _SMTP_PASSWORD="${SMTP_PASSWORD}"
    _SMTP_TLS_MODE="${SMTP_TLS_MODE:-upgrade}"
else

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

while true; do
    if [[ -n "$HOST_ADDRESS" ]]; then
        prompt_type="current"
        prompt_value="${HOST_ADDRESS}"
    else
        prompt_type="default"
        prompt_value="localhost"
    fi
    read -p "Enter the host address (domain name or IP) [${prompt_type}: ${prompt_value}]: " input
    _HOST_ADDRESS="${input:-${HOST_ADDRESS:-localhost}}"
    break
done

while true; do
    if [[ -n "$HTTP_PORT" ]]; then
        prompt_type="current"
        prompt_value="${HTTP_PORT}"
    else
        prompt_type="default"
        prompt_value="80"
    fi
    read -p "Enter the port for HTTP [${prompt_type}: ${prompt_value}]: " input
    _HTTP_PORT="${input:-${HTTP_PORT:-80}}"
    if [[ "$_HTTP_PORT" =~ ^[0-9]+$ && "$_HTTP_PORT" -ge 1 && "$_HTTP_PORT" -le 65535 ]]; then
        break
    else
        echo "Invalid port. Please enter a number between 1 and 65535."
    fi
done

if [[ "$_HOST_ADDRESS" == "localhost" || "$_HOST_ADDRESS" == "127.0.0.1" || "$_HOST_ADDRESS" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}:?$ ]]; then
    _HOST_ADDRESS="${_HOST_ADDRESS%:}:${_HTTP_PORT}"
    _SECURE=""
    _EXTERNAL_SSL=""
    _HTTPS_PORT=""
else
    while true; do
        if [[ -n "$SECURE" ]]; then
            prompt_type="current"
            prompt_value="Yes"
        else
            prompt_type="default"
            prompt_value="No"
        fi
        read -p "Will you serve Huly over SSL? (y/n) [${prompt_type}: ${prompt_value}]: " input
        case "${input}" in
            [Yy]* )
                _SECURE="true"
                while true; do
                    if [[ "$EXTERNAL_SSL" == "true" ]]; then
                        ext_prompt="current: Yes"
                    else
                        ext_prompt="default: No"
                    fi
                    read -p "Is SSL terminated by a Cloudflare Tunnel or external proxy (no local certs)? (y/n) [${ext_prompt}]: " ext_input
                    case "${ext_input}" in
                        [Yy]* )
                            _EXTERNAL_SSL="true"
                            _HTTPS_PORT=""
                            break;;
                        [Nn]* )
                            _EXTERNAL_SSL=""
                            _HTTPS_PORT="443"
                            break;;
                        "" )
                            if [[ "$EXTERNAL_SSL" == "true" ]]; then
                                _EXTERNAL_SSL="true"
                                _HTTPS_PORT=""
                            else
                                _EXTERNAL_SSL=""
                                _HTTPS_PORT="443"
                            fi
                            break;;
                        * )
                            echo "Invalid input. Please enter Y or N.";;
                    esac
                done
                break;;
            [Nn]* )
                _SECURE=""
                _EXTERNAL_SSL=""
                _HTTPS_PORT=""
                break;;
            "" )
                _SECURE="${SECURE:+true}"
                _EXTERNAL_SSL="${EXTERNAL_SSL}"
                if [[ -n "$_SECURE" && "$_EXTERNAL_SSL" != "true" ]]; then
                    _HTTPS_PORT="443"
                else
                    _HTTPS_PORT=""
                fi
                break;;
            * )
                echo "Invalid input. Please enter Y or N.";;
        esac
    done
fi

# Volume path configuration
echo -e "\n\033[1;34mDocker Volume Configuration:\033[0m"

    echo "You can specify custom paths for persistent data storage, or leave empty to use default Docker named volumes."
    echo -e "\033[33mTip: To revert from custom paths to default volumes, enter 'default' or just press Enter when prompted.\033[0m"

    # Elasticsearch volume configuration
    if [[ -n "$VOLUME_ELASTIC_PATH" ]]; then
        current_elastic="custom: $VOLUME_ELASTIC_PATH"
    else
        current_elastic="default Docker volume"
    fi
    read -p "Enter custom path for Elasticsearch volume [current: ${current_elastic}]: " input
    if [[ "$input" == "default" ]]; then
        _VOLUME_ELASTIC_PATH=""
    else
        _VOLUME_ELASTIC_PATH="${input:-${VOLUME_ELASTIC_PATH}}"
    fi

    # Files volume configuration
    if [[ -n "$VOLUME_FILES_PATH" ]]; then
        current_files="custom: $VOLUME_FILES_PATH"
    else
        current_files="default Docker volume"
    fi
    read -p "Enter custom path for files volume [current: ${current_files}]: " input
    if [[ "$input" == "default" ]]; then
        _VOLUME_FILES_PATH=""
    else
        _VOLUME_FILES_PATH="${input:-${VOLUME_FILES_PATH}}"
    fi

    # Cockroach data volume configuration
    if [[ -n "$VOLUME_CR_DATA_PATH" ]]; then
        current_cr_data="custom: $VOLUME_CR_DATA_PATH"
    else
        current_cr_data="default Docker volume"
    fi
    read -p "Enter custom path for CR data volume [current: ${current_cr_data}]: " input
    if [[ "$input" == "default" ]]; then
        _VOLUME_CR_DATA_PATH=""
    else
        _VOLUME_CR_DATA_PATH="${input:-${VOLUME_CR_DATA_PATH}}"
    fi

    # Cockroach certs volume configuration
    if [[ -n "$VOLUME_CR_CERTS_PATH" ]]; then
        current_cr_certs="custom: $VOLUME_CR_CERTS_PATH"
    else
        current_cr_certs="default Docker volume"
    fi
    read -p "Enter custom path for CR certs volume [current: ${current_cr_certs}]: " input
    if [[ "$input" == "default" ]]; then
        _VOLUME_CR_CERTS_PATH=""
    else
        _VOLUME_CR_CERTS_PATH="${input:-${VOLUME_CR_CERTS_PATH}}"
    fi

    # Redpanda volume configuration
    if [[ -n "$VOLUME_REDPANDA_PATH" ]]; then
        current_redpanda="custom: $VOLUME_REDPANDA_PATH"
    else
        current_redpanda="default Docker volume"
    fi
    read -p "Enter custom path for Redpanda volume [current: ${current_redpanda}]: " input
    if [[ "$input" == "default" ]]; then
        _VOLUME_REDPANDA_PATH=""
    else
        _VOLUME_REDPANDA_PATH="${input:-${VOLUME_REDPANDA_PATH}}"
    fi

    # SMTP Email Configuration
    echo -e "\n\033[1;34mSMTP Email Configuration:\033[0m"
    echo "Configure an external SMTP server for user invites, signups, and notifications (optional)."
    read -p "Enter SMTP server host (leave empty to skip) [current: ${SMTP_HOST:-none}]: " input
    if [[ "$input" == "none" ]]; then
        _SMTP_HOST=""
    else
        _SMTP_HOST="${input:-${SMTP_HOST}}"
    fi

    if [[ -n "$_SMTP_HOST" ]]; then
        read -p "Enter SMTP port [current: ${SMTP_PORT:-587}]: " input
        _SMTP_PORT="${input:-${SMTP_PORT:-587}}"

        read -p "Enter sender email address (EMAIL_FROM) [current: ${EMAIL_FROM:-noreply@${_HOST_ADDRESS}}]: " input
        _EMAIL_FROM="${input:-${EMAIL_FROM:-noreply@${_HOST_ADDRESS}}}"

        read -p "Enter SMTP username (leave empty if none) [current: ${SMTP_USERNAME:-none}]: " input
        if [[ "$input" == "none" ]]; then
            _SMTP_USERNAME=""
        else
            _SMTP_USERNAME="${input:-${SMTP_USERNAME}}"
        fi

        read -s -p "Enter SMTP password (leave empty to keep current): " input
        echo ""
        if [[ -n "$input" ]]; then
            _SMTP_PASSWORD="$input"
        else
            _SMTP_PASSWORD="${SMTP_PASSWORD}"
        fi

        read -p "Enter SMTP TLS mode (upgrade [STARTTLS], secure [SSL], ignore) [current: ${SMTP_TLS_MODE:-upgrade}]: " input
        _SMTP_TLS_MODE="${input:-${SMTP_TLS_MODE:-upgrade}}"
    else
        _EMAIL_FROM="${EMAIL_FROM}"
        _SMTP_PORT="${SMTP_PORT:-587}"
        _SMTP_USERNAME="${SMTP_USERNAME}"
        _SMTP_PASSWORD="${SMTP_PASSWORD}"
        _SMTP_TLS_MODE="${SMTP_TLS_MODE:-upgrade}"
    fi

fi # End of non-quick mode

if [ ! -f .huly.secret ] || [ "$SECRET" == true ]; then
  openssl rand -hex 32 > .huly.secret
  echo "Secret generated and stored in .huly.secret"
else
  echo -e "\033[33m.huly.secret already exists, not overwriting."
  echo "Run this script with --secret to generate a new secret."
fi

if [ ! -f .cr.secret ]; then
  openssl rand -hex 32 > .cr.secret
  echo "Secret generated and stored in .cr.secret"
fi

if [ ! -f .rp.secret ]; then
  openssl rand -hex 32 > .rp.secret
  echo "Secret generated and stored in .rp.secret"
fi

if [ ! -f .vapid_pub.secret ] || [ ! -f .vapid_priv.secret ] || [ "$SECRET" == true ]; then
  GEN_SCRIPT="const c=require('crypto');const {publicKey:p,privateKey:s}=c.generateKeyPairSync('ec',{namedCurve:'prime256v1'});const u=p.export({format:'jwk'});const r=s.export({format:'jwk'});console.log(Buffer.concat([Buffer.from([4]),Buffer.from(u.x,'base64url'),Buffer.from(u.y,'base64url')]).toString('base64url'));console.log(Buffer.from(r.d,'base64url').toString('base64url'));"
  VAPID_KEYS=""
  if command -v node >/dev/null 2>&1; then
    VAPID_KEYS=$(node -e "$GEN_SCRIPT" 2>/dev/null || true)
  elif command -v docker >/dev/null 2>&1; then
    VAPID_KEYS=$(docker run --rm node:alpine node -e "$GEN_SCRIPT" 2>/dev/null || true)
  fi

  if [ -n "$VAPID_KEYS" ]; then
    echo "$VAPID_KEYS" | sed -n '1p' > .vapid_pub.secret
    echo "$VAPID_KEYS" | sed -n '2p' > .vapid_priv.secret
    chmod 600 .vapid_pub.secret .vapid_priv.secret
    echo "VAPID keys generated and stored in .vapid_pub.secret and .vapid_priv.secret"
  fi
fi

export HOST_ADDRESS=$_HOST_ADDRESS
export SECURE=$_SECURE
export EXTERNAL_SSL=$_EXTERNAL_SSL
export HTTP_PORT=$_HTTP_PORT
export HTTPS_PORT=$_HTTPS_PORT
export HTTP_BIND=$HTTP_BIND
export TITLE=${TITLE:-Huly}
export DEFAULT_LANGUAGE=${DEFAULT_LANGUAGE:-en}
export LAST_NAME_FIRST=${LAST_NAME_FIRST:-true}
export CR_DATABASE=${CR_DATABASE:-defaultdb}
export CR_USERNAME=${CR_USERNAME:-selfhost}
export REDPANDA_ADMIN_USER=${REDPANDA_ADMIN_USER:-superadmin}
export VOLUME_ELASTIC_PATH=$_VOLUME_ELASTIC_PATH
export VOLUME_FILES_PATH=$_VOLUME_FILES_PATH
export VOLUME_CR_DATA_PATH=$_VOLUME_CR_DATA_PATH
export VOLUME_CR_CERTS_PATH=$_VOLUME_CR_CERTS_PATH
export VOLUME_REDPANDA_PATH=$_VOLUME_REDPANDA_PATH
export HULY_SECRET=$(cat .huly.secret)
export COCKROACH_SECRET=$(cat .cr.secret)
export REDPANDA_SECRET=$(cat .rp.secret)
export PUSH_PUBLIC_KEY=$(cat .vapid_pub.secret 2>/dev/null || true)
export PUSH_PRIVATE_KEY=$(cat .vapid_priv.secret 2>/dev/null || true)
export EMAIL_FROM="${_EMAIL_FROM:-${EMAIL_FROM}}"
export SMTP_HOST="${_SMTP_HOST:-${SMTP_HOST}}"
export SMTP_PORT="${_SMTP_PORT:-${SMTP_PORT:-587}}"
export SMTP_USERNAME="${_SMTP_USERNAME:-${SMTP_USERNAME}}"
export SMTP_PASSWORD="${_SMTP_PASSWORD:-${SMTP_PASSWORD}}"
export SMTP_TLS_MODE="${_SMTP_TLS_MODE:-${SMTP_TLS_MODE:-upgrade}}"

envsubst < .template.huly.conf > $CONFIG_FILE
if [ ! -L ".env" ] || [ "$(readlink .env)" != "$CONFIG_FILE" ]; then
    rm -f .env
    cp "$CONFIG_FILE" .env
fi

source "$CONFIG_FILE"
export CR_DB_URL=$CR_DB_URL

echo -e "\n\033[1;34mConfiguration Summary:\033[0m"
echo -e "Host Address: \033[1;32m$_HOST_ADDRESS\033[0m"
echo -e "HTTP Port: \033[1;32m$_HTTP_PORT\033[0m"
if [[ -n "$SECURE" ]]; then
    if [[ "$_EXTERNAL_SSL" == "true" ]]; then
        echo -e "SSL Mode: \033[1;32mCloudflare Tunnel / External Reverse Proxy (HTTP port ${_HTTP_PORT} -> external HTTPS)\033[0m"
    else
        echo -e "SSL Enabled: \033[1;32mYes (Port ${_HTTPS_PORT:-443} in Nginx container)\033[0m"
    fi
else
    echo -e "SSL Enabled: \033[1;31mNo\033[0m"
fi
echo -e "Elasticsearch Volume: \033[1;32m${_VOLUME_ELASTIC_PATH:-Docker named volume}\033[0m"
echo -e "Files Volume: \033[1;32m${_VOLUME_FILES_PATH:-Docker named volume}\033[0m"
echo -e "CockroachDB Volume: \033[1;32m${_VOLUME_CR_DATA_PATH:-Docker named volume}\033[0m"
echo -e "CockroachDB Certs Volume: \033[1;32m${_VOLUME_CR_CERTS_PATH:-Docker named volume}\033[0m"
echo -e "Redpanda Volume: \033[1;32m${_VOLUME_REDPANDA_PATH:-Docker named volume}\033[0m"
if [[ -n "$_SMTP_HOST" ]]; then
    echo -e "SMTP Service: \033[1;32mEnabled (${_SMTP_HOST}:${_SMTP_PORT:-587})\033[0m"
    echo -e "Email Sender: \033[1;32m${_EMAIL_FROM}\033[0m"
else
    echo -e "SMTP Service: \033[1;33mNot configured (disabled)\033[0m"
fi

echo -e "\n\033[1;32mGenerating containerized nginx.conf...\033[0m"
./nginx.sh --recreate --no-prompt

if [ "$NO_START" == true ]; then
    echo -e "\n\033[1;33mSkipping container startup (--no-start specified).\033[0m"
    echo "You can start Huly anytime with: docker compose up -d"
elif [ "$QUICK" == true ]; then
    echo -e "\n\033[1;32mRunning 'docker compose up -d' now...\033[0m"
    docker compose up -d
else
    read -p "Do you want to run 'docker compose up -d' now to start Huly? (Y/n): " RUN_DOCKER
    case "${RUN_DOCKER:-Y}" in
        [Yy]* )
             echo -e "\033[1;32mRunning 'docker compose up -d' now...\033[0m"
             docker compose up -d
             ;;
        [Nn]* )
            echo "You can run 'docker compose up -d' later to start Huly."
            ;;
    esac
fi

echo ""
echo -e "\033[1;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e "\033[1;32m✅ Setup complete!\033[0m"
echo -e "\033[1;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo ""
echo -e "🌐 Access Huly at: \033[1;36mhttp${SECURE:+s}://${_HOST_ADDRESS}\033[0m"
echo ""
echo -e "ℹ️  Reverse proxy runs in the \033[1;33mnginx\033[0m container (no host Nginx required)."
echo -e "⏳ Wait ~60 seconds for all services to initialize..."
echo -e "📊 Check status with: \033[1;33mdocker compose ps\033[0m"
echo -e "📋 View logs with:   \033[1;33mdocker compose logs -f\033[0m"
if [[ -n "$SECURE" && "$_EXTERNAL_SSL" != "true" ]]; then
    echo -e "🔒 SSL Certificates: Place trusted fullchain.pem & privkey.pem in ./certs/"
    echo -e "   Then reload with:  \033[1;33mdocker compose exec nginx nginx -s reload\033[0m"
elif [[ "$_EXTERNAL_SSL" == "true" ]]; then
    echo -e "☁️  Cloudflare Tunnel: Point your tunnel service to \033[1;33mhttp://localhost:${_HTTP_PORT:-80}\033[0m (or http://nginx:80)"
fi
echo ""
