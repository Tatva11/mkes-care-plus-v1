FROM node:22-bookworm-slim

# Install Chromium, fonts, CA certificates, and runtime dependencies for Puppeteer & whatsapp-web.js
RUN apt-get update && apt-get install -y --no-install-recommends \
    chromium \
    fonts-liberation \
    fonts-freefont-ttf \
    ca-certificates \
    procps \
    && rm -rf /var/lib/apt/lists/*

ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium
ENV WA_SESSION_PATH=/app/wa_session

WORKDIR /app

COPY package*.json ./
RUN npm install --omit=dev

COPY . .

VOLUME ["/app/wa_session"]

CMD ["node", "index.js"]
