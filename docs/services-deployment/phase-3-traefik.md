# Phase 3: Traefik Migration (Optional)

**Purpose:** Migrate from Backend Gateway to Traefik for dynamic service routing

**Timeline:** 3-4 hours
**Complexity:** MEDIUM
**When to Use:** You have 5+ services or need dynamic service discovery

---

## Table of Contents

1. [Overview](#overview)
2. [When to Consider Traefik](#when-to-consider-traefik)
3. [Architecture](#architecture)
4. [Implementation](#implementation)
5. [Configuration](#configuration)
6. [Migration from Backend Gateway](#migration-from-backend-gateway)
7. [Pros and Cons](#pros-and-cons)

---

## Overview

### What is Traefik?

Traefik is a modern reverse proxy and load balancer designed for containerized applications. It can:
- **Auto-discover** services via Docker labels
- **Route** based on paths, domains, headers
- **Load balance** across multiple containers
- **Provide monitoring** dashboard

### Hybrid Architecture (Your Approach)

```
User: https://cybersecurity.neiu.edu/api/services/posthog/
    ↓
Host Nginx: /api → backend containers (UNCHANGED)
    ↓
Backend Express: /api/services/* → proxy to Traefik
    ↓
Traefik Container: Route based on path
    ├─ /posthog/* → PostHog
    ├─ /grafana/* → Grafana
    └─ /prometheus/* → Prometheus
```

**Key Insight:** Traefik sits BEHIND backend, not replacing host nginx.

---

## When to Consider Traefik

### ✅ Consider Traefik When:

1. **Many Services (5+)**
   - PostHog, Grafana, Prometheus, Jaeger, Loki, etc.
   - Adding services manually is tedious

2. **Dynamic Service Discovery Needed**
   - Services come and go
   - Auto-scaling containers
   - Want zero-downtime updates

3. **Advanced Routing Requirements**
   - Route by headers (e.g., `X-Service: posthog`)
   - Route by regex patterns
   - A/B testing, canary deployments

4. **Built-in Monitoring Desired**
   - Traefik dashboard shows all routes
   - Built-in metrics (Prometheus format)
   - Health checks

### ❌ Skip Traefik When:

1. **Few Services (2-3)**
   - Backend Gateway is simpler
   - Not worth the complexity

2. **Services Rarely Change**
   - Manual updates are fine
   - No need for auto-discovery

3. **Team Unfamiliar with Traefik**
   - Learning curve
   - Adds operational complexity

4. **Simple Requirements**
   - Just need path-based routing
   - Backend Gateway handles it well

---

## Architecture

### Before (Backend Gateway)

```
backend/src/routes/api/services/services.routes.ts:

router.use("/posthog", proxyToPostHog);
router.use("/grafana", proxyToGrafana);
router.use("/prometheus", proxyToPrometheus);
// ... manually add each service
```

### After (Traefik)

```
backend/src/routes/api/services/services.routes.ts:

router.use("/*", proxyToTraefik);
// Traefik handles all routing
```

```yaml
# docker-compose.yml
posthog:
  labels:
    - "traefik.enable=true"
    - "traefik.http.routers.posthog.rule=PathPrefix(`/posthog`)"
    - "traefik.http.services.posthog.loadbalancer.server.port=8000"
    - "traefik.http.middlewares.posthog-strip.stripprefix.prefixes=/posthog"
    - "traefik.http.routers.posthog.middlewares=posthog-strip"
```

**Result:** Add new service = just add Docker labels, no code changes.

---

## Implementation

### Step 1: Add Traefik to Docker Compose

Edit `infra/docker/docker-compose.yml`:

```yaml
services:
  # ... existing services ...

  traefik:
    image: traefik:v2.11
    container_name: traefik
    command:
      # Enable Docker provider
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--providers.docker.network=services"  # Watch 'services' network

      # Enable dashboard (accessible internally)
      - "--api.dashboard=true"
      - "--api.insecure=true"  # For internal access only

      # Entry points
      - "--entrypoints.web.address=:8080"

      # Logging
      - "--log.level=INFO"
      - "--accesslog=true"
    ports:
      - "127.0.0.1:8080:8080"  # Internal only (via SSH tunnel or backend proxy)
      - "127.0.0.1:8090:8080"  # Dashboard (internal)
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro  # Read Docker events
    networks:
      - backend  # Backend can reach Traefik
      - services  # Traefik can reach services
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: "1"
          memory: 512M
    logging:
      driver: "json-file"
      options:
        max-size: "200m"
        max-file: "10"

  # PostHog with Traefik labels
  posthog:
    image: posthog/posthog:latest
    container_name: posthog
    environment:
      - SECRET_KEY=${POSTHOG_SECRET_KEY}
      - SITE_URL=https://cybersecurity.neiu.edu/api/services/posthog
      - DISABLE_SECURE_SSL_REDIRECT=true
      - IS_BEHIND_PROXY=true
    volumes:
      - posthog-data:/var/lib/postgresql/data
    networks:
      - services  # Traefik can reach PostHog
    restart: unless-stopped
    labels:
      # Enable Traefik for this service
      - "traefik.enable=true"

      # Router configuration
      - "traefik.http.routers.posthog.rule=PathPrefix(`/posthog`)"
      - "traefik.http.routers.posthog.entrypoints=web"

      # Service configuration (which port to use)
      - "traefik.http.services.posthog.loadbalancer.server.port=8000"

      # Middleware: Strip /posthog prefix before forwarding
      - "traefik.http.middlewares.posthog-strip.stripprefix.prefixes=/posthog"
      - "traefik.http.routers.posthog.middlewares=posthog-strip"

      # Network to use
      - "traefik.docker.network=services"

  # Grafana with Traefik labels
  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    environment:
      - GF_SERVER_ROOT_URL=https://cybersecurity.neiu.edu/api/services/grafana
      - GF_SERVER_SERVE_FROM_SUB_PATH=true
    volumes:
      - grafana-data:/var/lib/grafana
    networks:
      - services
    restart: unless-stopped
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.grafana.rule=PathPrefix(`/grafana`)"
      - "traefik.http.routers.grafana.entrypoints=web"
      - "traefik.http.services.grafana.loadbalancer.server.port=3000"
      - "traefik.http.middlewares.grafana-strip.stripprefix.prefixes=/grafana"
      - "traefik.http.routers.grafana.middlewares=grafana-strip"
      - "traefik.docker.network=services"

networks:
  frontend:
  backend:
  ml:
  services:  # NEW: Network for Traefik and services
    driver: bridge

volumes:
  model_storage:
    driver: local
  posthog-data:
    driver: local
  grafana-data:
    driver: local
```

### Step 2: Update Backend to Proxy to Traefik

Replace the entire `backend/src/routes/api/services/services.routes.ts`:

```typescript
import { Router } from "express";
import { createProxyMiddleware } from "http-proxy-middleware";

const router = Router();

/**
 * Traefik Proxy
 *
 * All requests to /api/services/* are forwarded to Traefik.
 * Traefik then routes to the appropriate service based on path.
 *
 * Example flow:
 * 1. User: GET /api/services/posthog/dashboard
 * 2. Backend: Proxy to Traefik at http://traefik:8080/posthog/dashboard
 * 3. Traefik: Routes to PostHog container based on PathPrefix rule
 * 4. PostHog: Receives GET /dashboard (after StripPrefix middleware)
 */
router.use(
  "/*",
  createProxyMiddleware({
    target: "http://traefik:8080",
    changeOrigin: true,
    pathRewrite: {
      "^/api/services": "", // Remove /api/services prefix
    },
    logLevel: "info",
    onProxyReq: (proxyReq, req, res) => {
      console.log(
        `[Traefik Proxy] ${req.method} ${req.path} → http://traefik:8080`
      );
    },
    onError: (err, req, res) => {
      console.error("[Traefik Proxy] Error:", err.message);
      res.status(502).json({
        error: "Service Gateway Unavailable",
        message: "Cannot connect to Traefik service gateway",
        details: err.message,
      });
    },
  })
);

/**
 * Health check
 * GET /api/services/health
 */
router.get("/health", (req, res) => {
  res.json({
    status: "ok",
    timestamp: new Date().toISOString(),
    gateway: "traefik",
    note: "Services are dynamically discovered via Traefik",
  });
});

export default router;
```

### Step 3: Deploy

```bash
# 1. Build and push backend
cd backend
npm run build
docker build -f Dockerfile.prod -t aiacosus/backend:traefik-test .
docker push aiacosus/backend:traefik-test

# 2. SSH to server
ssh user@cybersecurity.neiu.edu

# 3. Update docker-compose.yml with Traefik service
cd ~/app/infra/docker
# ... paste updated docker-compose.yml

# 4. Start Traefik
docker-compose up -d traefik

# 5. Start services (PostHog, Grafana)
docker-compose up -d posthog grafana

# 6. Deploy backend
./deploy-service.sh backend traefik-test

# 7. Verify
docker ps | grep traefik
docker logs traefik
```

### Step 4: Verify Traefik Routes

```bash
# Check Traefik discovered services
docker logs traefik | grep -i "router"

# Expected output:
# Router posthog@docker: rule=PathPrefix(`/posthog`)
# Router grafana@docker: rule=PathPrefix(`/grafana`)
```

Test access:

```bash
# Via backend proxy
curl https://cybersecurity.neiu.edu/api/services/posthog/

# Traefik dashboard (via SSH tunnel)
ssh -L 8090:localhost:8090 user@cybersecurity.neiu.edu
# Open browser: http://localhost:8090
```

---

## Configuration

### Traefik Labels Reference

#### Basic Service Labels

```yaml
labels:
  # Enable Traefik for this service
  - "traefik.enable=true"

  # Router name and rule
  - "traefik.http.routers.<service>.rule=PathPrefix(`/<path>`)"

  # Which entrypoint to use
  - "traefik.http.routers.<service>.entrypoints=web"

  # Which port the service listens on
  - "traefik.http.services.<service>.loadbalancer.server.port=<port>"
```

#### Strip Prefix Middleware

```yaml
labels:
  # Define middleware to strip path prefix
  - "traefik.http.middlewares.<service>-strip.stripprefix.prefixes=/<path>"

  # Apply middleware to router
  - "traefik.http.routers.<service>.middlewares=<service>-strip"
```

#### Example: Add Prometheus

```yaml
prometheus:
  image: prom/prometheus:latest
  container_name: prometheus
  networks:
    - services
  labels:
    - "traefik.enable=true"
    - "traefik.http.routers.prometheus.rule=PathPrefix(`/prometheus`)"
    - "traefik.http.routers.prometheus.entrypoints=web"
    - "traefik.http.services.prometheus.loadbalancer.server.port=9090"
    - "traefik.http.middlewares.prometheus-strip.stripprefix.prefixes=/prometheus"
    - "traefik.http.routers.prometheus.middlewares=prometheus-strip"
    - "traefik.docker.network=services"
```

**Deploy:**

```bash
docker-compose up -d prometheus
# Traefik automatically discovers it
# Access: https://cybersecurity.neiu.edu/api/services/prometheus/
```

### Advanced: Multiple Middlewares

Add authentication + strip prefix:

```yaml
labels:
  # Basic auth middleware
  - "traefik.http.middlewares.admin-auth.basicauth.users=admin:$$apr1$$..."

  # Strip prefix middleware
  - "traefik.http.middlewares.grafana-strip.stripprefix.prefixes=/grafana"

  # Chain middlewares
  - "traefik.http.routers.grafana.middlewares=admin-auth,grafana-strip"
```

### Traefik Dashboard Access

The dashboard shows all routes, services, and health:

**Via SSH Tunnel:**

```bash
ssh -L 8090:localhost:8090 user@cybersecurity.neiu.edu
# Open: http://localhost:8090
```

**Via Backend Proxy (Optional):**

Add to backend routes:

```typescript
// In services.routes.ts
router.use(
  "/traefik",
  authenticateAdmin,  // Require admin auth
  createProxyMiddleware({
    target: "http://traefik:8080",
    pathRewrite: { "^/api/services/traefik": "" },
  })
);
```

Access: `https://cybersecurity.neiu.edu/api/services/traefik/`

---

## Migration from Backend Gateway

### Phase 1: Add Traefik Alongside Backend Gateway

**Step 1:** Add Traefik to docker-compose (as shown above)

**Step 2:** Keep existing backend proxy routes:

```typescript
// services.routes.ts - HYBRID APPROACH

// Existing: Direct proxies (for backwards compatibility)
router.use("/posthog", createProxyMiddleware({ target: "http://posthog:8000", ... }));

// NEW: Traefik proxy for new services
router.use("/grafana", createProxyMiddleware({ target: "http://traefik:8080/grafana", ... }));
router.use("/prometheus", createProxyMiddleware({ target: "http://traefik:8080/prometheus", ... }));
```

**Step 3:** Test new services via Traefik:

```bash
# Existing: PostHog via direct proxy (still works)
curl https://cybersecurity.neiu.edu/api/services/posthog/

# New: Grafana via Traefik
curl https://cybersecurity.neiu.edu/api/services/grafana/
```

### Phase 2: Migrate Existing Services to Traefik

**Step 1:** Add Traefik labels to existing services:

```yaml
posthog:
  # ... existing config ...
  labels:
    - "traefik.enable=true"
    - "traefik.http.routers.posthog.rule=PathPrefix(`/posthog`)"
    # ... other labels
```

**Step 2:** Update backend to route via Traefik:

```typescript
// Remove direct proxy
// router.use("/posthog", createProxyMiddleware({ target: "http://posthog:8000", ... }));

// Now handled by catch-all Traefik proxy
router.use("/*", createProxyMiddleware({ target: "http://traefik:8080", ... }));
```

**Step 3:** Test and verify:

```bash
# Should still work, but now via Traefik
curl https://cybersecurity.neiu.edu/api/services/posthog/

# Check Traefik logs
docker logs traefik | grep posthog
```

### Phase 3: Clean Up

Remove old proxy code:

```typescript
// OLD (DELETE):
// router.use("/posthog", createProxyMiddleware({...}));
// router.use("/grafana", createProxyMiddleware({...}));

// NEW (KEEP):
router.use("/*", createProxyMiddleware({ target: "http://traefik:8080", ... }));
```

---

## Pros and Cons

### Pros

✅ **Dynamic Service Discovery**
- Add service = add Docker labels
- No backend code changes

✅ **Scalability**
- Easy to add many services
- Traefik handles routing logic

✅ **Monitoring**
- Built-in dashboard
- Metrics in Prometheus format

✅ **Flexibility**
- Advanced routing rules
- Middleware system (auth, rate limiting, etc.)

✅ **Load Balancing**
- Automatic load balancing across multiple containers
- Health checks

### Cons

⚠️ **Complexity**
- Learning curve for Traefik
- More moving parts

⚠️ **Extra Hop**
- Request goes: Nginx → Backend → Traefik → Service
- Adds 5-10ms latency

⚠️ **Operational Overhead**
- Another container to monitor
- Traefik-specific troubleshooting

⚠️ **Overkill for Few Services**
- Not worth it for 2-3 services
- Backend Gateway is simpler

---

## Performance Considerations

### Latency

```
Backend Gateway:  Nginx → Backend → Service (2 hops)
Traefik:         Nginx → Backend → Traefik → Service (3 hops)

Additional latency: ~5-10ms
```

**Impact:** Negligible for monitoring/analytics services.

### Resource Usage

Traefik container:
- **CPU:** ~0.1-0.5 cores (idle to moderate load)
- **Memory:** ~128-512 MB
- **Disk:** Minimal

### When Traefik Makes Sense

- **5+ services:** Overhead is justified
- **Frequent changes:** Dynamic discovery saves time
- **Advanced routing:** Need Traefik's features

### When to Stick with Backend Gateway

- **2-3 services:** Simpler is better
- **Stable setup:** Services rarely change
- **Low latency critical:** Every millisecond counts

---

## Troubleshooting

### Issue 1: Traefik Can't Discover Services

**Symptoms:**
- Traefik dashboard shows no routes
- 404 on service URLs

**Causes:**
1. Service not on `services` network
2. Missing `traefik.enable=true` label
3. Traefik not watching correct Docker socket

**Solutions:**

```bash
# Check Traefik can access Docker
docker exec traefik ls /var/run/docker.sock
# Should exist

# Check service has labels
docker inspect posthog | grep -A 10 Labels

# Check service network
docker inspect posthog | grep Networks -A 5
# Should include 'services' network

# Restart Traefik to rediscover
docker restart traefik
```

### Issue 2: Service Returns 404

**Symptoms:**
- Traefik dashboard shows route
- But accessing service returns 404

**Cause:**
- Path prefix not stripped correctly
- Service expects different path

**Solutions:**

```yaml
# Add StripPrefix middleware
labels:
  - "traefik.http.middlewares.posthog-strip.stripprefix.prefixes=/posthog"
  - "traefik.http.routers.posthog.middlewares=posthog-strip"

# Verify in Traefik dashboard
# Open: http://localhost:8090
# Check: HTTP → Middlewares → posthog-strip
```

### Issue 3: Backend Can't Reach Traefik

**Symptoms:**
```
[Traefik Proxy] Error: connect ECONNREFUSED
```

**Causes:**
1. Traefik not running
2. Backend not on same network as Traefik

**Solutions:**

```bash
# Check Traefik running
docker ps | grep traefik

# Check backend can reach Traefik
docker exec backend-1 ping traefik

# Check networks
docker network inspect backend
docker network inspect services

# Backend should be on 'backend' network
# Traefik should be on 'backend' and 'services' networks
```

---

## Summary

### When to Use Traefik

✅ **Use Traefik if:**
- You have 5+ services
- Services change frequently
- You want dynamic discovery
- You need advanced routing

❌ **Skip Traefik if:**
- You have 2-3 services
- Services are stable
- Backend Gateway works fine
- Team unfamiliar with Traefik

### Migration Path

```
Week 1: Backend Gateway (Phase 1)
  ↓
Month 1-2: Monitor and evaluate
  ↓
Month 3: If you have 5+ services → Consider Traefik
  ↓
Week 1: Add Traefik alongside Backend Gateway
Week 2: Migrate services to Traefik one by one
Week 3: Clean up old proxy code
```

### Key Takeaways

1. **Traefik is powerful but adds complexity**
2. **Only migrate if Backend Gateway isn't sufficient**
3. **Hybrid approach allows gradual migration**
4. **Dashboard provides excellent visibility**

---

**Need optimization?** → See [Phase 4: Production Optimization](./phase-4-optimization.md)

**Having issues?** → See [Appendix: Troubleshooting](./appendix-troubleshooting.md)
