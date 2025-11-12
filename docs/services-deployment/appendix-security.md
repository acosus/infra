# Appendix: Security Considerations

**Purpose:** Security best practices for services deployment

---

## Table of Contents

1. [Threat Model](#threat-model)
2. [Network Security](#network-security)
3. [Authentication and Authorization](#authentication-and-authorization)
4. [Data Protection](#data-protection)
5. [Rate Limiting and DoS Protection](#rate-limiting-and-dos-protection)
6. [Logging and Monitoring](#logging-and-monitoring)
7. [Security Checklist](#security-checklist)

---

## Threat Model

### What We're Protecting

1. **Services themselves** (PostHog, Grafana, etc.)
2. **Service data** (analytics, metrics, logs)
3. **Backend infrastructure** (Express, Docker, host)
4. **User data** (if services access it)

### Attack Vectors

1. **Unauthorized access** to monitoring/admin tools
2. **Data exfiltration** via service APIs
3. **Service abuse** (excessive requests, resource exhaustion)
4. **Container escape** (breaking out of Docker)
5. **Man-in-the-middle** attacks (if not using HTTPS)
6. **Supply chain** attacks (malicious service images)

---

## Network Security

### 1. Network Isolation

**Principle:** Services only accessible from authorized paths.

```yaml
# docker-compose.yml
services:
  posthog:
    networks:
      - backend  # Only backend can reach PostHog
    # NO ports exposed to host (no 8000:8000)
    # Only accessible via backend proxy

  grafana:
    networks:
      - backend
      - services  # If using Traefik
    # Not on public network

  backend-1:
    networks:
      - backend   # Can reach services
      - frontend  # Can receive from frontend
      - ml        # Can reach models
```

**Result:**
- Services NOT directly accessible from internet
- Must go through backend proxy (authentication, logging)

### 2. Firewall Configuration

On the server, ensure only necessary ports are open:

```bash
# Check current firewall rules (requires sudo)
sudo firewall-cmd --list-all

# Should only show:
# ports: 22/tcp 80/tcp 443/tcp
# NOT: 3000/tcp 8000/tcp 9000/tcp (service ports)
```

**If service ports are exposed:**

```bash
# Remove them (ask admin)
sudo firewall-cmd --permanent --remove-port=8000/tcp
sudo firewall-cmd --reload
```

### 3. Docker Security

**Restrict Docker socket access:**

```yaml
# Traefik (if used)
traefik:
  volumes:
    - /var/run/docker.sock:/var/run/docker.sock:ro  # ← Read-only
  user: "root"  # Required for Docker socket access
```

**Run services as non-root:**

```yaml
posthog:
  user: "1000:1000"  # Non-root user
  # Security: Limits damage if container compromised
```

**Drop unnecessary capabilities:**

```yaml
posthog:
  cap_drop:
    - ALL
  cap_add:
    - NET_BIND_SERVICE  # Only if needed
```

---

## Authentication and Authorization

### 1. Backend-Level Authentication

Add authentication middleware to services router:

```typescript
// backend/src/middleware/auth.ts
import jwt from "jsonwebtoken";

export const authenticateToken = (req, res, next) => {
  const token = req.cookies.accessToken || req.headers.authorization?.split(" ")[1];

  if (!token) {
    return res.status(401).json({ error: "Unauthorized" });
  }

  try {
    const decoded = jwt.verify(token, process.env.ACCESS_TOKEN_SECRET);
    req.user = decoded;
    next();
  } catch (error) {
    return res.status(403).json({ error: "Invalid token" });
  }
};

export const requireAdmin = (req, res, next) => {
  if (req.user.role !== "admin") {
    return res.status(403).json({ error: "Admin access required" });
  }
  next();
};
```

**Apply to services:**

```typescript
// services.routes.ts
import { authenticateToken, requireAdmin } from "../../middleware/auth";

// PostHog: Public (for analytics collection)
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

### 2. IP Whitelisting

Restrict admin tools to specific IPs:

```typescript
// backend/src/middleware/ipWhitelist.ts
import ipRangeCheck from "ip-range-check";

export const allowedIPs = [
  "127.0.0.1",           // Localhost
  "::1",                 // IPv6 localhost
  "192.168.1.0/24",      // Campus network
  "10.0.0.0/8",          // Internal network
  // Add your IP ranges
];

export const ipWhitelist = (req, res, next) => {
  const clientIP = req.ip || req.headers["x-forwarded-for"]?.split(",")[0].trim();

  if (!clientIP) {
    return res.status(403).json({ error: "Cannot determine client IP" });
  }

  const isAllowed = allowedIPs.some((allowedRange) => {
    if (allowedRange.includes("/")) {
      return ipRangeCheck(clientIP, allowedRange);
    }
    return clientIP === allowedRange;
  });

  if (isAllowed) {
    next();
  } else {
    console.warn(`[Security] Blocked access from IP: ${clientIP}`);
    res.status(403).json({ error: "Access denied from this IP" });
  }
};
```

**Install dependency:**
```bash
npm install ip-range-check
```

**Apply:**
```typescript
// services.routes.ts
router.use("/grafana", ipWhitelist, authenticateToken, requireAdmin, createProxyMiddleware({...}));
```

### 3. Service-Level Authentication

Configure services with their own auth:

**PostHog:**
```yaml
posthog:
  environment:
    - POSTHOG_PERSONAL_API_KEY=${POSTHOG_API_KEY}  # Set strong key
```

**Grafana:**
```yaml
grafana:
  environment:
    - GF_SECURITY_ADMIN_USER=admin
    - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}  # Strong password
    - GF_AUTH_ANONYMOUS_ENABLED=false  # Disable anonymous access
    - GF_AUTH_BASIC_ENABLED=true
```

**Generate strong passwords:**
```bash
# Generate 32-character password
openssl rand -base64 32
```

Store in private env repo: `backend/.env`

```bash
GRAFANA_ADMIN_PASSWORD=...
POSTHOG_API_KEY=...
```

---

## Data Protection

### 1. Encryption in Transit

**Ensure HTTPS everywhere:**

- Host Nginx → Backend: HTTP (internal, trusted network)
- Backend → Services: HTTP (internal Docker network)
- Client → Host Nginx: **HTTPS** (SSL termination)

**Verify SSL config:**
```nginx
# In /etc/nginx/conf.d/acosus.conf
server {
    listen 443 ssl;
    ssl_protocols TLSv1.2 TLSv1.3;  # Modern protocols only
    ssl_ciphers HIGH:!aNULL:!MD5;   # Strong ciphers
    ssl_prefer_server_ciphers on;
}
```

### 2. Encryption at Rest

**Docker volumes:**

```bash
# Check if volumes support encryption
docker volume inspect posthog-data

# For sensitive data, use encrypted volumes (requires host setup)
```

**Service-specific encryption:**

```yaml
# PostHog: Encrypt sensitive fields
posthog:
  environment:
    - ENCRYPTION_KEYS=${POSTHOG_ENCRYPTION_KEYS}

# Grafana: Encrypt datasource passwords
grafana:
  environment:
    - GF_SECURITY_SECRET_KEY=${GRAFANA_SECRET_KEY}
```

### 3. Secrets Management

**Never commit secrets to git:**

```bash
# .gitignore
*.env
.env.*
secrets/
```

**Use environment variables:**

```yaml
# docker-compose.yml
posthog:
  env_file:
    - ../backend/.env  # Stored in private repo
  environment:
    - SECRET_KEY=${POSTHOG_SECRET_KEY}  # From .env file
```

**Rotate secrets regularly:**

```bash
# Generate new secret
NEW_SECRET=$(openssl rand -hex 32)

# Update in .env
echo "POSTHOG_SECRET_KEY=$NEW_SECRET" >> backend/.env

# Recreate containers
docker-compose up -d --force-recreate posthog
```

---

## Rate Limiting and DoS Protection

### 1. Backend Rate Limiting

Install express-rate-limit:

```bash
cd backend
npm install express-rate-limit
```

**Global services rate limit:**

```typescript
// services.routes.ts
import rateLimit from "express-rate-limit";

const servicesLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 1000, // Max 1000 requests per 15 min per IP
  message: {
    error: "Too many requests to services",
    retryAfter: "15 minutes",
  },
  standardHeaders: true, // Return rate limit info in headers
  legacyHeaders: false,
});

router.use(servicesLimiter);
```

**Per-service stricter limits:**

```typescript
const adminServicesLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100, // Stricter for admin tools
  message: "Too many requests to admin service",
});

router.use("/grafana", adminServicesLimiter);
router.use("/prometheus", adminServicesLimiter);
```

**Per-user rate limiting:**

```typescript
const userServicesLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 500,
  keyGenerator: (req) => {
    // Rate limit per authenticated user, not IP
    return req.user?.id || req.ip;
  },
});

router.use(authenticateToken, userServicesLimiter);
```

### 2. Nginx Rate Limiting

Request admin to add rate limiting at nginx level:

```nginx
# In /etc/nginx/conf.d/acosus.conf

# Define rate limit zone
limit_req_zone $binary_remote_addr zone=services_limit:10m rate=10r/s;

server {
    # ... existing config

    location /services {
        # Apply rate limit
        limit_req zone=services_limit burst=20 nodelay;

        # Existing proxy config
        proxy_pass http://backend_servers;
        # ...
    }
}
```

**Meaning:**
- 10 requests/second per IP
- Burst of 20 requests allowed
- Excess requests rejected with 503

### 3. Resource Limits

Prevent resource exhaustion:

```yaml
# docker-compose.yml
posthog:
  deploy:
    resources:
      limits:
        cpus: "2"       # Max 2 CPU cores
        memory: 2G      # Max 2GB RAM
      reservations:
        cpus: "0.5"     # Guaranteed minimum
        memory: 512M
  restart: unless-stopped  # Auto-restart if crashes
```

**Set timeouts:**

```typescript
// services.routes.ts
createProxyMiddleware({
  target: "http://posthog:8000",
  timeout: 30000,      // 30 second timeout
  proxyTimeout: 30000,
  // ...
})
```

---

## Logging and Monitoring

### 1. Access Logging

Log all service accesses:

```typescript
// services.routes.ts
router.use((req, res, next) => {
  const start = Date.now();

  res.on("finish", () => {
    const duration = Date.now() - start;
    const service = req.path.split("/")[1];

    console.log(
      JSON.stringify({
        type: "service_access",
        timestamp: new Date().toISOString(),
        service,
        method: req.method,
        path: req.path,
        statusCode: res.statusCode,
        duration,
        ip: req.ip,
        userAgent: req.headers["user-agent"],
        user: req.user?.id || "anonymous",
      })
    );
  });

  next();
});
```

### 2. Security Event Logging

Log security-related events:

```typescript
// middleware/ipWhitelist.ts
if (!isAllowed) {
  console.warn(
    JSON.stringify({
      type: "security_blocked_ip",
      timestamp: new Date().toISOString(),
      ip: clientIP,
      path: req.path,
      userAgent: req.headers["user-agent"],
    })
  );
  res.status(403).json({ error: "Access denied" });
}
```

```typescript
// middleware/auth.ts
if (!token) {
  console.warn(
    JSON.stringify({
      type: "security_unauthorized_access",
      timestamp: new Date().toISOString(),
      path: req.path,
      ip: req.ip,
    })
  );
  return res.status(401).json({ error: "Unauthorized" });
}
```

### 3. Log Aggregation

Collect logs for analysis:

```yaml
# docker-compose.yml
backend-1:
  logging:
    driver: "json-file"
    options:
      max-size: "200m"
      max-file: "10"
      labels: "service,environment"
```

**View logs:**
```bash
# Recent security events
docker logs backend-1 | grep security_

# Analyze blocked IPs
docker logs backend-1 | grep security_blocked_ip | jq '.ip' | sort | uniq -c
```

### 4. Alerting

Setup alerts for suspicious activity:

```typescript
// utils/alerting.ts
export const sendSecurityAlert = async (event) => {
  // Send to your monitoring system (email, Slack, PagerDuty, etc.)
  console.error(`[SECURITY ALERT] ${JSON.stringify(event)}`);

  // Example: Send to Slack webhook
  if (process.env.SLACK_WEBHOOK_URL) {
    await fetch(process.env.SLACK_WEBHOOK_URL, {
      method: "POST",
      body: JSON.stringify({
        text: `🚨 Security Alert: ${event.type}`,
        blocks: [
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: `*${event.type}*\n${JSON.stringify(event, null, 2)}`,
            },
          },
        ],
      }),
    });
  }
};
```

**Trigger alerts:**

```typescript
// Detect brute force attempts
const failedAttempts = new Map();

router.use((req, res, next) => {
  res.on("finish", () => {
    if (res.statusCode === 401 || res.statusCode === 403) {
      const key = req.ip;
      const count = (failedAttempts.get(key) || 0) + 1;
      failedAttempts.set(key, count);

      if (count > 10) {
        sendSecurityAlert({
          type: "brute_force_detected",
          ip: req.ip,
          attempts: count,
          path: req.path,
        });
      }
    }
  });

  next();
});
```

---

## Security Checklist

### Before Deployment

- [ ] All services on internal Docker networks (not exposed to host)
- [ ] Strong passwords/API keys for all services
- [ ] Secrets stored in private env repo (not in git)
- [ ] SSL/TLS enabled for external access
- [ ] Authentication middleware implemented
- [ ] Authorization checks (admin vs user)
- [ ] Rate limiting configured
- [ ] Resource limits set for all containers
- [ ] Logging enabled for all security events
- [ ] IP whitelisting for admin tools (if applicable)

### After Deployment

- [ ] Test unauthorized access (should be blocked)
- [ ] Test rate limiting (should throttle)
- [ ] Verify logs are being collected
- [ ] Check service health checks working
- [ ] Review security logs for anomalies
- [ ] Test rollback procedure

### Ongoing Maintenance

- [ ] Rotate secrets quarterly
- [ ] Review access logs weekly
- [ ] Update service images monthly (security patches)
- [ ] Audit user access quarterly
- [ ] Test disaster recovery annually

---

## Security Best Practices Summary

### Network Layer
✅ Services on internal networks only
✅ Firewall blocks direct service access
✅ SSL/TLS for external connections

### Authentication Layer
✅ Backend-level auth for all services
✅ Service-level auth configured
✅ Strong passwords/API keys
✅ IP whitelisting for admin tools

### Data Layer
✅ Secrets in environment variables
✅ Encryption in transit (HTTPS)
✅ Encryption at rest (if needed)
✅ Regular secret rotation

### Protection Layer
✅ Rate limiting (per IP, per user)
✅ Resource limits (CPU, memory)
✅ Request timeouts
✅ DoS protection

### Monitoring Layer
✅ Access logging
✅ Security event logging
✅ Alerting for suspicious activity
✅ Regular log review

---

## Compliance Considerations

If handling sensitive data (PII, FERPA, etc.):

### 1. Data Minimization
- Only collect necessary data in services
- Configure PostHog to not track PII
- Redact sensitive fields in logs

### 2. Access Controls
- Document who has access to services
- Implement principle of least privilege
- Regular access audits

### 3. Audit Trail
- Log all access to sensitive services
- Retain logs per compliance requirements
- Secure log storage

### 4. Incident Response
- Document security incident procedures
- Test incident response plan
- Have rollback procedure ready

---

**Security is an ongoing process, not a one-time task.**

Regularly review and update security measures as threats evolve.

**Questions about security?** Consult with your campus IT security team.
