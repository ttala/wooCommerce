#!/bin/bash
set -e

WP_PATH=/var/www/html

# --- WAIT FOR MYSQL ---
echo "Waiting for MySQL at $WORDPRESS_DB_HOST:$WORDPRESS_DB_PORT..."

while ! nc -z "$WORDPRESS_DB_HOST" "${WORDPRESS_DB_PORT:-3306}"; do
    sleep 2
done

echo "MySQL is ready!"

# Ensure WordPress files exist
if [ ! -f $WP_PATH/wp-settings.php ]; then
    echo "WordPress files not found — copying from image..."
    cp -R /usr/src/wordpress/* $WP_PATH/
    chown -R www-data:www-data $WP_PATH
fi

# Create config
if [ ! -f $WP_PATH/wp-config.php ]; then
    echo "Creating wp-config.php..."
    wp config create \
        --path=$WP_PATH \
        --dbname="$WORDPRESS_DB_NAME" \
        --dbuser="$WORDPRESS_DB_USER" \
        --dbpass="$WORDPRESS_DB_PASSWORD" \
        --dbhost="$WORDPRESS_DB_HOST" \
        --allow-root
fi

# Install WP
if ! wp core is-installed --allow-root --path=$WP_PATH; then
    wp core install \
        --path=$WP_PATH \
        --url="$WORDPRESS_URL" \
        --title="My WP" \
        --admin_user="$WORDPRESS_ADMIN_USER" \
        --admin_password="$WORDPRESS_ADMIN_PASSWORD" \
        --admin_email="$WORDPRESS_ADMIN_EMAIL" \
        --skip-email \
        --allow-root
fi

# Install and activate WooCommerce
if ! wp plugin is-installed woocommerce --allow-root --path=$WP_PATH; then
    wp plugin install woocommerce --activate --allow-root --path=$WP_PATH
fi

exec "$@"

