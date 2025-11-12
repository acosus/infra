# Services Deployment Strategy

**Created:** 2025-11-12
**Status:** Ready for Implementation
**Timeline:** Phase 1 can be completed in 1-2 hours

---

## Overview

This guide provides a comprehensive strategy for adding new services (PostHog, Grafana, Prometheus, etc.) to your on-premise cybersecurity server **without requiring host Nginx configuration changes**.

### The Challenge

Your on-premise server at `cybersecurity.neiu.edu` runs on RHEL 9 with Nginx configurations you cannot modify:
- `/etc/nginx/nginx.conf` (main config)
- `/etc/nginx/conf.d/acosus.conf` (custom config with `/` and `/api` routes)

You need to add monitoring and analytics services accessible via the same domain but can't update these Nginx files.

### The Solution

Use your **Express.js backend as an API gateway** to proxy requests to service containers. Since host Nginx already routes `/api/*` to your backend, you can add new routes like `/api/services/posthog/*` that proxy to service containers.

---

## Quick Navigation

### 📋 Implementation Guides

1. **[Phase 0: Current State Analysis](./phase-0-current-state.md)**
   - Existing architecture diagrams
   - Request flow documentation
   - Current limitations and constraints

2. **[Phase 1: Backend API Gateway (PRIMARY)](./phase-1-backend-gateway.md)** ⭐ **START HERE**
   - Add PostHog via backend proxy
   - Complete implementation guide
   - Code snippets and configurations
   - Testing procedures
   - **Timeline: 1-2 hours**

3. **[Phase 2: Alternative Solutions](./phase-2-alternatives.md)**
   - Frontend Nginx Gateway approach
   - SSH Tunnel access for internal tools
   - Port-based access (if firewall allows)
   - When to use each approach

4. **[Phase 3: Traefik Migration (Optional)](./phase-3-traefik.md)**
   - When to consider Traefik
   - Hybrid Traefik + Backend architecture
   - Complete implementation guide
   - Migration from Backend Gateway to Traefik
   - **Timeline: 3-4 hours**

5. **[Phase 4: Production Optimization (Optional)](./phase-4-optimization.md)**
   - Request one-time Nginx update
   - Cleaner URL structure (`/services/*` instead of `/api/services/*`)
   - Performance optimizations
   - Monitoring and health checks

### 📚 Reference Documents

- **[Appendix: Troubleshooting](./appendix-troubleshooting.md)**
  - Common issues and solutions
  - Debugging guide
  - Rollback procedures

- **[Appendix: Security Considerations](./appendix-security.md)**
  - Authentication and authorization
  - CORS configuration
  - Network isolation

---

## Implementation Roadmap

```
┌─────────────────────────────────────────────────────────────┐
│  Phase 1: Backend Gateway (IMMEDIATE - 1-2 hours)          │
│  ✓ Add PostHog via backend proxy                           │
│  ✓ Minimal changes, zero risk                              │
│  ✓ Works with existing infrastructure                      │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  Validate and Use (Days/Weeks)                              │
│  ✓ Test PostHog in production                              │
│  ✓ Monitor performance                                     │
│  ✓ Gather user feedback                                    │
└─────────────────────────────────────────────────────────────┘
                            ↓
                    Decision Point:
                Need more services?
                            ↓
              ┌─────────────┴─────────────┐
              │                           │
              ▼                           ▼
┌──────────────────────────┐  ┌──────────────────────────┐
│  Continue with Backend   │  │  Migrate to Traefik      │
│  Gateway (30 min/service)│  │  (Phase 3 - 3-4 hours)   │
│                          │  │                          │
│  Good for: 2-5 services  │  │  Good for: 5+ services   │
└──────────────────────────┘  └──────────────────────────┘
```

---

## Current Architecture Summary

### Request Flow (Before Changes)

```
Browser: https://cybersecurity.neiu.edu/
    ↓
Host Nginx (Port 443)
    ├─ location / → frontend containers (8081, 8082)
    └─ location /api → backend containers (3001, 3002, 3003)
                         ↓
                    Express.js Backend
                         ├─ /api/v1/* → v1 routes
                         └─ /api/v2/* → v2 routes
```

### Request Flow (After Phase 1)

```
Browser: https://cybersecurity.neiu.edu/api/services/posthog/
    ↓
Host Nginx (Port 443)
    └─ location /api → backend containers (3001, 3002, 3003)
                         ↓
                    Express.js Backend
                         ├─ /api/v1/* → v1 routes (unchanged)
                         ├─ /api/v2/* → v2 routes (unchanged)
                         └─ /api/services/* → NEW: Proxy to service containers
                                               ↓
                                          PostHog Container (8000)
```

---

## Key Benefits

### ✅ No Infrastructure Changes Required
- Zero host Nginx modifications
- Works with existing docker-compose setup
- No firewall rule changes

### ✅ Quick Implementation
- Phase 1: 1-2 hours (PostHog working)
- Add more services: 30 minutes each
- Minimal backend code changes

### ✅ Safe and Reversible
- Changes isolated to backend application code
- Easy rollback (just remove proxy routes)
- No risk to existing v1/v2 APIs

### ✅ Future-Proof
- Can migrate to Traefik later (Phase 3)
- Can request Nginx update for cleaner URLs (Phase 4)
- Scalable to many services

---

## Services Coverage

This plan supports adding:

### Monitoring & Analytics
- **PostHog** - Product analytics (Phase 1 - PRIMARY)
- **Grafana** - Metrics visualization (Phase 1 pattern)
- **Prometheus** - Metrics collection (Phase 1 pattern)

### Observability
- **Jaeger** - Distributed tracing
- **Loki** - Log aggregation
- **Alertmanager** - Alert routing

### Development Tools
- **Swagger UI** - API documentation
- **pgAdmin** - Database management
- **Redis Commander** - Redis management

### Any Other HTTP Service
- The pattern works for any containerized HTTP service
- Just add proxy route + docker-compose service

---

## Prerequisites

Before starting Phase 1, ensure you have:

- ✅ SSH access to `cybersecurity.neiu.edu`
- ✅ Permission to modify your application code (backend, frontend, model)
- ✅ Access to docker-compose.yml and ability to restart containers
- ✅ GitHub Actions access for deployment
- ✅ Access to private env repo with secrets
- ✅ Node.js development environment (for testing locally)

---

## Getting Started

### Step 1: Read Current State Analysis
Start with [Phase 0: Current State Analysis](./phase-0-current-state.md) to understand:
- How your current architecture works
- Why you can't modify host Nginx
- What constraints we're working with

### Step 2: Implement Backend Gateway
Follow [Phase 1: Backend API Gateway](./phase-1-backend-gateway.md) to:
- Add PostHog service to docker-compose
- Implement proxy route in Express backend
- Test locally and deploy to production
- **Timeline: 1-2 hours**

### Step 3: Validate and Monitor
- Test PostHog access via `cybersecurity.neiu.edu/api/services/posthog/`
- Monitor backend logs for proxy errors
- Check PostHog functionality

### Step 4: Consider Next Steps
- Need more services? Repeat Phase 1 pattern (30 min each)
- Need 5+ services? Consider [Phase 3: Traefik Migration](./phase-3-traefik.md)
- Want cleaner URLs? See [Phase 4: Production Optimization](./phase-4-optimization.md)

---

## Support and Questions

### During Implementation
- Each phase includes a **Troubleshooting** section
- Refer to [Appendix: Troubleshooting](./appendix-troubleshooting.md) for common issues
- Check [Appendix: Security](./appendix-security.md) for security best practices

### Testing Locally
- All phases include **Local Testing** sections
- Test before deploying to production
- Use `docker-compose` locally to validate changes

---

## Document History

| Date | Phase | Status | Notes |
|------|-------|--------|-------|
| 2025-11-12 | Phase 0 | Complete | Current state analysis |
| 2025-11-12 | Phase 1 | Ready | Backend gateway implementation |
| 2025-11-12 | Phase 2 | Ready | Alternative solutions documented |
| 2025-11-12 | Phase 3 | Ready | Traefik migration guide (optional) |
| 2025-11-12 | Phase 4 | Ready | Production optimization (optional) |

---

## Quick Reference

### URLs After Phase 1 Implementation

| Service | URL | Purpose |
|---------|-----|---------|
| PostHog | `https://cybersecurity.neiu.edu/api/services/posthog/` | Product analytics |
| PostHog API | `https://cybersecurity.neiu.edu/api/services/posthog/api/` | PostHog API endpoints |

### Backend Routes Added

```javascript
// In backend/src/app.ts
app.use('/api/services', servicesProxyRouter);
```

### Docker Services Added

```yaml
# In infra/docker/docker-compose.yml
services:
  posthog:
    image: posthog/posthog:latest
    # ... configuration
```

---

**Ready to start?** → Go to [Phase 1: Backend API Gateway](./phase-1-backend-gateway.md)
