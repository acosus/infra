# Phase 1: Backend API Gateway Implementation

**Objective:** Add PostHog analytics service accessible via `https://cybersecurity.neiu.edu/api/services/posthog/*`

**Timeline:** 1-2 hours
**Risk Level:** LOW (zero nginx changes, easy rollback)

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Step 1: Install Dependencies](#step-1-install-dependencies)
4. [Step 2: Create Services Proxy Router](#step-2-create-services-proxy-router)
5. [Step 3: Update App Configuration](#step-3-update-app-configuration)
6. [Step 4: Update Docker Compose](#step-4-update-docker-compose)
7. [Step 5: Local Testing](#step-5-local-testing)
8. [Step 6: Deploy to Production](#step-6-deploy-to-production)
9. [Step 7: Validation](#step-7-validation)
10. [Troubleshooting](#troubleshooting)
11. [Rollback Procedure](#rollback-procedure)
12. [Adding More Services](#adding-more-services)

---

## Overview

### What We're Building

```
User Request: https://cybersecurity.neiu.edu/api/services/posthog/
                    ↓
Host Nginx: /api → backend containers (EXISTING - NO CHANGES)
                    ↓
Backend Express: /api/services/* → NEW PROXY ROUTE
                    ↓ (Docker network: backend)
PostHog Container: http://posthog:8000
```

### Changes Required

1. **Backend Code:**
   - Install `http-proxy-middleware` package
   - Create new router: `services.routes.ts`
   - Add route to `app.ts`

2. **Docker Compose:**
   - Add PostHog service
   - Configure networks
   - Set environment variables

3. **No Changes Needed:**
   - ❌ Host nginx config
   - ❌ Frontend code
   - ❌ Existing backend routes
   - ❌ Firewall rules

---

## Prerequisites

Before starting, ensure you have:

- [x] SSH access to `cybersecurity.neiu.edu`
- [x] Git repo cloned locally: `/Users/deep/Dev/research/TS`
- [x] Node.js installed locally (for testing)
- [x] Docker installed locally (for testing)
- [x] Access to backend codebase: `backend/`
- [x] Access to docker-compose: `infra/docker/docker-compose.yml`
- [x] GitHub repository access for deployment

---

## Step 1: Install Dependencies

### 1.1 Add http-proxy-middleware Package

Navigate to backend directory and install:

```bash
cd /Users/deep/Dev/research/TS/backend
npm install http-proxy-middleware
npm install --save-dev @types/http-proxy-middleware
```

### 1.2 Verify Installation

Check `package.json`:

```json
{
  "dependencies": {
    "http-proxy-middleware": "^2.0.6",
    // ... other dependencies
  },
  "devDependencies": {
    "@types/http-proxy-middleware": "^1.0.0",
    // ... other dev dependencies
  }
}
```

---

## Step 2: Create Services Proxy Router

### 2.1 Create New Router File

Create file: `backend/src/routes/api/services/services.routes.ts`

```typescript
import { Router } from "express";
import { createProxyMiddleware } from "http-proxy-middleware";

const router = Router();

/**
 * PostHog Analytics Proxy
 * Routes: /api/services/posthog/*
 * Target: http://posthog:8000 (PostHog container)
 */
router.use(
  "/posthog",
  createProxyMiddleware({
    target: "http://posthog:8000",
    changeOrigin: true,
    pathRewrite: {
      "^/api/services/posthog": "", // Remove /api/services/posthog prefix
    },
    logLevel: "debug", // Enable debug logging
    onProxyReq: (proxyReq, req, res) => {
      // Log proxied requests for debugging
      console.log(
        `[Services Proxy] ${req.method} ${req.path} → http://posthog:8000`
      );
    },
    onError: (err, req, res) => {
      console.error("[Services Proxy] Error:", err.message);
      res.status(502).json({
        error: "Service Unavailable",
        message: "Cannot connect to PostHog service",
        details: err.message,
      });
    },
  })
);

/**
 * Health check for services proxy
 * GET /api/services/health
 */
router.get("/health", (req, res) => {
  res.json({
    status: "ok",
    timestamp: new Date().toISOString(),
    availableServices: ["posthog"],
  });
});

export default router;
```

### 2.2 Understanding the Configuration

| Option | Purpose |
|--------|---------|
| `target` | PostHog container URL (via Docker network) |
| `changeOrigin` | Changes Host header to match target |
| `pathRewrite` | Removes `/api/services/posthog` prefix before forwarding |
| `logLevel: "debug"` | Enables detailed logging (remove in production) |
| `onProxyReq` | Logs each proxied request |
| `onError` | Handles connection errors gracefully |

### 2.3 Path Rewriting Example

```
User Request:    /api/services/posthog/dashboard
                            ↓
Backend Receives: /api/services/posthog/dashboard
                            ↓
Path Rewrite:    Remove /api/services/posthog
                            ↓
PostHog Gets:    /dashboard
```

---

## Step 3: Update App Configuration

### 3.1 Modify `backend/src/app.ts`

Add import at the top (after existing imports):

```typescript
// Existing imports
import adminRouterV2 from "./routes/api/v2/admin";
import studentRouterV2 from "./routes/api/v2/student";

// ADD THIS: Import services router
import servicesRouter from "./routes/api/services/services.routes";
```

Add route **AFTER** existing v2 routes (around line 176):

```typescript
// V2 API Routes
app.use("/api/v2/admin", adminRouterV2);
app.use("/api/v2/student", studentRouterV2);

// ADD THIS: Services proxy routes
app.use("/api/services", servicesRouter);
// https://cybersecurity.neiu.edu/api/services/posthog
// https://cybersecurity.neiu.edu/api/services/grafana (future)

export { app };
```

### 3.2 Complete app.ts Context

Your routes section should look like this:

```typescript
// Health check routes (should be early in route chain)
app.use("/api/v1/health", healthRouter);

// V1 API Routes
app.use("/api/v1", publicRouter);
app.use("/api/v1/account", accountRouter);
app.use("/api/v1/student", studentRouter);
app.use("/api/v1/admin", adminRouter);
app.use("/api/v1/advisor", advisorRouter);

// V2 API Routes
app.use("/api/v2/admin", adminRouterV2);
app.use("/api/v2/student", studentRouterV2);

// Services Proxy Routes (NEW)
app.use("/api/services", servicesRouter);

export { app };
```

---

## Step 4: Update Docker Compose

### 4.1 Modify `infra/docker/docker-compose.yml`

Add PostHog service **at the end** of the `services:` section (before `networks:`):

```yaml
services:
  # ... existing frontend, backend, model services ...

  # PostHog Analytics Service
  posthog:
    image: posthog/posthog:latest
    container_name: posthog
    ports:
      - "8000:8000"  # Internal access only (for debugging)
    environment:
      - SECRET_KEY=${POSTHOG_SECRET_KEY:-random-secret-key-change-in-production}
      - SITE_URL=https://cybersecurity.neiu.edu/api/services/posthog
      - DISABLE_SECURE_SSL_REDIRECT=true
      - IS_BEHIND_PROXY=true
      - TRUST_ALL_PROXIES=true
    volumes:
      - posthog-data:/var/lib/postgresql/data
    restart: unless-stopped
    networks:
      - backend  # ← Backend containers can reach PostHog
    deploy:
      resources:
        limits:
          cpus: "2"
          memory: 2G
    logging:
      driver: "json-file"
      options:
        max-size: "200m"
        max-file: "10"

networks:
  frontend:
  backend:
  ml:
  # monitoring:  # Uncommented if needed later

volumes:
  model_storage:
    driver: local
  posthog-data:  # ADD THIS: PostHog data volume
    driver: local
  # grafana-data:
  #   driver: local
```

### 4.2 PostHog Environment Variables Explained

| Variable | Purpose |
|----------|---------|
| `SECRET_KEY` | PostHog encryption key (generate unique key for production) |
| `SITE_URL` | Base URL for PostHog (includes proxy path) |
| `DISABLE_SECURE_SSL_REDIRECT` | Allow HTTP between nginx and PostHog |
| `IS_BEHIND_PROXY` | PostHog knows it's behind a proxy |
| `TRUST_ALL_PROXIES` | Trust proxy headers for IP detection |

### 4.3 Generate Secure SECRET_KEY

For production, generate a secure key:

```bash
# On your laptop or server
openssl rand -hex 32
# Output: a1b2c3d4e5f6... (64 characters)
```

Add to your private env repo: `backend/.env`

```bash
POSTHOG_SECRET_KEY=a1b2c3d4e5f6...
```

Update docker-compose reference:

```yaml
environment:
  - SECRET_KEY=${POSTHOG_SECRET_KEY}
```

---

## Step 5: Local Testing

### 5.1 Test Backend Code Locally

Start backend in development mode:

```bash
cd /Users/deep/Dev/research/TS/backend
npm run dev
```

**Expected Output:**
```
[nodemon] starting `ts-node src/index.ts`
Server listening on port 3000
```

### 5.2 Test Services Proxy Locally

#### Option A: With Docker PostHog Running

Start PostHog locally:

```bash
cd /Users/deep/Dev/research/TS/infra/docker

# Create a minimal docker-compose for local testing
docker-compose up -d posthog
```

Test proxy:

```bash
# Health check
curl http://localhost:3000/api/services/health

# Expected:
# {
#   "status": "ok",
#   "timestamp": "2025-11-12T...",
#   "availableServices": ["posthog"]
# }

# PostHog proxy (should return PostHog HTML)
curl http://localhost:3000/api/services/posthog/
```

#### Option B: Mock Testing (Without PostHog)

If PostHog isn't running, you'll get a 502 error:

```bash
curl http://localhost:3000/api/services/posthog/

# Expected (PostHog not running):
# {
#   "error": "Service Unavailable",
#   "message": "Cannot connect to PostHog service",
#   "details": "..."
# }
```

This is **expected behavior** when PostHog isn't running.

### 5.3 Test Full Stack Locally

Start all services:

```bash
cd /Users/deep/Dev/research/TS/infra/docker

# Start all services
docker-compose up -d

# Check all containers running
docker ps
```

Test from browser:
- PostHog: http://localhost:3000/api/services/posthog/
- Health: http://localhost:3000/api/services/health

### 5.4 Check Backend Logs

```bash
# Backend container logs
docker logs backend-1

# Look for:
[Services Proxy] GET /api/services/posthog/ → http://posthog:8000
```

---

## Step 6: Deploy to Production

### 6.1 Commit Changes

```bash
cd /Users/deep/Dev/research/TS

# Create feature branch
git checkout -b feat/add-posthog-service

# Add changes
git add backend/src/routes/api/services/services.routes.ts
git add backend/src/app.ts
git add backend/package.json
git add backend/package-lock.json
git add infra/docker/docker-compose.yml

# Commit
git commit -m "Add PostHog service via backend proxy

- Install http-proxy-middleware
- Create services proxy router at /api/services
- Add PostHog container to docker-compose
- Configure PostHog with backend network
- Add health check endpoint

🤖 Generated with Claude Code"

# Push to GitHub
git push origin feat/add-posthog-service
```

### 6.2 Deploy Backend

**Option A: Manual Deployment (Recommended for first time)**

1. **Build and push backend image:**

```bash
# Trigger GitHub Actions or build manually
# If manual:
cd /Users/deep/Dev/research/TS/backend
docker build -f Dockerfile.prod -t aiacosus/backend:posthog-test .
docker push aiacosus/backend:posthog-test
```

2. **SSH to server and deploy:**

```bash
# SSH to server
ssh user@cybersecurity.neiu.edu

# Navigate to app directory
cd ~/app/infra/docker

# Pull latest docker-compose.yml from your repo
# (or manually update the file with PostHog service)

# Deploy backend with new tag
./deploy-service.sh backend posthog-test

# Deploy PostHog service
docker-compose up -d posthog
```

**Option B: Via GitHub Actions**

Merge to main branch to trigger automatic deployment:

```bash
# Create pull request on GitHub
# Merge feat/add-posthog-service → main
# GitHub Actions will:
# 1. Build backend:latest-prod
# 2. Push to DockerHub
# 3. SSH to server and run deploy-service.sh backend latest-prod
```

### 6.3 Update docker-compose.yml on Server

**Important:** Ensure the server has the updated `docker-compose.yml` with PostHog service.

```bash
# On server: cybersecurity.neiu.edu
cd ~/app/infra/docker

# Option 1: Pull from your infra repo
git pull origin main

# Option 2: Manually add PostHog service
nano docker-compose.yml
# ... add PostHog service as shown in Step 4.1
```

### 6.4 Start PostHog Service

```bash
# On server
cd ~/app/infra/docker

# Start PostHog container
docker-compose up -d posthog

# Verify it's running
docker ps | grep posthog

# Check logs
docker logs posthog
```

### 6.5 Restart Backend Containers

Backend needs to be restarted to load new proxy routes:

```bash
# On server
cd ~/app/infra/docker

# Restart all backend containers
docker-compose restart backend-1 backend-2 backend-3

# OR use deploy script
./deploy-service.sh backend latest-prod
```

---

## Step 7: Validation

### 7.1 Test from Browser

Open browser and navigate to:

**PostHog UI:**
```
https://cybersecurity.neiu.edu/api/services/posthog/
```

**Expected:** PostHog setup wizard or login page

**Health Check:**
```
https://cybersecurity.neiu.edu/api/services/health
```

**Expected:**
```json
{
  "status": "ok",
  "timestamp": "2025-11-12T...",
  "availableServices": ["posthog"]
}
```

### 7.2 Check Backend Logs

```bash
# On server
docker logs -f backend-1

# Look for:
[Services Proxy] GET /api/services/posthog/ → http://posthog:8000
```

### 7.3 Test PostHog Functionality

1. **Access PostHog UI:**
   - Navigate to: `https://cybersecurity.neiu.edu/api/services/posthog/`
   - Complete setup wizard
   - Create admin account

2. **Test PostHog API:**
   ```bash
   curl https://cybersecurity.neiu.edu/api/services/posthog/api/projects/
   ```

3. **Integrate with Frontend:**
   ```javascript
   // In frontend code
   import posthog from 'posthog-js';

   posthog.init('<your-project-key>', {
     api_host: 'https://cybersecurity.neiu.edu/api/services/posthog',
     // ... other config
   });
   ```

### 7.4 Verify Existing APIs Still Work

**Critical:** Ensure v1 and v2 APIs are unaffected:

```bash
# V1 API
curl https://cybersecurity.neiu.edu/api/v1/health
# Expected: {"status":"ok",...}

# V2 API (requires auth)
curl https://cybersecurity.neiu.edu/api/v2/admin/quiz
# Expected: 401 Unauthorized or 200 with data
```

### 7.5 Load Testing (Optional)

Test under load to ensure proxy doesn't impact performance:

```bash
# Install apache bench
# apt-get install apache2-utils (on server)
# brew install httpie (on mac)

# Test PostHog proxy
ab -n 100 -c 10 https://cybersecurity.neiu.edu/api/services/posthog/

# Test existing API
ab -n 100 -c 10 https://cybersecurity.neiu.edu/api/v1/health
```

---

## Troubleshooting

### Issue 1: 502 Bad Gateway on /api/services/posthog

**Symptoms:**
```json
{
  "error": "Service Unavailable",
  "message": "Cannot connect to PostHog service"
}
```

**Causes:**
1. PostHog container not running
2. PostHog not on `backend` network
3. Backend can't resolve `posthog` hostname

**Solutions:**

```bash
# Check PostHog is running
docker ps | grep posthog

# Check PostHog health
docker exec posthog curl http://localhost:8000/

# Check network connectivity
docker exec backend-1 ping posthog

# Check networks
docker inspect posthog | grep Networks -A 10
docker inspect backend-1 | grep Networks -A 10

# Both should show "backend" network
```

**Fix:**
```bash
# Ensure PostHog is on backend network
cd ~/app/infra/docker
docker-compose down posthog
# Edit docker-compose.yml to add networks: - backend
docker-compose up -d posthog
```

### Issue 2: PostHog UI Loads but Assets 404

**Symptoms:**
- PostHog page loads but no styles/scripts
- Browser console shows 404 errors

**Cause:**
- PostHog generating incorrect asset URLs
- `SITE_URL` environment variable incorrect

**Solution:**

```bash
# Check PostHog environment
docker exec posthog env | grep SITE_URL

# Should be: https://cybersecurity.neiu.edu/api/services/posthog

# If incorrect, update docker-compose.yml
cd ~/app/infra/docker
nano docker-compose.yml

# Update SITE_URL:
environment:
  - SITE_URL=https://cybersecurity.neiu.edu/api/services/posthog

# Recreate container
docker-compose up -d --force-recreate posthog
```

### Issue 3: Backend Doesn't Proxy Requests

**Symptoms:**
- 404 Not Found on `/api/services/posthog`
- Services router not registered

**Causes:**
1. Services router not imported in app.ts
2. TypeScript compilation error
3. Backend container using old image

**Solutions:**

```bash
# Check backend logs for errors
docker logs backend-1 | grep -i error

# Verify services route is registered
docker exec backend-1 cat /app/dist/app.js | grep services

# Rebuild backend image
cd /Users/deep/Dev/research/TS/backend
npm run build
docker build -f Dockerfile.prod -t aiacosus/backend:latest-prod .
docker push aiacosus/backend:latest-prod

# On server: Pull and restart
docker pull aiacosus/backend:latest-prod
docker-compose up -d --force-recreate backend-1 backend-2 backend-3
```

### Issue 4: CORS Errors

**Symptoms:**
- Browser console: "CORS policy blocked"
- PostHog requests fail from frontend

**Cause:**
- PostHog not configured for proxy
- Backend CORS settings blocking PostHog responses

**Solution:**

Update PostHog environment:

```yaml
# In docker-compose.yml
posthog:
  environment:
    - CORS_ENABLED=true
    - ALLOWED_HOSTS=cybersecurity.neiu.edu,localhost
```

Or update backend CORS to allow PostHog responses:

```typescript
// In backend/src/app.ts
const corsOptionsDelegate = function (req, callback) {
  let corsOptions = {
    credentials: true,
    // Allow all origins for services proxy
    origin: req.path.startsWith('/api/services') ? true : checkOrigin(req),
  };
  callback(null, corsOptions);
};
```

### Issue 5: PostHog Data Not Persisting

**Symptoms:**
- PostHog setup resets after container restart
- Users/projects disappear

**Cause:**
- Volume not configured correctly
- PostHog using in-memory database

**Solution:**

```bash
# Check volume exists
docker volume ls | grep posthog

# Check volume is mounted
docker inspect posthog | grep Mounts -A 10

# Should show:
# "Source": "/var/lib/docker/volumes/posthog-data/_data"
# "Destination": "/var/lib/postgresql/data"

# If missing, recreate with volume
docker-compose down posthog
docker volume create posthog-data
docker-compose up -d posthog
```

---

## Rollback Procedure

If something goes wrong, rollback is straightforward:

### Quick Rollback (Stop PostHog Only)

```bash
# On server
cd ~/app/infra/docker

# Stop PostHog
docker-compose stop posthog

# Remove PostHog from startup
# (Comment out in docker-compose.yml or leave stopped)
```

**Impact:**
- PostHog stops working
- Existing APIs (v1, v2) unaffected
- Backend still has proxy code but won't be used

### Full Rollback (Revert Backend Code)

```bash
# On your laptop
cd /Users/deep/Dev/research/TS
git checkout main  # Or previous stable branch

# Rebuild backend without services router
cd backend
npm run build
docker build -f Dockerfile.prod -t aiacosus/backend:rollback .
docker push aiacosus/backend:rollback

# On server
cd ~/app/infra/docker
./deploy-service.sh backend rollback

# Stop and remove PostHog
docker-compose stop posthog
docker-compose rm -f posthog
```

### Verify Rollback

```bash
# Test existing APIs
curl https://cybersecurity.neiu.edu/api/v1/health
curl https://cybersecurity.neiu.edu/api/v2/admin/quiz

# Services route should 404 (expected after rollback)
curl https://cybersecurity.neiu.edu/api/services/health
# Expected: 404 Not Found
```

---

## Adding More Services

Once PostHog is working, adding more services is quick (30 minutes each).

### Example: Add Grafana

**Step 1: Add to services router**

Edit `backend/src/routes/api/services/services.routes.ts`:

```typescript
/**
 * Grafana Monitoring Proxy
 * Routes: /api/services/grafana/*
 * Target: http://grafana:3000 (Grafana container)
 */
router.use(
  "/grafana",
  createProxyMiddleware({
    target: "http://grafana:3000",
    changeOrigin: true,
    pathRewrite: {
      "^/api/services/grafana": "",
    },
    logLevel: "debug",
    onProxyReq: (proxyReq, req, res) => {
      console.log(
        `[Services Proxy] ${req.method} ${req.path} → http://grafana:3000`
      );
    },
  })
);
```

**Step 2: Add to docker-compose**

```yaml
grafana:
  image: grafana/grafana:latest
  container_name: grafana
  ports:
    - "3001:3000"  # Internal access only
  environment:
    - GF_SERVER_ROOT_URL=https://cybersecurity.neiu.edu/api/services/grafana
    - GF_SERVER_SERVE_FROM_SUB_PATH=true
  volumes:
    - grafana-data:/var/lib/grafana
  restart: unless-stopped
  networks:
    - backend
  deploy:
    resources:
      limits:
        cpus: "1"
        memory: 1G

volumes:
  grafana-data:
    driver: local
```

**Step 3: Deploy**

```bash
# Build and deploy backend (to update router)
./deploy-service.sh backend latest-prod

# Start Grafana
docker-compose up -d grafana
```

**Step 4: Access**

```
https://cybersecurity.neiu.edu/api/services/grafana/
```

### Pattern for Any Service

1. **Add proxy route** in `services.routes.ts`
2. **Add service** to `docker-compose.yml`
3. **Configure service** with `SITE_URL` or `ROOT_URL` pointing to proxy path
4. **Deploy backend** (if router changed)
5. **Start service** container
6. **Test** via browser

---

## Performance Considerations

### Proxy Overhead

Each proxied request adds ~5-10ms latency:

```
Direct: Backend → PostHog (1-2ms)
Proxied: Backend → PostHog (5-10ms)
```

**Impact:** Negligible for analytics/monitoring services.

### Load Balancing

All 3 backend containers proxy to PostHog:

```
Load Balancer:
  backend-1 → posthog ✓
  backend-2 → posthog ✓
  backend-3 → posthog ✓
```

PostHog handles 3x backend load, which is fine for most use cases.

### Caching

For performance-critical services, add caching:

```typescript
router.use(
  "/grafana",
  createProxyMiddleware({
    target: "http://grafana:3000",
    // ... other options

    // Add response caching
    onProxyRes: (proxyRes, req, res) => {
      if (req.path.endsWith('.js') || req.path.endsWith('.css')) {
        proxyRes.headers['Cache-Control'] = 'public, max-age=86400';
      }
    },
  })
);
```

---

## Security Considerations

### 1. Authentication

PostHog has its own auth, but you can add backend-level auth:

```typescript
import { authenticateToken } from "../../../middleware/auth";

// Require authentication for PostHog access
router.use("/posthog", authenticateToken, createProxyMiddleware({...}));
```

### 2. Network Isolation

Services are isolated via Docker networks:

- PostHog ONLY accessible from backend containers
- Not exposed to internet directly
- Backend acts as authentication gateway

### 3. Rate Limiting

Add rate limiting to prevent abuse:

```bash
npm install express-rate-limit
```

```typescript
import rateLimit from "express-rate-limit";

const servicesLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 1000, // Limit each IP to 1000 requests per windowMs
  message: "Too many requests to services, please try again later",
});

router.use(servicesLimiter);
```

### 4. Logging and Monitoring

Monitor proxy usage:

```typescript
router.use((req, res, next) => {
  console.log(`[Services Proxy] ${req.method} ${req.path} from ${req.ip}`);
  next();
});
```

---

## Next Steps

### Immediate (After PostHog Works)

- [ ] Remove `logLevel: "debug"` from production
- [ ] Set up PostHog admin account
- [ ] Integrate PostHog with frontend
- [ ] Configure PostHog event tracking

### Short-term (Next Week)

- [ ] Add Grafana for metrics visualization
- [ ] Add Prometheus for metrics collection
- [ ] Set up dashboards for monitoring

### Long-term (Next Month)

- [ ] Evaluate if Traefik migration is needed (5+ services)
- [ ] Request one-time nginx update for cleaner URLs
- [ ] Document service addition process for team

---

## Summary

### What We Accomplished

✅ **Added PostHog** via backend proxy
✅ **Zero nginx changes** - Used existing `/api` route
✅ **Safe deployment** - Easy rollback, no risk to existing APIs
✅ **Scalable pattern** - Can add more services easily

### Key URLs

| Service | URL |
|---------|-----|
| PostHog UI | `https://cybersecurity.neiu.edu/api/services/posthog/` |
| PostHog API | `https://cybersecurity.neiu.edu/api/services/posthog/api/` |
| Health Check | `https://cybersecurity.neiu.edu/api/services/health` |

### Files Changed

- `backend/src/routes/api/services/services.routes.ts` (new)
- `backend/src/app.ts` (added import + route)
- `backend/package.json` (added dependency)
- `infra/docker/docker-compose.yml` (added PostHog service)

---

**Need more services?** Follow the pattern in [Adding More Services](#adding-more-services).

**Having issues?** Check [Troubleshooting](#troubleshooting) or refer to [Appendix: Troubleshooting](./appendix-troubleshooting.md).

**Ready for alternatives?** See [Phase 2: Alternative Solutions](./phase-2-alternatives.md).

**Want Traefik?** See [Phase 3: Traefik Migration](./phase-3-traefik.md).
