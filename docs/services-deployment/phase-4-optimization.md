# Phase 4: Production Optimization (Optional)

**Purpose:** Request one-time nginx update for cleaner URLs and performance optimizations

**Timeline:** 1-2 weeks (admin approval time) + 1 hour implementation
**Risk:** LOW (just adding one nginx rule)

---

## Table of Contents

1. [Overview](#overview)
2. [The One-Time Nginx Update](#the-one-time-nginx-update)
3. [URL Migration](#url-migration)
4. [Performance Optimizations](#performance-optimizations)
5. [Monitoring and Health Checks](#monitoring-and-health-checks)
6. [Security Hardening](#security-hardening)

---

## Overview

### Current State (After Phase 1)

**URLs:**
```
https://cybersecurity.neiu.edu/api/services/posthog/
https://cybersecurity.neiu.edu/api/services/grafana/
```

**Pros:**
- ✅ Works with existing nginx config
- ✅ No admin approval needed
- ✅ Quick implementation

**Cons:**
- ⚠️ Verbose URLs (`/api/services/*`)
- ⚠️ Services mixed with API routes
- ⚠️ Not semantically clean

### Goal (Phase 4)

**URLs:**
```
https://cybersecurity.neiu.edu/services/posthog/
https://cybersecurity.neiu.edu/services/grafana/
```

**Benefits:**
- ✅ Cleaner, shorter URLs
- ✅ Semantic separation (services vs API)
- ✅ Better UX
- ✅ Easier to remember

---

## The One-Time Nginx Update

### What to Request

Ask your administrator to add **ONE** rule to `/etc/nginx/conf.d/acosus.conf`:

```nginx
# Existing configuration (DO NOT CHANGE)
upstream frontend_servers {
    least_conn;
    server 127.0.0.1:8081;
    server 127.0.0.1:8082;
}

upstream backend_servers {
    least_conn;
    server 127.0.0.1:3001;
    server 127.0.0.1:3002;
    server 127.0.0.1:3003;
}

server {
    listen 443 ssl;
    server_name cybersecurity.neiu.edu;

    # SSL configuration (DO NOT CHANGE)
    ssl_certificate "/etc/pki/nginx/server.crt";
    ssl_certificate_key "/etc/pki/nginx/private/server.key";
    # ... other SSL settings

    # Frontend routing (DO NOT CHANGE)
    location / {
        proxy_pass http://frontend_servers;
        # ... proxy settings
    }

    # API routing (DO NOT CHANGE)
    location /api {
        proxy_pass http://backend_servers;
        # ... proxy settings
    }

    # ====================================================
    # NEW: Services routing (ADD THIS)
    # ====================================================
    location /services {
        proxy_pass http://backend_servers;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;

        # Cookie handling
        proxy_cookie_path / "/; HTTPOnly; Secure; SameSite=None";
        proxy_cookie_domain localhost cybersecurity.neiu.edu;

        # Timeouts
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }
    # ====================================================
}
```

### Justification to Administration

**Email Template:**

```
Subject: Request: Add /services Route to Nginx Config (One-Time)

Hi [Admin Name],

I'd like to request a one-time addition to the nginx configuration for
cybersecurity.neiu.edu. This will enable us to add monitoring and analytics
services without future nginx changes.

**What:** Add a single location block to /etc/nginx/conf.d/acosus.conf
**Why:** Enable self-service addition of monitoring tools (PostHog, Grafana, etc.)
**Impact:** Zero impact on existing routes (/, /api)
**Risk:** LOW - just routing /services to existing backend servers
**Future requests:** None - this enables us to add services independently

The new block routes /services/* to our backend servers (same as /api),
allowing us to proxy to containerized services. This is a standard pattern
for microservices architecture.

Proposed configuration is attached. Can we schedule this update?

Thanks,
[Your Name]
```

### Implementation by Admin

**Steps for Administrator:**

1. **Backup existing config:**
   ```bash
   sudo cp /etc/nginx/conf.d/acosus.conf /etc/nginx/conf.d/acosus.conf.backup
   ```

2. **Add /services location block** (as shown above)

3. **Test configuration:**
   ```bash
   sudo nginx -t
   # Expected: syntax is ok, test is successful
   ```

4. **Reload nginx:**
   ```bash
   sudo systemctl reload nginx
   ```

5. **Verify:**
   ```bash
   curl https://cybersecurity.neiu.edu/services/health
   # Should return 404 (expected - backend doesn't have route yet)
   # NOT 502 (nginx routing works)
   ```

**Downtime:** Zero (nginx reload is instant)

---

## URL Migration

Once nginx is updated, migrate from `/api/services/*` to `/services/*`.

### Step 1: Update Backend Routes

Edit `backend/src/app.ts`:

```typescript
// OLD (keep for backwards compatibility during migration)
app.use("/api/services", servicesRouter);

// NEW (add this)
app.use("/services", servicesRouter);

export { app };
```

**Result:** Both URLs work:
- `https://cybersecurity.neiu.edu/api/services/posthog/` (old)
- `https://cybersecurity.neiu.edu/services/posthog/` (new)

### Step 2: Update Service Configurations

Update services to use new base URL:

```yaml
# docker-compose.yml
posthog:
  environment:
    - SITE_URL=https://cybersecurity.neiu.edu/services/posthog  # Updated

grafana:
  environment:
    - GF_SERVER_ROOT_URL=https://cybersecurity.neiu.edu/services/grafana  # Updated
```

### Step 3: Update Frontend References

If frontend directly accesses services:

```typescript
// OLD
const posthogUrl = '/api/services/posthog';

// NEW
const posthogUrl = '/services/posthog';
```

### Step 4: Announce Migration

**To users/team:**

```
Services are now available at cleaner URLs:

OLD: https://cybersecurity.neiu.edu/api/services/posthog/
NEW: https://cybersecurity.neiu.edu/services/posthog/

Both URLs work during migration period (1 month).
Please update bookmarks to use new URLs.
```

### Step 5: Deprecate Old URLs (After 1 Month)

Remove backwards compatibility:

```typescript
// backend/src/app.ts

// Remove old route
// app.use("/api/services", servicesRouter);

// Keep only new route
app.use("/services", servicesRouter);
```

---

## Performance Optimizations

### 1. Enable Caching in Backend Proxy

For static assets served by services:

```typescript
// services.routes.ts
router.use(
  "/posthog",
  createProxyMiddleware({
    target: "http://posthog:8000",
    // ... other options

    onProxyRes: (proxyRes, req, res) => {
      // Cache static assets
      if (req.path.match(/\.(js|css|png|jpg|jpeg|gif|ico|woff|woff2)$/)) {
        proxyRes.headers['Cache-Control'] = 'public, max-age=86400'; // 1 day
      }

      // Don't cache API responses
      if (req.path.includes('/api/')) {
        proxyRes.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate';
      }
    },
  })
);
```

### 2. Enable Compression

Add compression middleware to backend:

```bash
cd backend
npm install compression
```

```typescript
// backend/src/app.ts
import compression from 'compression';

app.use(compression({
  filter: (req, res) => {
    // Compress responses for services
    if (req.path.startsWith('/services') || req.path.startsWith('/api/services')) {
      return true;
    }
    return compression.filter(req, res);
  },
  level: 6  // Balance between speed and compression ratio
}));
```

### 3. Connection Pooling

Reuse connections to services:

```typescript
// services.routes.ts
import { Agent } from 'http';

const httpAgent = new Agent({
  keepAlive: true,
  maxSockets: 50,
  maxFreeSockets: 10,
  timeout: 60000,
});

router.use(
  "/posthog",
  createProxyMiddleware({
    target: "http://posthog:8000",
    agent: httpAgent,  // Reuse connections
    // ... other options
  })
);
```

### 4. Backend Load Balancing

Nginx already load balances backend containers. Ensure even distribution:

```bash
# On server: Monitor backend load
docker stats backend-1 backend-2 backend-3

# Check request distribution
docker logs backend-1 | grep "Services Proxy" | wc -l
docker logs backend-2 | grep "Services Proxy" | wc -l
docker logs backend-3 | grep "Services Proxy" | wc -l

# Should be roughly equal
```

If uneven, check nginx upstream:

```nginx
upstream backend_servers {
    least_conn;  # Good for proxy workloads
    server 127.0.0.1:3001;
    server 127.0.0.1:3002;
    server 127.0.0.1:3003;
}
```

### 5. Service Container Resources

Optimize resource limits in docker-compose:

```yaml
posthog:
  deploy:
    resources:
      limits:
        cpus: "2"        # Increase if CPU-bound
        memory: 2G       # Increase if memory pressure
      reservations:
        cpus: "0.5"      # Minimum guaranteed
        memory: 512M
```

Monitor and adjust:

```bash
# Watch container resources
docker stats

# If PostHog CPU > 90%, increase CPU limit
# If PostHog memory near limit, increase memory limit
```

---

## Monitoring and Health Checks

### 1. Service Health Checks

Add health checks to docker-compose:

```yaml
posthog:
  # ... existing config
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:8000/_health"]
    interval: 30s
    timeout: 10s
    retries: 3
    start_period: 40s

grafana:
  healthcheck:
    test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:3000/api/health || exit 1"]
    interval: 30s
    timeout: 10s
    retries: 3
```

### 2. Backend Health Check Endpoint

Enhance services health check:

```typescript
// services.routes.ts

/**
 * Comprehensive health check
 * GET /services/health
 */
router.get("/health", async (req, res) => {
  const services = [
    { name: "posthog", url: "http://posthog:8000/_health" },
    { name: "grafana", url: "http://grafana:3000/api/health" },
  ];

  const checks = await Promise.all(
    services.map(async (service) => {
      try {
        const response = await fetch(service.url, { timeout: 5000 });
        return {
          name: service.name,
          status: response.ok ? "healthy" : "unhealthy",
          statusCode: response.status,
        };
      } catch (error) {
        return {
          name: service.name,
          status: "unreachable",
          error: error.message,
        };
      }
    })
  );

  const allHealthy = checks.every((c) => c.status === "healthy");

  res.status(allHealthy ? 200 : 503).json({
    status: allHealthy ? "ok" : "degraded",
    timestamp: new Date().toISOString(),
    services: checks,
  });
});
```

### 3. Prometheus Metrics

Export metrics from backend:

```bash
npm install prom-client
```

```typescript
// backend/src/metrics.ts
import { Registry, Counter, Histogram } from 'prom-client';

const register = new Registry();

// Services proxy requests counter
export const servicesRequestsTotal = new Counter({
  name: 'services_proxy_requests_total',
  help: 'Total number of requests proxied to services',
  labelNames: ['service', 'method', 'status'],
  registers: [register],
});

// Services proxy latency
export const servicesRequestDuration = new Histogram({
  name: 'services_proxy_request_duration_seconds',
  help: 'Duration of service proxy requests in seconds',
  labelNames: ['service', 'method'],
  buckets: [0.001, 0.005, 0.010, 0.050, 0.100, 0.500, 1.000],
  registers: [register],
});

export { register };
```

```typescript
// services.routes.ts
import { servicesRequestsTotal, servicesRequestDuration } from '../metrics';

router.use((req, res, next) => {
  const start = Date.now();

  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    const service = req.path.split('/')[1]; // Extract service name

    servicesRequestsTotal.inc({
      service,
      method: req.method,
      status: res.statusCode,
    });

    servicesRequestDuration.observe(
      { service, method: req.method },
      duration
    );
  });

  next();
});
```

Expose metrics endpoint:

```typescript
// backend/src/app.ts
import { register } from './metrics';

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});
```

### 4. Grafana Dashboard

Create dashboard to monitor services:

**Metrics to track:**
- Request rate per service
- Response time (p50, p95, p99)
- Error rate
- Backend CPU/memory usage
- Service container health

**Example queries (Prometheus):**

```promql
# Request rate
rate(services_proxy_requests_total[5m])

# Average latency
rate(services_proxy_request_duration_seconds_sum[5m])
/
rate(services_proxy_request_duration_seconds_count[5m])

# Error rate
rate(services_proxy_requests_total{status=~"5.."}[5m])
```

---

## Security Hardening

### 1. Rate Limiting per Service

```bash
npm install express-rate-limit
```

```typescript
// services.routes.ts
import rateLimit from 'express-rate-limit';

// Global services rate limit
const servicesLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 1000, // per IP
  message: "Too many requests to services",
  standardHeaders: true,
  legacyHeaders: false,
});

router.use(servicesLimiter);

// Per-service stricter limits (for admin tools)
const adminServicesLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100,
  message: "Too many requests to admin service",
});

router.use("/grafana", adminServicesLimiter);
router.use("/prometheus", adminServicesLimiter);
```

### 2. Authentication Middleware

Require authentication for certain services:

```typescript
// services.routes.ts
import { authenticateToken, requireAdmin } from '../middleware/auth';

// PostHog: Public (analytics collection)
router.use("/posthog", createProxyMiddleware({...}));

// Grafana: Admin only
router.use(
  "/grafana",
  authenticateToken,
  requireAdmin,
  createProxyMiddleware({...})
);

// Prometheus: Admin only
router.use(
  "/prometheus",
  authenticateToken,
  requireAdmin,
  createProxyMiddleware({...})
);
```

### 3. IP Whitelisting (for Admin Tools)

```typescript
// middleware/ipWhitelist.ts
export const adminIPWhitelist = (req, res, next) => {
  const allowedIPs = [
    '127.0.0.1',
    '::1',
    '192.168.1.0/24',  // Campus network
    // Add your IP ranges
  ];

  const clientIP = req.ip || req.connection.remoteAddress;

  if (isIPAllowed(clientIP, allowedIPs)) {
    next();
  } else {
    res.status(403).json({ error: 'Access denied from this IP' });
  }
};

// Apply to admin services
router.use("/grafana", adminIPWhitelist, createProxyMiddleware({...}));
```

### 4. HTTPS Enforcement

Ensure all service configs enforce HTTPS:

```yaml
# docker-compose.yml
posthog:
  environment:
    - SECURE_PROXY_SSL_HEADER=HTTP_X_FORWARDED_PROTO,https
    - IS_BEHIND_PROXY=true

grafana:
  environment:
    - GF_SERVER_PROTOCOL=https
    - GF_SERVER_ENFORCE_DOMAIN=true
```

### 5. Content Security Policy

Add CSP headers for services:

```typescript
// services.routes.ts
router.use((req, res, next) => {
  res.setHeader(
    'Content-Security-Policy',
    "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline';"
  );
  next();
});
```

---

## Summary

### Phase 4 Achievements

After completing Phase 4:

✅ **Cleaner URLs:** `/services/*` instead of `/api/services/*`
✅ **Better Performance:** Caching, compression, connection pooling
✅ **Comprehensive Monitoring:** Health checks, Prometheus metrics, Grafana dashboards
✅ **Security Hardening:** Rate limiting, authentication, IP whitelisting

### URLs After Phase 4

| Service | URL |
|---------|-----|
| PostHog | `https://cybersecurity.neiu.edu/services/posthog/` |
| Grafana | `https://cybersecurity.neiu.edu/services/grafana/` |
| Prometheus | `https://cybersecurity.neiu.edu/services/prometheus/` |
| Health Check | `https://cybersecurity.neiu.edu/services/health` |
| Metrics | `https://cybersecurity.neiu.edu/metrics` |

### Implementation Timeline

| Week | Task | Duration |
|------|------|----------|
| 1 | Request nginx update from admin | - (waiting) |
| 2-3 | Admin schedules and implements update | - (admin work) |
| 4 | Update backend routes (/services) | 30 minutes |
| 4 | Update service configs (SITE_URL) | 30 minutes |
| 5 | Implement performance optimizations | 2 hours |
| 5 | Setup monitoring and health checks | 2 hours |
| 6 | Security hardening | 2 hours |
| 7 | Test and validate | 1 hour |
| 8+ | Deprecate old URLs (/api/services) | 30 minutes |

**Total active work:** ~8 hours (spread over weeks)
**Total calendar time:** 2-3 weeks (mostly waiting for admin)

---

## Next Steps

### Immediate (After Nginx Update)

1. Migrate URLs from `/api/services/*` to `/services/*`
2. Update all service configurations
3. Announce new URLs to users

### Short-term (Week After Migration)

1. Implement performance optimizations
2. Setup monitoring and metrics
3. Create Grafana dashboards

### Long-term (Ongoing)

1. Security hardening
2. Monitor and adjust resource limits
3. Add more services as needed

---

**All phases complete!** You now have a comprehensive guide for adding services without nginx changes, with optional optimization paths.

**Having issues?** → See [Appendix: Troubleshooting](./appendix-troubleshooting.md)

**Security questions?** → See [Appendix: Security](./appendix-security.md)
