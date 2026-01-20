# Backend Dockerfile - Multi-stage build for optimal image size
# This Dockerfile is a placeholder for the backend application

# Stage 1: Build
FROM node:18-alpine AS builder

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy application source
# Note: In actual use, this would copy from the application repository
# COPY . .

# Build application (if TypeScript)
# RUN npm run build

# Stage 2: Production
FROM node:18-alpine

# Install dumb-init for proper signal handling
RUN apk add --no-cache dumb-init

# Set environment to production
ENV NODE_ENV=production

# Run as non-root user for security
USER node

WORKDIR /app

# Copy built application from builder stage
COPY --chown=node:node --from=builder /app/node_modules ./node_modules
# COPY --chown=node:node --from=builder /app/dist ./dist
# COPY --chown=node:node --from=builder /app/package*.json ./

# Expose application port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3000/health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"

# Use dumb-init to handle signals properly
CMD ["dumb-init", "node", "dist/index.js"]
