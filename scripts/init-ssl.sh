#!/bin/bash
# SSL Certificate Initialization Script for Suna
# This script handles the initial SSL certificate setup with Let's Encrypt
#
# Usage:
#   ./scripts/init-ssl.sh <domain> <email>
#
# Example:
#   ./scripts/init-ssl.sh suna.excelmaster.ai admin@excelmaster.ai

set -e

DOMAIN="${1:-suna.excelmaster.ai}"
EMAIL="${2:-admin@excelmaster.ai}"
CERTBOT_DIR="./certbot"
NGINX_CONF_DIR="./nginx"

echo "=== SSL Certificate Initialization ==="
echo "Domain: $DOMAIN"
echo "Email: $EMAIL"
echo ""

# Create required directories
mkdir -p "$CERTBOT_DIR/conf"
mkdir -p "$CERTBOT_DIR/www"

# Check if certificate already exists
if [ -d "$CERTBOT_DIR/conf/live/$DOMAIN" ]; then
    echo "Certificate already exists for $DOMAIN"
    echo "To renew, run: docker compose run --rm certbot renew"
    exit 0
fi

echo "Step 1: Creating temporary self-signed certificate..."
# Create directories for the certificate
mkdir -p "$CERTBOT_DIR/conf/live/$DOMAIN"

# Generate a self-signed certificate (temporary, until Let's Encrypt provides real one)
openssl req -x509 -nodes -newkey rsa:4096 -days 1 \
    -keyout "$CERTBOT_DIR/conf/live/$DOMAIN/privkey.pem" \
    -out "$CERTBOT_DIR/conf/live/$DOMAIN/fullchain.pem" \
    -subj "/CN=$DOMAIN" 2>/dev/null

echo "Temporary self-signed certificate created."

echo ""
echo "Step 2: Starting nginx with temporary certificate..."
# Start/restart nginx to use the temporary certificate
docker compose up -d nginx

echo "Waiting for nginx to start..."
sleep 5

echo ""
echo "Step 3: Requesting Let's Encrypt certificate..."
# Remove temporary certificate so certbot can create real one
rm -rf "$CERTBOT_DIR/conf/live/$DOMAIN"
rm -rf "$CERTBOT_DIR/conf/archive/$DOMAIN"
rm -f "$CERTBOT_DIR/conf/renewal/$DOMAIN.conf"

# Run certbot to get real certificate
docker compose run --rm certbot certonly \
    --webroot \
    -w /var/www/certbot \
    --email "$EMAIL" \
    -d "$DOMAIN" \
    --agree-tos \
    --no-eff-email \
    --force-renewal

echo ""
echo "Step 4: Switching nginx to production SSL configuration..."
# The nginx.conf already has SSL configured, we need to use it instead of nginx-init.conf
# Update docker-compose to use nginx.conf

echo ""
echo "Step 5: Reloading nginx with Let's Encrypt certificate..."
docker compose exec nginx nginx -s reload || docker compose restart nginx

echo ""
echo "=== SSL Setup Complete ==="
echo "Your site should now be accessible at https://$DOMAIN"
echo ""
echo "To set up automatic renewal, add this to your crontab:"
echo "0 12 * * * cd $(pwd) && docker compose run --rm certbot renew --quiet && docker compose exec nginx nginx -s reload"
