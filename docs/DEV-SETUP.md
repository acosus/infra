# ACOSUS Development Environment Setup

**Complete guide to setting up and running the ACOSUS development environment with Docker Compose.**

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Quick Start](#quick-start)
4. [Detailed Setup](#detailed-setup)
5. [Daily Workflow](#daily-workflow)
6. [Services](#services)
7. [Troubleshooting](#troubleshooting)
8. [Advanced Usage](#advanced-usage)

---

## Overview

The ACOSUS development environment uses Docker Compose to run all services locally:

- **Frontend** (React + Vite) - Port 5173
- **Backend** (Express.js + TypeScript) - Port 3000
- **Model** (Python + Flask) - Port 5051
- **MongoDB** (Database) - Port 27017
- **Mongo Express** (Database UI) - Port 8081

**Benefits:**
- ✅ One command to start everything
- ✅ Hot reload for all apps (code changes auto-refresh)
- ✅ Local MongoDB (no cloud dependency)
- ✅ Database UI for easy viewing
- ✅ Same environment as production

---

## Prerequisites

### Required Software

1. **GitHub CLI** (for cloning repos)
   ```bash
   brew install gh
   gh auth login
   ```

2. **Docker Desktop** (for running containers)
   - Download: https://www.docker.com/products/docker-desktop
   - Or: `brew install --cask docker`

3. **Node.js** (v18+)
   ```bash
   brew install node
   node --version  # Should be v18 or higher
   ```

4. **Python 3** (v3.12+)
   ```bash
   brew install python
   python3 --version  # Should be 3.12 or higher
   ```

5. **Make** (usually pre-installed on Mac/Linux)
   ```bash
   make --version
   ```

### Verify Installation

```bash
gh --version      # GitHub CLI
docker --version  # Docker
node --version    # Node.js
python3 --version # Python
make --version    # Make
```

---

## Quick Start

### Option 1: Fresh Setup (Recommended)

```bash
# 1. Create a new directory for the project
mkdir acosus-dev && cd acosus-dev

# 2. Download the Makefile
curl https://raw.githubusercontent.com/acosus/infra/main/Makefile -o Makefile

# 3. Run setup (clones repos, installs deps, configures env)
make setup

# 4. Start development environment
make up

# 5. Open in browser
open http://localhost:5173  # Frontend
open http://localhost:8081  # Mongo Express (admin/admin123)
```

**That's it!** All services are now running.

### Option 2: Manual Setup

If you already have repos cloned:

```bash
cd /path/to/your/project

# 1. Copy Makefile from infra
cp infra/Makefile .

# 2. Setup env files and docker-compose
make config

# 3. Start dev environment
make up
```

---

## Detailed Setup

### Step 1: Clone Repositories

The Makefile will clone all required repos:

```bash
make clone
```

**Repositories cloned:**
- `frontend/` - React frontend
- `backend/` - Express.js backend
- `model/` - Python ML model
- `docs/` - Documentation
- `infra/` - Infrastructure configs

**Directory structure after clone:**
```
acosus-dev/
├── Makefile
├── docker-compose.dev.yml (copied from infra/)
├── frontend/
├── backend/
├── model/
├── docs/
└── infra/
```

### Step 2: Install Dependencies

```bash
make install
```

**This will:**
1. Run `npm install` in frontend and backend
2. Create Python venv in model
3. Install Python packages from requirements.txt

### Step 3: Configure Environment

```bash
make config
```

**This will:**
1. Copy `.env.dev.example` → `.env.dev` for each app
2. Copy `docker-compose.dev.yml` to project root

**Review and edit .env.dev files:**
```bash
# Backend
code backend/.env.dev

# Frontend
code frontend/.env.dev

# Model
code model/.env.dev
```

### Step 4: Start Development

```bash
make up
```

**This will:**
1. Build Docker images (first time only)
2. Start all containers
3. Wait for services to be healthy

**Check status:**
```bash
make status
```

---

## Daily Workflow

### Starting Your Day

```bash
cd acosus-dev
make up
```

Wait ~30 seconds for all services to start.

### Access Services

| Service | URL | Purpose |
|---------|-----|---------|
| **Frontend** | http://localhost:5173 | Main application |
| **Backend API** | http://localhost:3000 | REST API |
| **API Health** | http://localhost:3000/api/v1/health | Backend health check |
| **Model API** | http://localhost:5051 | ML predictions |
| **Model Health** | http://localhost:5051/health | Model health check |
| **Mongo Express** | http://localhost:8081 | Database viewer (admin/admin123) |

### Making Code Changes

**Hot reload is enabled for all services!**

#### Backend Changes

1. Edit any `.ts` file in `backend/src/`
2. Save file
3. Nodemon detects change and restarts backend
4. See changes immediately (no restart needed)

**Example:**
```bash
# Edit a file
code backend/src/routes/api/v1/public.routes.ts

# Save → backend auto-restarts
# Check logs
make logs-backend
```

#### Frontend Changes

1. Edit any `.tsx` or `.ts` file in `frontend/src/`
2. Save file
3. Vite HMR updates browser without refresh
4. See changes immediately

**Example:**
```bash
# Edit a component
code frontend/src/components/Dashboard.tsx

# Save → browser updates instantly
```

#### Model Changes

1. Edit any `.py` file in `model/`
2. Save file
3. Watchdog detects change and restarts Flask
4. See changes immediately

**Example:**
```bash
# Edit model code
code model/app/routes.py

# Save → Flask auto-restarts
```

### Viewing Logs

```bash
# All services
make logs

# Specific service
make logs-backend
make logs-frontend
make logs-model

# Follow logs (Ctrl+C to exit)
docker-compose -f docker-compose.dev.yml logs -f backend
```

### Database Management

**Seed database:**
```bash
make seed         # Full database seed
make seed-admin   # Create admin user
make seed-quiz    # Seed quiz data
```

**View database (Mongo Express):**
1. Open http://localhost:8081
2. Login: `admin` / `admin123`
3. Browse collections

**Connect via mongosh:**
```bash
make shell-mongodb

# Inside mongosh
use acosus_dev
db.users.find()
```

### Stopping Services

```bash
# Stop all services (data persists)
make down

# Stop and remove all data (fresh start)
make clean
```

### Ending Your Day

```bash
# Option 1: Leave running (uses resources but ready tomorrow)
# Do nothing

# Option 2: Stop services (save resources)
make down

# Option 3: Clean state (fresh DB tomorrow)
make clean
```

---

## Services

### Frontend (Port 5173)

**Technology:** React + TypeScript + Vite

**Hot Reload:** Vite HMR (instant updates)

**Environment:** `frontend/.env.dev`

**Key Config:**
```env
VITE_API_URL=http://localhost:3000
```

**Access:**
- Main app: http://localhost:5173
- Vite dev server features enabled

### Backend (Port 3000)

**Technology:** Express.js + TypeScript + MongoDB

**Hot Reload:** Nodemon (auto-restart on file changes)

**Environment:** `backend/.env.dev`

**Key Config:**
```env
MONGODB_URI=mongodb://mongodb:27017/acosus_dev
ML_ROOT_URL=http://model:5051
WORKERS=1  # Single worker for easier debugging
```

**Access:**
- Health: http://localhost:3000/api/v1/health
- API docs: http://localhost:3000/api-docs (if enabled)

**Shell access:**
```bash
make shell-backend
```

### Model (Port 5051)

**Technology:** Python 3.12 + Flask

**Hot Reload:** Watchdog (auto-restart on .py changes)

**Environment:** `model/.env.dev`

**Key Config:**
```env
FLASK_DEBUG=True
EXPRESS_URL=http://backend:3000
```

**Access:**
- Health: http://localhost:5051/health
- Predict endpoint: http://localhost:5051/predict

**Shell access:**
```bash
make shell-model
```

### MongoDB (Port 27017)

**Technology:** MongoDB 7.0

**Data Persistence:** Docker volume (survives restarts)

**Database:** `acosus_dev`

**Connection String:**
```
mongodb://localhost:27017/acosus_dev
```

**Access via CLI:**
```bash
make shell-mongodb
```

**Reset database:**
```bash
make clean  # Deletes all data
make up     # Fresh database
make seed   # Re-seed data
```

### Mongo Express (Port 8081)

**Technology:** Web-based MongoDB admin

**Access:** http://localhost:8081

**Login:**
- Username: `admin`
- Password: `admin123`

**Features:**
- Browse collections
- Run queries
- View/edit documents
- Export data

---

## Troubleshooting

### Services Won't Start

**Check Docker is running:**
```bash
docker ps
```

**Check for port conflicts:**
```bash
lsof -i :5173  # Frontend
lsof -i :3000  # Backend
lsof -i :5051  # Model
lsof -i :27017 # MongoDB
lsof -i :8081  # Mongo Express
```

**Rebuild containers:**
```bash
make rebuild
```

### Hot Reload Not Working

**Backend:**
```bash
# Check nodemon is watching files
make logs-backend | grep -i watching

# Verify volume mounts
docker inspect acosus-backend-dev | grep -A 10 Mounts
```

**Frontend:**
```bash
# Check Vite dev server
make logs-frontend | grep -i hmr

# Restart frontend
docker-compose -f docker-compose.dev.yml restart frontend
```

**Model:**
```bash
# Check watchdog is running
make logs-model | grep -i watching
```

### Database Connection Errors

**Check MongoDB is healthy:**
```bash
make status | grep mongodb

# Should show "healthy"
```

**Check connection from backend:**
```bash
make shell-backend
# Inside container:
wget -q -O - http://mongodb:27017
```

**Reset database:**
```bash
make clean
make up
make seed
```

### Frontend Can't Reach Backend

**Check backend is running:**
```bash
curl http://localhost:3000/api/v1/health
```

**Check CORS settings:**
```bash
# In backend/.env.dev
CORS_ORIGIN=http://localhost:5173,http://localhost:3000
```

**Check browser console** for CORS errors.

### Container Build Failures

**Clear Docker cache:**
```bash
docker system prune -a
make rebuild
```

**Check Dockerfile.dev exists:**
```bash
ls -la backend/Dockerfile.dev
ls -la frontend/Dockerfile.dev
ls -la model/Dockerfile.dev
```

---

## Advanced Usage

### Running Tests

**Backend tests:**
```bash
docker-compose -f docker-compose.dev.yml exec backend npm test
```

**Frontend tests:**
```bash
docker-compose -f docker-compose.dev.yml exec frontend npm test
```

### Accessing Container Shells

```bash
make shell-backend   # Backend shell
make shell-frontend  # Frontend shell
make shell-model     # Model shell
make shell-mongodb   # MongoDB shell
```

### Rebuilding Specific Service

```bash
# Rebuild backend only
docker-compose -f docker-compose.dev.yml up -d --build backend

# Rebuild all
make rebuild
```

### Custom Docker Compose Commands

```bash
# Any docker-compose command works
docker-compose -f docker-compose.dev.yml <command>

# Examples:
docker-compose -f docker-compose.dev.yml ps
docker-compose -f docker-compose.dev.yml logs backend
docker-compose -f docker-compose.dev.yml restart frontend
```

### Enabling PostHog (Optional)

Edit `docker-compose.dev.yml`, uncomment PostHog service:

```yaml
posthog:
  image: posthog/posthog:latest
  # ... (uncomment all lines)
```

Restart:
```bash
make down
make up
```

Access: http://localhost:3000/api/services/posthog

### Environment Variable Overrides

**Temporary override:**
```bash
MONGODB_URI=mongodb://localhost:27017/test make up
```

**Permanent override:**
Edit `backend/.env.dev`

### Viewing Resource Usage

```bash
make stats

# Or
docker stats
```

---

## Makefile Commands Reference

### Setup Commands

| Command | Description |
|---------|-------------|
| `make setup` | Full setup (clone + install + config) |
| `make clone` | Clone all repositories |
| `make install` | Install dependencies |
| `make config` | Setup environment files |

### Development Commands

| Command | Description |
|---------|-------------|
| `make up` | Start all services |
| `make down` | Stop all services |
| `make restart` | Restart all services |
| `make rebuild` | Rebuild and restart containers |
| `make clean` | Stop and remove volumes (fresh DB) |

### Utility Commands

| Command | Description |
|---------|-------------|
| `make logs` | View all logs |
| `make logs-backend` | View backend logs |
| `make logs-frontend` | View frontend logs |
| `make logs-model` | View model logs |
| `make status` | Show container status |
| `make seed` | Seed database |
| `make shell-backend` | Open backend shell |
| `make shell-frontend` | Open frontend shell |
| `make shell-model` | Open model shell |
| `make shell-mongodb` | Open MongoDB shell |
| `make pull` | Pull latest from all repos |
| `make update` | Pull + install (update everything) |

---

## Tips and Best Practices

### 1. Keep Containers Running

Leave containers running between dev sessions for faster startup.

### 2. Use make logs

Always check logs when something isn't working:
```bash
make logs-backend  # See what's happening
```

### 3. Seed Database Once

After `make up`, seed database once:
```bash
make seed
```

Don't need to seed again unless you run `make clean`.

### 4. Hot Reload is Your Friend

Don't restart containers manually. Just save files and let hot reload work.

### 5. Clean State When Stuck

If things are broken:
```bash
make clean  # Nuclear option - fresh start
make up
make seed
```

### 6. Check Health Endpoints

Before debugging, check if services are healthy:
```bash
curl http://localhost:3000/api/v1/health  # Backend
curl http://localhost:5051/health         # Model
```

---

## Next Steps

- **Start coding!** Make changes and see them instantly
- **Explore Mongo Express:** http://localhost:8081
- **Read API docs:** Check `backend/README.md`
- **Deploy to production:** See `infra/docs/DEPLOYMENT.md`

---

## Getting Help

- **Logs:** `make logs`
- **Status:** `make status`
- **Commands:** `make help`
- **Issues:** https://github.com/acosus/infra/issues

---

**Happy Coding!** 🚀
