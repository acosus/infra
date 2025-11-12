# Appendix: Troubleshooting Guide

**Purpose:** Common issues and solutions when implementing services deployment

---

## Quick Diagnostic Commands

```bash
# Check all containers status
docker ps -a

# Check specific service logs
docker logs -f posthog
docker logs -f backend-1
docker logs -f traefik

# Check container health
docker inspect posthog | grep -A 10 Health

# Check networks
docker network ls
docker network inspect backend

# Check if backend can reach service
docker exec backend-1 ping posthog
docker exec backend-1 curl http://posthog:8000

# Check nginx routing (on server)
curl -I https://cybersecurity.neiu.edu/api/services/health

# Check from external
curl https://cybersecurity.neiu.edu/api/services/posthog/
```

---

## Common Issues

### Issue 1: 502 Bad Gateway - Cannot Connect to Service

**Symptoms:**
```json
{
  "error": "Service Unavailable",
  "message": "Cannot connect to PostHog service"
}
```

**Possible Causes:**

#### A. Service Container Not Running

```bash
# Check if PostHog is running
docker ps | grep posthog

# If not running, check why
docker ps -a | grep posthog
docker logs posthog
```

**Solution:**
```bash
# Start the service
docker-compose up -d posthog

# If it keeps crashing, check logs
docker logs posthog
```

#### B. Service Not on Correct Network

```bash
# Check PostHog networks
docker inspect posthog | grep -A 10 Networks

# Should show: "backend" network
```

**Solution:**
```yaml
# In docker-compose.yml
posthog:
  networks:
    - backend  # Add this
```

```bash
# Recreate container
docker-compose up -d --force-recreate posthog
```

#### C. Backend Can't Resolve Service Hostname

```bash
# Test DNS resolution
docker exec backend-1 ping posthog

# If fails: PING posthog: Name or service not known
```

**Solution:**
```bash
# Check both containers on same network
docker network inspect backend | grep -E "(posthog|backend-1)"

# Both should appear. If not, add to network:
docker network connect backend posthog
```

#### D. Service Port Incorrect

```bash
# Check what port PostHog is listening on
docker exec posthog netstat -tuln | grep LISTEN

# Should show: 0.0.0.0:8000
```

**Solution:**
```typescript
// In services.routes.ts
// Ensure target port matches service port
createProxyMiddleware({
  target: "http://posthog:8000",  // ← Port 8000, not 80
  // ...
})
```

---

### Issue 2: 404 Not Found on /api/services

**Symptoms:**
```
GET /api/services/posthog/
404 Not Found
```

**Possible Causes:**

#### A. Services Router Not Registered

```bash
# Check backend logs
docker logs backend-1 | grep -i services

# Check if route exists
docker exec backend-1 cat /app/dist/app.js | grep services
```

**Solution:**
```typescript
// In backend/src/app.ts
// Ensure this line exists:
app.use("/api/services", servicesRouter);

// Rebuild and redeploy
npm run build
docker build -f Dockerfile.prod -t aiacosus/backend:latest-prod .
docker push aiacosus/backend:latest-prod

// On server
./deploy-service.sh backend latest-prod
```

#### B. Import Statement Missing

```typescript
// backend/src/app.ts
// Check if import exists:
import servicesRouter from "./routes/api/services/services.routes";

// If missing, add it
```

#### C. TypeScript Compilation Error

```bash
# Check for TS errors
cd backend
npm run build

# If errors, fix them and rebuild
```

---

### Issue 3: Service UI Loads but Assets 404

**Symptoms:**
- PostHog page loads but broken styles
- Browser console: 404 on /static/*, /assets/*

**Cause:** Service generating incorrect asset URLs

**Solution:**

#### A. Check SITE_URL Configuration

```yaml
# docker-compose.yml
posthog:
  environment:
    - SITE_URL=https://cybersecurity.neiu.edu/api/services/posthog
    #                                              ^^^^^^^^^^^^^^
    # Must include full path including /api/services
```

#### B. Enable Sub-Path Support

Some services need explicit sub-path config:

```yaml
# Grafana
grafana:
  environment:
    - GF_SERVER_ROOT_URL=https://cybersecurity.neiu.edu/api/services/grafana
    - GF_SERVER_SERVE_FROM_SUB_PATH=true  # ← Important

# PostHog
posthog:
  environment:
    - IS_BEHIND_PROXY=true
    - DISABLE_SECURE_SSL_REDIRECT=true
```

#### C. Path Rewrite Issue

Check if path is being rewritten correctly:

```typescript
// services.routes.ts
createProxyMiddleware({
  target: "http://posthog:8000",
  pathRewrite: {
    "^/api/services/posthog": "",  // ← Removes /api/services/posthog
  },
  // ...
})
```

**Test:**
```
Request:  /api/services/posthog/static/main.js
            ↓ pathRewrite removes ^^^^^^^^^^^^^^^^^^^
Forwarded: /static/main.js (to PostHog)
```

---

### Issue 4: CORS Errors

**Symptoms:**
```
Access to XMLHttpRequest at 'https://cybersecurity.neiu.edu/api/services/posthog/api/event'
has been blocked by CORS policy
```

**Possible Causes:**

#### A. Service CORS Not Configured

```yaml
# docker-compose.yml
posthog:
  environment:
    - CORS_ENABLED=true
    - ALLOWED_HOSTS=cybersecurity.neiu.edu,localhost
```

#### B. Backend CORS Blocking Proxied Responses

```typescript
// backend/src/app.ts
const corsOptionsDelegate = (req, callback) => {
  let corsOptions = {
    credentials: true,
    origin: true,  // Allow all origins for services (adjust as needed)
  };
  callback(null, corsOptions);
};
```

#### C. Proxy Not Forwarding CORS Headers

```typescript
// services.routes.ts
createProxyMiddleware({
  target: "http://posthog:8000",
  changeOrigin: true,  // ← Important for CORS
  onProxyRes: (proxyRes, req, res) => {
    // Forward CORS headers from service
    // (Usually automatic, but can be explicit if needed)
  },
})
```

---

### Issue 5: Traefik Not Discovering Services

**Symptoms:**
- Traefik dashboard shows no routes
- 404 on Traefik-proxied services

**Possible Causes:**

#### A. Service Not Labeled

```bash
# Check if service has Traefik labels
docker inspect posthog | grep -A 20 Labels

# Should show: traefik.enable=true
```

**Solution:**
```yaml
posthog:
  labels:
    - "traefik.enable=true"  # ← Must be true
    - "traefik.http.routers.posthog.rule=PathPrefix(`/posthog`)"
    # ... other labels
```

#### B. Traefik Can't Access Docker Socket

```bash
# Check if Docker socket is mounted
docker inspect traefik | grep -A 5 Mounts

# Should show: /var/run/docker.sock
```

**Solution:**
```yaml
traefik:
  volumes:
    - /var/run/docker.sock:/var/run/docker.sock:ro  # ← Must be mounted
```

#### C. Service Not on Traefik's Network

```bash
# Check what network Traefik is watching
docker logs traefik | grep "provider.docker.network"

# Check if service is on that network
docker inspect posthog | grep Networks
```

**Solution:**
```yaml
posthog:
  networks:
    - services  # ← Must match Traefik's watched network

  labels:
    - "traefik.docker.network=services"  # ← Specify network
```

#### D. Traefik Not Watching Docker

```bash
# Check Traefik config
docker logs traefik | grep "provider.docker"

# Should show: Provider Docker enabled
```

**Solution:**
```yaml
traefik:
  command:
    - "--providers.docker=true"  # ← Enable Docker provider
    - "--providers.docker.exposedbydefault=false"
```

---

### Issue 6: Backend Load Imbalance

**Symptoms:**
- One backend container handles all service traffic
- Other backends idle

**Cause:** Nginx load balancing not distributing evenly

**Check:**
```bash
# Count service proxy requests per backend
docker logs backend-1 | grep "Services Proxy" | wc -l
docker logs backend-2 | grep "Services Proxy" | wc -l
docker logs backend-3 | grep "Services Proxy" | wc -l
```

**Solution:**

#### A. Check Nginx Upstream Algorithm

```nginx
# In /etc/nginx/conf.d/acosus.conf
upstream backend_servers {
    least_conn;  # ← Good for proxy workloads
    # or: ip_hash;  ← Sticky sessions (less balanced)
    server 127.0.0.1:3001;
    server 127.0.0.1:3002;
    server 127.0.0.1:3003;
}
```

#### B. Check Backend Health

```bash
# One backend might be unhealthy
docker ps | grep backend
# All should show (healthy)

# Check individual health
curl http://localhost:3001/api/v1/health
curl http://localhost:3002/api/v1/health
curl http://localhost:3003/api/v1/health
```

---

### Issue 7: Slow Service Response

**Symptoms:**
- Services take 10+ seconds to respond
- Timeouts

**Possible Causes:**

#### A. Backend Proxy Timeout Too Short

```typescript
// services.routes.ts
createProxyMiddleware({
  target: "http://posthog:8000",
  timeout: 30000,  // ← Increase if needed (30 seconds)
  proxyTimeout: 30000,
  // ...
})
```

#### B. Nginx Proxy Timeout Too Short

```nginx
# In /etc/nginx/conf.d/acosus.conf
location /api {
    proxy_pass http://backend_servers;
    proxy_connect_timeout 60s;   # ← Increase if needed
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
}
```

#### C. Service Container Resource Constrained

```bash
# Check service resource usage
docker stats posthog

# If CPU or memory near limit:
```

```yaml
# docker-compose.yml
posthog:
  deploy:
    resources:
      limits:
        cpus: "4"      # ← Increase
        memory: 4G     # ← Increase
```

#### D. Service Cold Start

First request to service is slow (loading models, warming up):

**Solution:**
```yaml
# docker-compose.yml
posthog:
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:8000/_health"]
    start_period: 60s  # ← Give service time to start
```

---

### Issue 8: Service Data Not Persisting

**Symptoms:**
- Service resets after restart
- Data disappears

**Cause:** Volume not configured or mounted incorrectly

**Check:**
```bash
# Check if volume exists
docker volume ls | grep posthog

# Check if volume is mounted
docker inspect posthog | grep -A 10 Mounts
```

**Solution:**
```yaml
# docker-compose.yml
posthog:
  volumes:
    - posthog-data:/var/lib/postgresql/data  # ← Correct path for PostHog

volumes:
  posthog-data:
    driver: local
```

```bash
# Recreate container with volume
docker-compose down posthog
docker-compose up -d posthog
```

---

### Issue 9: Authentication Errors

**Symptoms:**
```
401 Unauthorized
403 Forbidden
```

**Possible Causes:**

#### A. Cookie Not Being Forwarded

```typescript
// services.routes.ts
createProxyMiddleware({
  target: "http://posthog:8000",
  cookiePathRewrite: "/",  // ← Rewrite cookie path if needed
  // ...
})
```

#### B. CORS Credentials Issue

```typescript
// Backend CORS config
const corsOptions = {
  credentials: true,  // ← Must be true for cookies
  origin: [/* allowed origins */],
};
```

#### C. Service Session Configuration

```yaml
# docker-compose.yml
posthog:
  environment:
    - SESSION_COOKIE_SECURE=false  # ← False for HTTP between nginx and service
    - SESSION_COOKIE_HTTPONLY=true
```

---

## Debugging Workflow

When something doesn't work, follow this sequence:

### 1. Check Service is Running
```bash
docker ps | grep <service>
```

### 2. Check Service Logs
```bash
docker logs <service>
```

### 3. Check Backend Logs
```bash
docker logs backend-1 | grep -i services
```

### 4. Check Network Connectivity
```bash
docker exec backend-1 ping <service>
docker exec backend-1 curl http://<service>:<port>
```

### 5. Check from Browser
```bash
# Open browser DevTools (F12)
# Network tab
# Try accessing service
# Check request/response details
```

### 6. Check Nginx Routing
```bash
# On server
curl -I https://cybersecurity.neiu.edu/api/services/health

# Should return 200 or 404, NOT 502
```

### 7. Enable Debug Logging

```typescript
// services.routes.ts
createProxyMiddleware({
  logLevel: "debug",  // ← Enable debug logs
  // ...
})
```

```bash
# Check logs again
docker logs -f backend-1
```

---

## Getting Help

### Information to Provide

When asking for help, include:

1. **What you're trying to do**
   - Example: "Add PostHog service via backend proxy"

2. **What's happening**
   - Error message, status code, behavior

3. **What you've tried**
   - Steps taken, configurations checked

4. **Relevant logs**
   ```bash
   # Backend logs
   docker logs backend-1 | tail -50

   # Service logs
   docker logs posthog | tail -50

   # Nginx access logs (if accessible)
   tail -50 /var/log/nginx/access.log
   ```

5. **Configuration snippets**
   - Relevant parts of docker-compose.yml
   - Relevant backend code
   - Nginx config (if available)

6. **Environment details**
   - Docker version: `docker --version`
   - Container status: `docker ps -a`
   - Networks: `docker network ls`

---

## Useful Commands Reference

```bash
# === Container Management ===
docker ps                              # Running containers
docker ps -a                           # All containers
docker logs -f <container>             # Follow logs
docker exec <container> <command>      # Run command in container
docker restart <container>             # Restart container
docker-compose up -d <service>         # Start service
docker-compose restart <service>       # Restart service
docker-compose down <service>          # Stop and remove
docker-compose up -d --force-recreate  # Recreate containers

# === Network Debugging ===
docker network ls                      # List networks
docker network inspect <network>       # Inspect network
docker exec <container> ping <host>    # Test connectivity
docker exec <container> curl <url>     # Test HTTP
docker exec <container> netstat -tuln  # Check listening ports

# === Logs and Debugging ===
docker logs <container> | grep <term>  # Search logs
docker logs --since 5m <container>     # Last 5 minutes
docker logs --tail 100 <container>     # Last 100 lines
docker stats                           # Resource usage
docker inspect <container>             # Full container details

# === Volume Management ===
docker volume ls                       # List volumes
docker volume inspect <volume>         # Inspect volume
docker volume prune                    # Remove unused volumes

# === Image Management ===
docker images                          # List images
docker pull <image>                    # Pull image
docker rmi <image>                     # Remove image
docker image prune -a                  # Remove unused images
```

---

**Still stuck?** Double-check:
- Phase 1 implementation steps
- Configuration examples in phase guides
- Network connectivity between containers

**Need more help?** Refer to:
- [Phase 1: Implementation Guide](./phase-1-backend-gateway.md)
- [Phase 3: Traefik](./phase-3-traefik.md) (if using Traefik)
- [Appendix: Security](./appendix-security.md)
