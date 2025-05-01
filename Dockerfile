# Dockerfile for WordPress
FROM wordpress:latest

# Set environment variables for database connection
ENV WORDPRESS_DB_HOST=your-database-host
ENV WORDPRESS_DB_USER=your-database-user
ENV WORDPRESS_DB_PASSWORD=your-database-password
ENV WORDPRESS_DB_NAME=your-database-name

# Expose port 80 for the WordPress application
EXPOSE 80