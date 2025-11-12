# Phase 0: Current State Analysis

**Purpose:** Understand your existing architecture, request flow, and constraints before implementing changes.

---

## Table of Contents

1. [Infrastructure Overview](#infrastructure-overview)
2. [Architecture Layers](#architecture-layers)
3. [Request Flow Analysis](#request-flow-analysis)
4. [Current Deployment Status](#current-deployment-status)
5. [Constraints and Limitations](#constraints-and-limitations)
6. [Why Backend Gateway Solution Works](#why-backend-gateway-solution-works)

---

## Infrastructure Overview

### Server Environment

| Component | Details |
|-----------|---------|
| **Server** | `cybersecurity.neiu.edu` (on-premise campus server) |
| **OS** | Red Hat Enterprise Linux (RHEL) 9 |
| **Web Server** | Nginx (host level) |
| **Containerization** | Docker + Docker Compose |
| **Deployment** | GitHub Actions → Docker images → Server |

### Your Access Permissions

✅ **What You CAN Do:**
- Modify application code (frontend, backend, model)
- Update docker-compose.yml
- Restart Docker containers
- Deploy new Docker images via GitHub Actions
- Add new services to docker-compose

❌ **What You CANNOT Do:**
- Edit `/etc/nginx/nginx.conf` (main nginx config)
- Edit `/etc/nginx/conf.d/acosus.conf` (custom nginx config)
- Modify firewall rules
- Access root-level system configurations

---

## Architecture Layers

### Layer 1: External Access

```
User's Browser
    ↓
https://cybersecurity.neiu.edu
    ↓
DNS Resolution
    ↓
On-Premise Server (Public IP)
```

### Layer 2: Host Nginx (Port 443)

**Configuration Files:**
- `/etc/nginx/nginx.conf` ([prod.conf](../../nginx/prod.conf))
- `/etc/nginx/conf.d/acosus.conf` ([nginx.prod.conf](../../nginx/nginx.prod.conf))

**Upstreams:**
```nginx
upstream frontend_servers {
    least_conn;
    server 127.0.0.1:8081;  # frontend-1
    server 127.0.0.1:8082;  # frontend-2
}

upstream backend_servers {
    least_conn;
    server 127.0.0.1:3001;  # backend-1
    server 127.0.0.1:3002;  # backend-2
    server 127.0.0.1:3003;  # backend-3
}
```

**Routing Rules:**
```nginx
server {
    listen 443 ssl;
    server_name cybersecurity.neiu.edu;

    # SSL termination happens here
    ssl_certificate "/etc/pki/nginx/server.crt";
    ssl_certificate_key "/etc/pki/nginx/private/server.key";

    # Frontend routing
    location / {
        proxy_pass http://frontend_servers;
        # Load balances to 8081 or 8082
    }

    # API routing
    location /api {
        proxy_pass http://backend_servers;
        # Load balances to 3001, 3002, or 3003
    }
}
```

**Key Points:**
- SSL termination at this layer
- Load balancing with `least_conn` algorithm
- ALL `/api/*` requests go to backend containers
- This is the configuration you **cannot modify**

### Layer 3: Docker Containers

**Current Running Containers:**

```bash
# From docker ps output:
CONTAINER       IMAGE                              CREATED       STATUS        PORTS
frontend-1      aiacosus/frontend:latest-prod      7 weeks ago   Up 2 weeks    0.0.0.0:8081->80/tcp
frontend-2      aiacosus/frontend:latest-prod      7 weeks ago   Up 2 weeks    0.0.0.0:8082->80/tcp
backend-1       aiacosus/backend:latest-prod       5 months ago  Up 2 weeks    0.0.0.0:3001->3000/tcp
backend-2       aiacosus/backend:latest-prod       5 months ago  Up 2 weeks    0.0.0.0:3002->3000/tcp
backend-3       aiacosus/backend:latest-prod       5 months ago  Up 2 weeks    0.0.0.0:3003->3000/tcp
model-1         aiacosus/model:latest-prod         6 months ago  Up 2 weeks    0.0.0.0:5051->5051/tcp
model-2         aiacosus/model:latest-prod         6 months ago  Up 2 weeks    0.0.0.0:5052->5051/tcp
model-3         aiacosus/model:latest-prod         6 months ago  Up 2 weeks    0.0.0.0:5053->5051/tcp
```

**Docker Networks:**
```yaml
networks:
  frontend:  # Used by: frontend-1, frontend-2
  backend:   # Used by: frontend-1, frontend-2, backend-1, backend-2, backend-3
  ml:        # Used by: backend-1, backend-2, backend-3, model-1, model-2, model-3
```

**Container Details:**

#### Frontend Containers
- **Purpose:** Serve React application (static files)
- **Technology:** Nginx (Alpine Linux)
- **Ports:** 8081, 8082 → 80 (container)
- **Networks:** `frontend`, `backend`
- **Config:** `frontend-nginx.conf` (inside container)

#### Backend Containers
- **Purpose:** Express.js REST API
- **Technology:** Node.js with 4 worker processes each
- **Ports:** 3001, 3002, 3003 → 3000 (container)
- **Networks:** `backend`, `ml`
- **Routes:**
  - `/api/v1/*` - Version 1 API (current)
  - `/api/v2/*` - Version 2 API (new)

#### Model Containers
- **Purpose:** Python ML inference service
- **Technology:** Flask
- **Ports:** 5051, 5052, 5053 → 5051 (container)
- **Networks:** `ml`, `backend`

### Layer 4: Inter-Container Communication

```
Backend Container (backend-1)
    ↓ (Docker network: ml)
Model Container (model-1)
    ↓
ML Predictions returned
```

Backend calls model via Docker service name:
```javascript
// In backend
const ML_ROOT_URL = process.env.ML_ROOT_URL; // http://model-1:5051
```

---

## Request Flow Analysis

### Static File Request (HTML, JS, CSS)

```
1. Browser Request
   GET https://cybersecurity.neiu.edu/

2. Host Nginx (Layer 2)
   - Matches: location /
   - Action: proxy_pass http://frontend_servers
   - Load balances to: 127.0.0.1:8081 or 127.0.0.1:8082

3. Frontend Container (Layer 3)
   - Container Nginx receives: GET /
   - Matches: location / { try_files $uri $uri/ /index.html; }
   - Serves: /usr/share/nginx/html/index.html

4. Browser Receives
   - index.html with React app
   - Loads assets: /assets/*.js, /assets/*.css
   - Same flow for each asset
```

### API Request (v1 or v2)

```
1. Browser JavaScript (React)
   // v1 Request
   axios.get('/users')  // baseURL: /api/v1/
   → https://cybersecurity.neiu.edu/api/v1/users

   // v2 Request
   axiosV2.get('/admin/quiz')  // baseURL: /api/v2/
   → https://cybersecurity.neiu.edu/api/v2/admin/quiz

2. Host Nginx (Layer 2)
   - Matches: location /api
   - Action: proxy_pass http://backend_servers
   - Load balances to: 127.0.0.1:3001, 3002, or 3003
   - Forwards full path: /api/v1/users (or /api/v2/admin/quiz)

3. Backend Container (Layer 3)
   - Receives: GET /api/v1/users
   - Express.js routing:
     * app.use("/api/v1", publicRouter)      → v1 handler
     * app.use("/api/v2/admin", adminRouterV2) → v2 handler
   - Processes request, returns JSON

4. Response Flow
   Backend → Host Nginx → Browser
```

### ML Inference Request

```
1. Frontend → Backend
   POST /api/v1/predict

2. Backend → Model (via Docker network)
   POST http://model-1:5051/predict
   (Internal Docker network, not exposed to internet)

3. Model → Backend
   JSON response with prediction

4. Backend → Frontend
   Processed prediction result
```

---

## Current Deployment Status

### Deployment Timeline

| Component | Last Updated | Age | Image |
|-----------|--------------|-----|-------|
| Frontend | 7 weeks ago | ~49 days | `aiacosus/frontend:latest-prod` |
| Backend | 5 months ago | ~150 days | `aiacosus/backend:latest-prod` |
| Model | 6 months ago | ~180 days | `aiacosus/model:latest-prod` |

**Analysis:**
- Backend is older than frontend (unusual)
- Backend currently has both v1 and v2 routes
- System is stable (containers up for 2 weeks)

### Environment Variables

**Backend Containers:**
```yaml
environment:
  - NODE_ENV=production
  - ML_ROOT_URL=http://model-1:5051  # (varies per backend instance)
  - WORKERS=4
  - TRUST_PROXY=1
  - ACCESS_TOKEN_EXPIRES_IN=1d
  - REFRESH_TOKEN_EXPIRES_IN=7d
  - ACCESS_TOKEN_SECRET=${ACCESS_TOKEN_SECRET}  # From .env
  - REFRESH_TOKEN_SECRET=${REFRESH_TOKEN_SECRET}
  - AUTH_SECRET=${AUTH_SECRET}
  - CORS_ORIGIN=https://cybersecurity.neiu.edu,http://localhost:8081,...
```

**Frontend Containers:**
```yaml
environment:
  - NODE_ENV=production
  - VITE_API_URL=/api  # (No effect - build-time variable)
```

### Deployment Process

**Workflow:**
1. **Local Development** → Git push to feature branch
2. **GitHub Actions** → Build Docker image
   - Frontend: `aiacosus/frontend:{git-sha}-prod`
   - Backend: `aiacosus/backend:{git-sha}-prod`
   - Model: `aiacosus/model:{git-sha}-prod`
3. **Push to DockerHub** → Images available publicly
4. **Deploy to Server** → SSH + run `deploy-service.sh`
   ```bash
   ./deploy-service.sh backend latest-prod
   # Pulls image, updates docker-compose, restarts containers
   ```
5. **Validation** → Test via browser

**Deployment Script:** [deploy-service.sh](../../env/scripts/deploy-service.sh)

---

## Constraints and Limitations

### 1. Cannot Modify Host Nginx

**Files You Cannot Edit:**
- `/etc/nginx/nginx.conf`
- `/etc/nginx/conf.d/acosus.conf`

**Impact:**
- Cannot add new `location` blocks (e.g., `/posthog`, `/grafana`)
- Cannot change upstream targets
- Cannot add new upstreams

**Workaround:**
- Use existing routes (`/` or `/api`)
- Add logic inside containers (frontend nginx or backend Express)

### 2. Cannot Modify Firewall Rules

**Impact:**
- Cannot expose new ports directly (e.g., `:9000` for PostHog)
- All external access must go through port 443 (HTTPS)

**Workaround:**
- Use path-based routing instead of port-based
- Access services via existing routes

### 3. Administration Delays

**Challenge:**
- Requesting nginx changes takes weeks
- Not sustainable for frequent service additions

**Workaround:**
- Minimize or eliminate need for admin changes
- Use self-contained solutions

### 4. Existing URL Structure

**Current Structure:**
```
/               → Frontend (React app)
/api/v1/*       → Backend v1 routes
/api/v2/*       → Backend v2 routes
```

**Constraint:**
- Cannot add `/posthog` or `/grafana` at root level
- Must use subpaths under `/` or `/api`

**Solution:**
- Add services under `/api/services/*`
- Host nginx already routes `/api` to backend
- Backend can proxy to service containers

---

## Why Backend Gateway Solution Works

### Key Insight: Host Nginx Already Routes `/api` to Backend

```nginx
# In /etc/nginx/conf.d/acosus.conf (existing config)
location /api {
    proxy_pass http://backend_servers;
    # This matches ALL paths starting with /api
}
```

**This means:**
- `/api/v1/users` → backend ✅ (existing)
- `/api/v2/admin/quiz` → backend ✅ (existing)
- `/api/services/posthog/` → backend ✅ (NEW - will work!)

### Backend Has Full Control

Inside Express.js backend:
```javascript
// Existing routes (unchanged)
app.use("/api/v1", publicRouter);
app.use("/api/v2/admin", adminRouterV2);

// NEW: Add proxy route for services
app.use("/api/services", servicesProxyRouter);
```

**Backend can proxy to:**
- PostHog container via Docker network: `http://posthog:8000`
- Grafana container: `http://grafana:3000`
- Any other service container

### Network Connectivity

All backend containers are on `backend` network:
```yaml
backend-1:
  networks:
    - backend
    - ml
```

New service containers can join `backend` network:
```yaml
posthog:
  networks:
    - backend  # ← Backend can reach PostHog
```

Backend can communicate with PostHog:
```javascript
// Inside backend container
const response = await fetch('http://posthog:8000/api/event');
// Works! Both on 'backend' network
```

### Request Flow (New Services)

```
User: https://cybersecurity.neiu.edu/api/services/posthog/dashboard
    ↓
Host Nginx: /api → backend_servers (EXISTING RULE)
    ↓
Backend Container (backend-1):
    app.use('/api/services', createProxyMiddleware({
        target: 'http://posthog:8000',
        pathRewrite: { '^/api/services/posthog': '' }
    }))
    ↓ (Docker network: backend)
PostHog Container:
    GET /dashboard
    ↓
Response: PostHog dashboard HTML
```

**Zero nginx changes needed!** ✅

---

## Architecture Diagram

### Current State (Before Changes)

```
┌─────────────────────────────────────────────────────────────┐
│  Internet                                                    │
│  https://cybersecurity.neiu.edu                             │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  Host Nginx (Port 443) - CANNOT MODIFY                      │
│  ┌─────────────────┐  ┌────────────────────┐               │
│  │ location /      │  │ location /api      │               │
│  │ → frontend      │  │ → backend          │               │
│  └────────┬────────┘  └─────────┬──────────┘               │
└───────────┼───────────────────────┼──────────────────────────┘
            │                       │
            ▼                       ▼
┌──────────────────┐    ┌──────────────────────────────┐
│ Frontend         │    │ Backend Containers           │
│ Containers       │    │ (3 instances)                │
│                  │    │                              │
│ frontend-1:8081  │    │ backend-1:3001               │
│ frontend-2:8082  │    │ backend-2:3002               │
│                  │    │ backend-3:3003               │
│                  │    │                              │
│ Nginx serves     │    │ Express.js routes:           │
│ static files     │    │ - /api/v1/*                  │
│                  │    │ - /api/v2/*                  │
└──────────────────┘    └────────────┬─────────────────┘
                                     │
                                     ▼
                        ┌──────────────────────────────┐
                        │ Model Containers             │
                        │ (3 instances)                │
                        │                              │
                        │ model-1:5051                 │
                        │ model-2:5052                 │
                        │ model-3:5053                 │
                        │                              │
                        │ Flask ML inference           │
                        └──────────────────────────────┘
```

### Future State (After Phase 1)

```
┌─────────────────────────────────────────────────────────────┐
│  Internet                                                    │
│  https://cybersecurity.neiu.edu                             │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  Host Nginx (Port 443) - NO CHANGES                         │
│  ┌─────────────────┐  ┌────────────────────┐               │
│  │ location /      │  │ location /api      │               │
│  │ → frontend      │  │ → backend          │               │
│  └────────┬────────┘  └─────────┬──────────┘               │
└───────────┼───────────────────────┼──────────────────────────┘
            │                       │
            ▼                       ▼
┌──────────────────┐    ┌──────────────────────────────────────┐
│ Frontend         │    │ Backend Containers                   │
│ (unchanged)      │    │ (3 instances)                        │
│                  │    │                                      │
│ frontend-1:8081  │    │ backend-1:3001                       │
│ frontend-2:8082  │    │ backend-2:3002                       │
│                  │    │ backend-3:3003                       │
│ Nginx serves     │    │                                      │
│ static files     │    │ Express.js routes:                   │
│                  │    │ - /api/v1/* (unchanged)              │
│                  │    │ - /api/v2/* (unchanged)              │
│                  │    │ - /api/services/* (NEW)              │
│                  │    │   ↓                                  │
│                  │    │   Proxy to service containers        │
└──────────────────┘    └───────────┬────────┬─────────────────┘
                                    │        │
                        ┌───────────┘        └────────────┐
                        ▼                                  ▼
            ┌──────────────────────┐      ┌──────────────────────────┐
            │ Model Containers     │      │ Service Containers (NEW) │
            │ (unchanged)          │      │                          │
            │                      │      │ posthog:8000             │
            │ model-1:5051         │      │ grafana:3000             │
            │ model-2:5052         │      │ prometheus:9090          │
            │ model-3:5053         │      │                          │
            └──────────────────────┘      └──────────────────────────┘
```

**Key Changes:**
1. Backend adds `/api/services/*` proxy route
2. New service containers added to `backend` network
3. Zero changes to host nginx
4. Zero changes to frontend
5. Existing routes unaffected

---

## Summary

### What We Learned

1. **Host Nginx routes ALL `/api` requests to backend** - This is our entry point
2. **Backend has full control over routes under `/api`** - Can add proxy routes
3. **Docker networks allow inter-container communication** - Backend can reach services
4. **You can modify everything inside containers** - Backend code, docker-compose
5. **Admin changes take weeks** - Must minimize external dependencies

### Why Backend Gateway Works

✅ **No nginx changes** - Uses existing `/api` route
✅ **No firewall changes** - All via port 443
✅ **No admin delays** - Entirely self-contained
✅ **Quick to implement** - Just backend code + docker-compose
✅ **Safe and reversible** - Easy to rollback

### Next Steps

Now that you understand the current architecture, proceed to:

**→ [Phase 1: Backend API Gateway](./phase-1-backend-gateway.md)** - Implement PostHog via backend proxy

---

**Questions or unclear?** Review this document before proceeding to Phase 1.
