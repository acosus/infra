# Phase 2: Alternative Solutions

**Purpose:** Document alternative approaches for adding services when Backend Gateway isn't suitable.

---

## Table of Contents

1. [When to Use Alternatives](#when-to-use-alternatives)
2. [Option A: Frontend Nginx Gateway](#option-a-frontend-nginx-gateway)
3. [Option B: SSH Tunnel Access](#option-b-ssh-tunnel-access)
4. [Option C: Port-Based Access](#option-c-port-based-access)
5. [Comparison Matrix](#comparison-matrix)

---

## When to Use Alternatives

### Use Backend Gateway (Phase 1) When:
- ✅ Services need public access
- ✅ Services are HTTP-based
- ✅ You want centralized authentication
- ✅ You need clean integration with existing API

### Use Frontend Nginx Gateway When:
- ✅ Backend is overloaded (too many proxies)
- ✅ Services need to be accessed from frontend directly
- ✅ You want cleaner URL paths (`/posthog` vs `/api/services/posthog`)
- ✅ Services don't require backend authentication

### Use SSH Tunnels When:
- ✅ Services are for internal/admin use only
- ✅ You want maximum security (no public exposure)
- ✅ Users have SSH access to server
- ✅ Services are development/debugging tools

### Use Port-Based Access When:
- ✅ Firewall allows custom ports
- ✅ Services need dedicated URLs
- ✅ You want zero proxy overhead
- ✅ SSL certificates support multiple ports

---

## Option A: Frontend Nginx Gateway

### Architecture

```
User: https://cybersecurity.neiu.edu/posthog/
    ↓
Host Nginx: / → frontend containers (EXISTING)
    ↓
Frontend Container Nginx: /posthog → proxy to PostHog
    ↓
PostHog Container
```

### Implementation

#### Step 1: Update Frontend Nginx Config

Edit `frontend/frontend-nginx.conf`:

```nginx
server {
    listen 80;
    root /usr/share/nginx/html;
    index index.html;

    # Existing: Serve React app
    location / {
        try_files $uri $uri/ /index.html;
    }

    # NEW: PostHog proxy
    location /posthog/ {
        proxy_pass http://posthog:8000/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;

        # Remove /posthog prefix before forwarding
        rewrite ^/posthog/(.*)$ /$1 break;
    }

    # NEW: Grafana proxy
    location /grafana/ {
        proxy_pass http://grafana:3000/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;

        rewrite ^/grafana/(.*)$ /$1 break;
    }

    # Existing: /api proxy (unused in production but kept for compatibility)
    location /api {
        set $upstream_backend backend:3000;
        proxy_pass http://$upstream_backend;
    }
}
```

#### Step 2: Update Docker Networks

Ensure frontend containers can reach service containers:

```yaml
# In docker-compose.yml

services:
  frontend-1:
    networks:
      - frontend
      - backend
      - services  # NEW network for services

  posthog:
    networks:
      - backend
      - services  # Frontend can reach PostHog

networks:
  frontend:
  backend:
  ml:
  services:  # NEW network
```

#### Step 3: Update PostHog Configuration

```yaml
posthog:
  environment:
    - SITE_URL=https://cybersecurity.neiu.edu/posthog
    # ... other config
```

#### Step 4: Rebuild and Deploy Frontend

```bash
# Build frontend with new nginx config
cd frontend
docker build -f Dockerfile.prod -t aiacosus/frontend:services-test .
docker push aiacosus/frontend:services-test

# On server: Deploy
./deploy-service.sh frontend services-test
```

### Pros and Cons

**Pros:**
- ✅ Cleaner URLs (`/posthog` vs `/api/services/posthog`)
- ✅ Frontend can access services directly (no backend hop)
- ✅ Reduces backend load

**Cons:**
- ⚠️ Requires frontend rebuild for each new service
- ⚠️ Frontend becomes service gateway (unusual pattern)
- ⚠️ Harder to add authentication (nginx vs Express middleware)
- ⚠️ Can't leverage backend's existing CORS/auth

### When to Use

- Backend is overloaded with proxy traffic
- Services are primarily accessed from frontend (analytics, monitoring dashboards)
- You prefer path-based routing at root level

---

## Option B: SSH Tunnel Access

### Architecture

```
Your Laptop
    ↓ SSH Tunnel
Server: localhost:9000
    ↓
PostHog Container: posthog:8000
```

### Implementation

#### Step 1: Expose Service on Localhost Only

```yaml
# In docker-compose.yml
posthog:
  ports:
    - "127.0.0.1:9000:8000"  # Only accessible from server localhost
  # No networks needed beyond internal
```

#### Step 2: Create SSH Tunnel

From your laptop:

```bash
# Forward local port 9000 to server's localhost:9000
ssh -L 9000:localhost:9000 user@cybersecurity.neiu.edu

# Keep terminal open
```

#### Step 3: Access Service Locally

Open browser on your laptop:

```
http://localhost:9000
```

PostHog appears as if running locally, but it's on the server.

### Advanced: Persistent Tunnel

Create SSH config for easy tunneling:

**File:** `~/.ssh/config` (on your laptop)

```ssh
Host cybersecurity-tunnel
    HostName cybersecurity.neiu.edu
    User your-username
    LocalForward 9000 localhost:9000  # PostHog
    LocalForward 9001 localhost:9001  # Grafana
    LocalForward 9002 localhost:9002  # Prometheus
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

**Usage:**

```bash
# Start tunnel
ssh cybersecurity-tunnel

# Access services
# PostHog:     http://localhost:9000
# Grafana:     http://localhost:9001
# Prometheus:  http://localhost:9002
```

### Pros and Cons

**Pros:**
- ✅ Maximum security (not exposed to internet)
- ✅ Zero nginx/proxy changes
- ✅ Simple setup (5 minutes)
- ✅ Works with any service

**Cons:**
- ❌ Only for users with SSH access
- ❌ Not suitable for end-user services
- ❌ Requires tunnel to be active

### When to Use

- **Internal tools:** Grafana, Prometheus, pgAdmin
- **Development:** Testing services before public deployment
- **Debugging:** Access service directly without proxy
- **Admin-only:** Services not needed by regular users

---

## Option C: Port-Based Access

### Architecture

```
User: https://cybersecurity.neiu.edu:9000
    ↓ (Firewall allows port 9000)
PostHog Container: exposed on 9000
```

### Implementation

#### Step 1: Check Firewall Rules

```bash
# On server (requires sudo - ask admin)
sudo firewall-cmd --list-ports

# If port not open:
sudo firewall-cmd --permanent --add-port=9000/tcp
sudo firewall-cmd --reload
```

#### Step 2: Expose Service on Public Port

```yaml
# In docker-compose.yml
posthog:
  ports:
    - "9000:8000"  # Publicly accessible on port 9000
```

#### Step 3: Configure SSL (Optional)

**Option A: Let frontend nginx handle SSL:**

```nginx
# In /etc/nginx/conf.d/acosus.conf (requires admin)
server {
    listen 9000 ssl;
    server_name cybersecurity.neiu.edu;

    ssl_certificate "/etc/pki/nginx/server.crt";
    ssl_certificate_key "/etc/pki/nginx/private/server.key";

    location / {
        proxy_pass http://127.0.0.1:9000;
    }
}
```

**Option B: Use HTTP (less secure):**

Access via: `http://cybersecurity.neiu.edu:9000`

#### Step 4: Test Access

```bash
curl https://cybersecurity.neiu.edu:9000
# Or: http://cybersecurity.neiu.edu:9000
```

### Pros and Cons

**Pros:**
- ✅ Zero proxy overhead
- ✅ Clean separation per service
- ✅ Simple configuration

**Cons:**
- ❌ **Requires firewall changes** (admin access needed)
- ❌ Users must remember ports
- ❌ SSL certificate complexity
- ❌ Likely blocked in your case

### When to Use

- Firewall allows custom ports
- Services have dedicated subdomains
- You control full infrastructure

**Status for Your Setup:** ❌ Likely not viable (firewall restrictions)

---

## Comparison Matrix

| Feature | Backend Gateway | Frontend Gateway | SSH Tunnel | Port-Based |
|---------|----------------|------------------|------------|------------|
| **Nginx Changes** | None | None | None | Required |
| **Firewall Changes** | None | None | None | Required |
| **Public Access** | ✅ Yes | ✅ Yes | ❌ No | ✅ Yes |
| **URL Pattern** | `/api/services/*` | `/*` | `localhost:*` | `:port` |
| **Setup Time** | 1-2 hours | 1-2 hours | 5 minutes | Depends on admin |
| **Add New Service** | 30 min | Frontend rebuild | 1 minute | Depends on admin |
| **Authentication** | ✅ Easy (Express) | ⚠️ Hard (nginx) | ✅ SSH auth | ⚠️ Per-service |
| **SSL** | ✅ Automatic | ✅ Automatic | N/A | Complex |
| **Performance** | +5-10ms | +5-10ms | Direct | Direct |
| **Use Case** | Public services | Public services | Internal tools | Dedicated services |
| **Your Scenario** | ⭐ **BEST** | ✅ Viable | ✅ For admin tools | ❌ Blocked |

---

## Hybrid Approach (Recommended)

### Strategy

Combine multiple approaches based on use case:

#### 1. **Public Services** → Backend Gateway (Phase 1)
- PostHog (if users need analytics)
- Public monitoring dashboards
- API documentation (Swagger)

**URLs:**
```
https://cybersecurity.neiu.edu/api/services/posthog/
https://cybersecurity.neiu.edu/api/services/swagger/
```

#### 2. **Admin Tools** → SSH Tunnels (Option B)
- Grafana (internal metrics)
- Prometheus (internal monitoring)
- pgAdmin (database admin)
- Redis Commander

**Access:**
```bash
ssh -L 9001:localhost:9001 user@cybersecurity.neiu.edu
# http://localhost:9001 → Grafana
```

#### 3. **Future** → Frontend Gateway (Optional)
- Migrate high-traffic services to frontend
- Reduce backend load
- Cleaner URLs

**Migration Path:**
```
Phase 1: Backend Gateway (now)
    ↓
Phase 2: SSH Tunnels for admin (now)
    ↓
Phase 3: Evaluate traffic patterns (3 months)
    ↓
Phase 4: Migrate to Frontend Gateway if needed
```

---

## Implementation Priority

### Week 1 (Current)
✅ **Phase 1:** Backend Gateway for PostHog

### Week 2
✅ **SSH Tunnels:** Setup for Grafana, Prometheus
- Only for admin/dev access
- No code changes needed
- Quick setup (5 minutes per service)

### Month 1
✅ **Evaluate:** Is Backend Gateway working well?
- Monitor backend load
- Check proxy latency
- User feedback

### Month 2+ (If Needed)
🔄 **Migrate to Frontend Gateway** if:
- Backend proxy becomes bottleneck
- Want cleaner URLs
- Services don't need backend auth

---

## Decision Tree

```
Need to add a service?
    ↓
Is it for public access?
    ├─ YES → Is it HTTP-based?
    │           ├─ YES → Backend Gateway (Phase 1)
    │           └─ NO → SSH Tunnel (Option B)
    │
    └─ NO (internal only) → SSH Tunnel (Option B)

Backend Gateway working well?
    ├─ YES → Keep using it
    │
    └─ NO (backend overloaded)
           ↓
        Migrate to Frontend Gateway (Option A)
           OR
        Consider Traefik (Phase 3)
```

---

## Next Steps

- **For public services:** Continue with Backend Gateway (Phase 1)
- **For admin tools:** Setup SSH tunnels (5 min each)
- **For optimization:** Consider Traefik if you need 5+ services (Phase 3)
- **For cleaner URLs:** Request one-time nginx update (Phase 4)

---

**Ready for Traefik?** → See [Phase 3: Traefik Migration](./phase-3-traefik.md)

**Want cleaner URLs?** → See [Phase 4: Production Optimization](./phase-4-optimization.md)
