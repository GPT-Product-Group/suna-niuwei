#!/bin/sh
# Custom entrypoint for nginx that handles SSL certificate initialization
# This script checks for SSL certificates and uses HTTP-only mode if not available

DOMAIN="suna.excelmaster.ai"
CERT_PATH="/etc/letsencrypt/live/$DOMAIN"
NGINX_CONF="/etc/nginx/nginx.conf"
NGINX_INIT_CONF="/etc/nginx/nginx-init.conf"

# Check if valid certificates exist
if [ -f "$CERT_PATH/fullchain.pem" ] && [ -f "$CERT_PATH/privkey.pem" ]; then
    echo "SSL certificates found. Starting nginx with HTTPS support."
    # Use the full nginx.conf with SSL (already mounted)
else
    echo "==========================================="
    echo "SSL certificates not found!"
    echo "Starting nginx in HTTP-only mode."
    echo "==========================================="
    echo ""
    echo "To get a real Let's Encrypt certificate, run:"
    echo "  docker compose run --rm certbot certonly --webroot -w /var/www/certbot \\"
    echo "    --email your-email@example.com -d $DOMAIN --agree-tos --no-eff-email"
    echo ""
    echo "Then restart nginx:"
    echo "  docker compose restart nginx"
    echo ""
    echo "==========================================="

    # Copy the HTTP-only config to the nginx config location
    if [ -f "$NGINX_INIT_CONF" ]; then
        cp "$NGINX_INIT_CONF" "$NGINX_CONF"
        echo "Using HTTP-only configuration."
    else
        echo "ERROR: nginx-init.conf not found at $NGINX_INIT_CONF"
        exit 1
    fi
fi

# Execute the original nginx entrypoint
exec /docker-entrypoint.sh "$@"
