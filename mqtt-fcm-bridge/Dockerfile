# Use official Node.js LTS
FROM node:20-slim

# Create app directory
WORKDIR /usr/src/app

# Copy package files first for better caching
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy rest of the app
COPY . .

# Ensure the port is available
ENV HTTP_PORT=3000
EXPOSE 3000

# Start the bridge
CMD [ "node", "mqtt-to-fcm.js" ]
