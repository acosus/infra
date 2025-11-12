# Quick Start: Add PostHog in 1 Hour

**Goal:** Get PostHog running at `https://cybersecurity.neiu.edu/api/services/posthog/` in 1-2 hours.

---

## Prerequisites

- [ ] SSH access to `cybersecurity.neiu.edu`
- [ ] Backend code access: `/Users/deep/Dev/research/TS/backend`
- [ ] Docker compose access: `/Users/deep/Dev/research/TS/infra/docker`

---

## Step-by-Step (1 Hour)

### Step 1: Install Dependencies (5 min)

```bash
cd /Users/deep/Dev/research/TS/backend
npm install http-proxy-middleware
npm install --save-dev @types/http-proxy-middleware
```

### Step 2: Create Services Router (10 min)

Create file: `backend/src/routes/api/services/services.routes.ts`

```typescript
import { Router } from "express";
import { createProxyMiddleware } from "http-proxy-middleware";

const router = Router();

router.use(
  "/posthog",
  createProxyMiddleware({
    target: "http://posthog:8000",
    changeOrigin: true,
    pathRewrite: { "^/api/services/posthog": "" },
    logLevel: "debug",
    onProxyReq: (proxyReq, req, res) => {
      console.log(`[Services Proxy] ${req.method} ${req.path} → http://posthog:8000`);
    },
    onError: (err, req, res) => {
      console.error("[Services Proxy] Error:", err.message);
      res.status(502).json({
        error: "Service Unavailable",
        message: "Cannot connect to PostHog service",
      });
    },
  })
);

router.get("/health", (req, res) => {
  res.json({
    status: "ok",
    timestamp: new Date().toISOString(),
    availableServices: ["posthog"],
  });
});

export default router;
```

### Step 3: Update App.ts (5 min)

Edit `backend/src/app.ts`:

**Add import:**
```typescript
import servicesRouter from "./routes/api/services/services.routes";
```

**Add route (after v2 routes):**
```typescript
app.use("/api/v2/admin", adminRouterV2);
app.use("/api/v2/student", studentRouterV2);

// ADD THIS:
app.use("/api/services", servicesRouter);

export { app };
```

### Step 4: Update Docker Compose (10 min)

Edit `infra/docker/docker-compose.yml`, add PostHog service:

```yaml
  # Add at end of services section, before networks:
  posthog:
    image: posthog/posthog:latest
    container_name: posthog
    ports:
      - "8000:8000"
    environment:
      - SECRET_KEY=change-this-in-production
      - SITE_URL=https://cybersecurity.neiu.edu/api/services/posthog
      - DISABLE_SECURE_SSL_REDIRECT=true
      - IS_BEHIND_PROXY=true
      - TRUST_ALL_PROXIES=true
    volumes:
      - posthog-data:/var/lib/postgresql/data
    restart: unless-stopped
    networks:
      - backend
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

# Add at end of volumes section:
volumes:
  model_storage:
    driver: local
  posthog-data:  # ADD THIS
    driver: local
```

### Step 5: Test Locally (10 min)

```bash
# Terminal 1: Start backend
cd backend
npm run dev

# Terminal 2: Start PostHog
cd infra/docker
docker-compose up -d posthog

# Terminal 3: Test
curl http://localhost:3000/api/services/health
# Expected: {"status":"ok",...}

curl http://localhost:3000/api/services/posthog/
# Expected: PostHog HTML
```

### Step 6: Commit and Push (5 min)

```bash
git checkout -b feat/add-posthog-service

git add backend/src/routes/api/services/services.routes.ts
git add backend/src/app.ts
git add backend/package.json
git add backend/package-lock.json
git add infra/docker/docker-compose.yml

git commit -m "Add PostHog service via backend proxy"

git push origin feat/add-posthog-service
```

### Step 7: Deploy Backend (10 min)

```bash
# Build and push
cd backend
npm run build
docker build -f Dockerfile.prod -t aiacosus/backend:latest-prod .
docker push aiacosus/backend:latest-prod

# SSH to server
ssh user@cybersecurity.neiu.edu

# Deploy
cd ~/app/infra/docker
./deploy-service.sh backend latest-prod
```

### Step 8: Deploy PostHog (5 min)

```bash
# On server
cd ~/app/infra/docker

# Update docker-compose.yml (paste PostHog service from Step 4)
nano docker-compose.yml

# Start PostHog
docker-compose up -d posthog

# Verify
docker ps | grep posthog
```

### Step 9: Test Production (5 min)

```bash
# Test health
curl https://cybersecurity.neiu.edu/api/services/health

# Test PostHog
curl https://cybersecurity.neiu.edu/api/services/posthog/

# Open in browser
# https://cybersecurity.neiu.edu/api/services/posthog/
```

---

## Done! ✅

PostHog is now accessible at:
```
https://cybersecurity.neiu.edu/api/services/posthog/
```

---

## Troubleshooting

### Issue: 502 Bad Gateway

**Check PostHog is running:**
```bash
docker ps | grep posthog
docker logs posthog
```

**Check backend can reach PostHog:**
```bash
docker exec backend-1 ping posthog
```

**Solution:**
```bash
# Ensure PostHog on backend network
docker network connect backend posthog
docker restart backend-1
```

### Issue: 404 Not Found

**Check services route registered:**
```bash
docker logs backend-1 | grep -i services
```

**Solution:**
```bash
# Rebuild and redeploy backend
cd backend
npm run build
docker build -f Dockerfile.prod -t aiacosus/backend:latest-prod .
docker push aiacosus/backend:latest-prod

# On server
./deploy-service.sh backend latest-prod
```

---

## Next Steps

- [ ] Setup PostHog account and project
- [ ] Integrate PostHog with frontend
- [ ] Add more services (Grafana, Prometheus)
- [ ] Review security settings

**Full documentation:** See [README.md](./README.md) for comprehensive guides.

---

**Time breakdown:**
- Step 1-4: 30 minutes (coding)
- Step 5: 10 minutes (local testing)
- Step 6-9: 20 minutes (deployment)
- **Total: ~1 hour**
