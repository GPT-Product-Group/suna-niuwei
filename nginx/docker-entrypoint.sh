#!/bin/sh
# Custom entrypoint for nginx that handles SSL certificate initialization
# This script checks for SSL certificates and creates self-signed ones if needed

DOMAIN="suna.excelmaster.ai"
CERT_PATH="/etc/letsencrypt/live/$DOMAIN"

# Check if certificates exist
if [ ! -f "$CERT_PATH/fullchain.pem" ] || [ ! -f "$CERT_PATH/privkey.pem" ]; then
    echo "SSL certificates not found. Creating temporary self-signed certificate..."

    # Create directory
    mkdir -p "$CERT_PATH"

    # Generate self-signed certificate
    openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
        -keyout "$CERT_PATH/privkey.pem" \
        -out "$CERT_PATH/fullchain.pem" \
        -subj "/CN=$DOMAIN" 2>/dev/null

    echo "Temporary self-signed certificate created at $CERT_PATH"
    echo ""
    echo "IMPORTANT: Run the following command to get a real Let's Encrypt certificate:"
    echo "  docker compose run --rm certbot certonly --webroot -w /var/www/certbot \\"
    echo "    --email your-email@example.com -d $DOMAIN --agree-tos --no-eff-email"
    echo ""
    echo "Then reload nginx:"
    echo "  docker compose exec nginx nginx -s reload"
    echo ""
fi

# Execute the original nginx entrypoint
exec /docker-entrypoint.sh "$@"
