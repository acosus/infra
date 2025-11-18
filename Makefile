# ACOSUS Development Environment Makefile
# Location: infra/Makefile
#
# This Makefile helps set up and manage the ACOSUS development environment.
# It clones all repos, installs dependencies, and manages Docker Compose.
#
# Usage:
#   1. Copy this Makefile to an empty directory
#   2. Run: make setup
#   3. Run: make up
#
# Commands:
#   make setup   - Clone repos, install deps, setup env files
#   make up      - Start all dev containers
#   make down    - Stop all dev containers
#   make restart - Restart all containers
#   make clean   - Stop and remove volumes (fresh DB)
#   make nuke    - ☢️  Wipe EVERYTHING (containers, images, volumes, networks)
#   make logs    - View all container logs
#   make status  - Show running containers
#   make seed    - Seed the database
#   make help    - Show this help message

.PHONY: help setup clone install config up down restart clean nuke logs status seed rebuild

# ============================================================
# Configuration Variables
# ============================================================

# GitHub Organization
GITHUB_ORG := acosus

# Repositories to clone
REPOS := frontend backend model docs infra

# Repos that need npm install
NPM_REPOS := frontend backend

# Repos that need Python venv
PYTHON_REPOS := model

# Project root (where Makefile is located)
PROJECT_ROOT := $(shell pwd)

# Docker compose file
COMPOSE_FILE := docker-compose.dev.yml

# ============================================================
# Colors for output
# ============================================================
COLOR_RESET := \e[0m
COLOR_BOLD := \e[1m
COLOR_GREEN := \e[32m
COLOR_YELLOW := \e[33m
COLOR_BLUE := \e[34m
COLOR_CYAN := \e[36m
COLOR_RED := \e[31m

# ============================================================
# Default Target
# ============================================================
.DEFAULT_GOAL := help

# ============================================================
# Help
# ============================================================
help:
	@echo -e "$(COLOR_BOLD)$(COLOR_CYAN)ACOSUS Development Environment$(COLOR_RESET)"
	@echo -e ""
	@echo -e "$(COLOR_BOLD)Setup Commands:$(COLOR_RESET)"
	@echo -e "  $(COLOR_GREEN)make setup$(COLOR_RESET)      - Full setup (clone + install + config)"
	@echo -e "  $(COLOR_GREEN)make clone$(COLOR_RESET)      - Clone all repositories"
	@echo -e "  $(COLOR_GREEN)make install$(COLOR_RESET)    - Install dependencies"
	@echo -e "  $(COLOR_GREEN)make config$(COLOR_RESET)     - Setup environment files"
	@echo -e ""
	@echo -e "$(COLOR_BOLD)Development Commands:$(COLOR_RESET)"
	@echo -e "  $(COLOR_GREEN)make dev$(COLOR_RESET)        - 🚀 Full dev setup with init (recommended)"
	@echo -e "  $(COLOR_GREEN)make up$(COLOR_RESET)         - Start all services"
	@echo -e "  $(COLOR_GREEN)make down$(COLOR_RESET)       - Stop all services"
	@echo -e "  $(COLOR_GREEN)make restart$(COLOR_RESET)    - Restart all services"
	@echo -e "  $(COLOR_GREEN)make rebuild$(COLOR_RESET)    - Rebuild and restart containers"
	@echo -e "  $(COLOR_GREEN)make clean$(COLOR_RESET)      - Stop and remove volumes (fresh DB)"
	@echo -e "  $(COLOR_GREEN)make nuke$(COLOR_RESET)       - ☢️  Nuclear option: wipe EVERYTHING"
	@echo -e ""
	@echo -e "$(COLOR_BOLD)Init Container Commands:$(COLOR_RESET)"
	@echo -e "  $(COLOR_GREEN)make dev-init-status$(COLOR_RESET) - Show init status and DB version"
	@echo -e "  $(COLOR_GREEN)make dev-reinit$(COLOR_RESET) - Re-run database initialization"
	@echo -e "  $(COLOR_GREEN)make dev-fresh$(COLOR_RESET) - Fresh start (clean + rebuild + init)"
	@echo -e "  $(COLOR_GREEN)make logs-init$(COLOR_RESET) - View init container logs"
	@echo -e ""
	@echo -e "$(COLOR_BOLD)Utility Commands:$(COLOR_RESET)"
	@echo -e "  $(COLOR_GREEN)make logs$(COLOR_RESET)       - View logs (all services)"
	@echo -e "  $(COLOR_GREEN)make logs-backend$(COLOR_RESET) - View backend logs"
	@echo -e "  $(COLOR_GREEN)make logs-frontend$(COLOR_RESET) - View frontend logs"
	@echo -e "  $(COLOR_GREEN)make logs-model$(COLOR_RESET) - View model logs"
	@echo -e "  $(COLOR_GREEN)make status$(COLOR_RESET)     - Show running containers"
	@echo -e "  $(COLOR_GREEN)make seed$(COLOR_RESET)       - Seed database with test data"
	@echo -e "  $(COLOR_GREEN)make shell-backend$(COLOR_RESET) - Open shell in backend container"
	@echo -e "  $(COLOR_GREEN)make shell-frontend$(COLOR_RESET) - Open shell in frontend container"
	@echo -e "  $(COLOR_GREEN)make shell-model$(COLOR_RESET) - Open shell in model container"
	@echo -e ""
# 	@echo -e "$(COLOR_BOLD)PostHog Commands:$(COLOR_RESET)"
# 	@echo -e "  $(COLOR_GREEN)make posthog-status$(COLOR_RESET) - Check PostHog services"
# 	@echo -e "  $(COLOR_GREEN)make posthog-start$(COLOR_RESET) - Start PostHog services"
# 	@echo -e "  $(COLOR_GREEN)make posthog-stop$(COLOR_RESET) - Stop PostHog services"
# 	@echo -e "  $(COLOR_GREEN)make posthog-restart$(COLOR_RESET) - Restart PostHog services"
# 	@echo -e "  $(COLOR_GREEN)make posthog-clean$(COLOR_RESET) - Remove PostHog data"
# 	@echo -e "  $(COLOR_GREEN)make logs-posthog$(COLOR_RESET) - View PostHog logs"
# 	@echo -e ""
	@echo -e "$(COLOR_BOLD)Quick Start:$(COLOR_RESET)"
	@echo -e "  1. $(COLOR_CYAN)make setup$(COLOR_RESET)  # First time only"
	@echo -e "  2. $(COLOR_CYAN)make up$(COLOR_RESET)     # Start development"
	@echo -e "  3. Open: $(COLOR_YELLOW)http://localhost:5173$(COLOR_RESET)"
	@echo -e ""

# ============================================================
# Full Setup (Clone + Install + Config)
# ============================================================
setup: check-requirements clone install config
	@echo -e "$(COLOR_BOLD)$(COLOR_GREEN)✓ Setup complete!$(COLOR_RESET)"
	@echo -e ""
	@echo -e "$(COLOR_BOLD)Next steps:$(COLOR_RESET)"
	@echo -e "  1. Review and edit .env.dev files if needed:"
	@echo -e "     - backend/.env.dev"
	@echo -e "     - frontend/.env.dev"
	@echo -e "     - model/.env.dev"
	@echo -e ""
	@echo -e "  2. Start development environment:"
	@echo -e "     $(COLOR_CYAN)make up$(COLOR_RESET)"
	@echo -e ""
	@echo -e "  3. Access services:"
	@echo -e "     - Frontend:      $(COLOR_YELLOW)http://localhost:5173$(COLOR_RESET)"
	@echo -e "     - Backend API:   $(COLOR_YELLOW)http://localhost:3000$(COLOR_RESET)"
	@echo -e "     - Model API:     $(COLOR_YELLOW)http://localhost:5051$(COLOR_RESET)"
	@echo -e "     - Mongo Express: $(COLOR_YELLOW)http://localhost:8081$(COLOR_RESET) (admin/admin123)"
	@echo -e ""

# ============================================================
# Check Requirements
# ============================================================
check-requirements:
	@echo -e "$(COLOR_BOLD)$(COLOR_BLUE)Checking requirements...$(COLOR_RESET)"
	@command -v gh >/dev/null 2>&1 || { echo "$(COLOR_BOLD)ERROR:$(COLOR_RESET) gh CLI is required. Install: brew install gh"; exit 1; }
	@command -v docker >/dev/null 2>&1 || { echo "$(COLOR_BOLD)ERROR:$(COLOR_RESET) Docker is required. Install from docker.com"; exit 1; }
	@command -v node >/dev/null 2>&1 || { echo "$(COLOR_BOLD)ERROR:$(COLOR_RESET) Node.js is required. Install: brew install node"; exit 1; }
	@command -v python3 >/dev/null 2>&1 || { echo "$(COLOR_BOLD)ERROR:$(COLOR_RESET) Python 3 is required. Install: brew install python"; exit 1; }
	@echo -e "$(COLOR_GREEN)✓ All requirements met$(COLOR_RESET)"

# ============================================================
# Clone Repositories
# ============================================================
clone:
	@echo -e "$(COLOR_BOLD)$(COLOR_BLUE)Cloning repositories...$(COLOR_RESET)"
	@for repo in $(REPOS); do \
		if [ -d "$$repo" ]; then \
			echo "$(COLOR_YELLOW)⊙ $$repo already exists, skipping...$(COLOR_RESET)"; \
		else \
			echo "$(COLOR_CYAN)→ Cloning $$repo...$(COLOR_RESET)"; \
			gh repo clone $(GITHUB_ORG)/$$repo || exit 1; \
		fi; \
	done
	@echo -e "$(COLOR_GREEN)✓ All repositories cloned$(COLOR_RESET)"

# ============================================================
# Install Dependencies
# ============================================================
install: install-npm install-python
	@echo -e "$(COLOR_GREEN)✓ All dependencies installed$(COLOR_RESET)"

install-npm:
	@echo -e "$(COLOR_BOLD)$(COLOR_BLUE)Installing Node.js dependencies...$(COLOR_RESET)"
	@for repo in $(NPM_REPOS); do \
		if [ -d "$$repo" ]; then \
			echo "$(COLOR_CYAN)→ Installing $$repo...$(COLOR_RESET)"; \
			cd $$repo && npm install && cd ..; \
		fi; \
	done

install-python:
	@echo -e "$(COLOR_BOLD)$(COLOR_BLUE)Setting up Python environments...$(COLOR_RESET)"
	@for repo in $(PYTHON_REPOS); do \
		if [ -d "$$repo" ]; then \
			echo "$(COLOR_CYAN)→ Setting up $$repo venv...$(COLOR_RESET)"; \
			cd $$repo && python3 -m venv venv && \
			. venv/bin/activate && \
			pip install --upgrade pip && \
			pip install -r requirements.txt && \
			cd ..; \
		fi; \
	done

# ============================================================
# Setup Configuration
# ============================================================
config: config-env config-docker
	@echo -e "$(COLOR_GREEN)✓ Configuration complete$(COLOR_RESET)"

config-env:
	@echo -e "$(COLOR_BOLD)$(COLOR_BLUE)Setting up environment files...$(COLOR_RESET)"
	@# Backend
	@if [ ! -f backend/.env.dev ]; then \
		if [ -f backend/.env.dev.example ]; then \
			echo "$(COLOR_CYAN)→ Creating backend/.env.dev from example...$(COLOR_RESET)"; \
			cp backend/.env.dev.example backend/.env.dev; \
		else \
			echo "$(COLOR_YELLOW)⚠ .env.dev.example not found, creating minimal .env.dev...$(COLOR_RESET)"; \
			echo "# Backend Development Environment" > backend/.env.dev; \
			echo "MONGODB_URI=mongodb://mongodb:27017/acosus_dev" >> backend/.env.dev; \
			echo "ML_ROOT_URL=http://model:5051" >> backend/.env.dev; \
			echo "ACCESS_TOKEN_SECRET=dev-secret-change-me" >> backend/.env.dev; \
			echo "REFRESH_TOKEN_SECRET=dev-refresh-secret-change-me" >> backend/.env.dev; \
			echo "AUTH_SECRET=dev-auth-secret-change-me" >> backend/.env.dev; \
			echo "CORS_ORIGIN=http://localhost:5173,http://localhost:3000" >> backend/.env.dev; \
			echo "NODE_ENV=development" >> backend/.env.dev; \
			echo "WORKERS=1" >> backend/.env.dev; \
		fi; \
	else \
		echo "$(COLOR_YELLOW)⊙ backend/.env.dev already exists$(COLOR_RESET)"; \
	fi
	@# Frontend
	@if [ ! -f frontend/.env.dev ]; then \
		if [ -f frontend/.env.dev.example ]; then \
			echo "$(COLOR_CYAN)→ Creating frontend/.env.dev from example...$(COLOR_RESET)"; \
			cp frontend/.env.dev.example frontend/.env.dev; \
		else \
			echo "$(COLOR_YELLOW)⚠ .env.dev.example not found, creating minimal .env.dev...$(COLOR_RESET)"; \
			echo "# Frontend Development Environment" > frontend/.env.dev; \
			echo "VITE_API_URL=http://localhost:3000" >> frontend/.env.dev; \
			echo "MODE=development" >> frontend/.env.dev; \
		fi; \
	else \
		echo "$(COLOR_YELLOW)⊙ frontend/.env.dev already exists$(COLOR_RESET)"; \
	fi
	@# Model
	@if [ ! -f model/.env.dev ]; then \
		if [ -f model/.env.dev.example ]; then \
			echo "$(COLOR_CYAN)→ Creating model/.env.dev from example...$(COLOR_RESET)"; \
			cp model/.env.dev.example model/.env.dev; \
		else \
			echo "$(COLOR_YELLOW)⚠ .env.dev.example not found, creating minimal .env.dev...$(COLOR_RESET)"; \
			echo "# Model Development Environment" > model/.env.dev; \
			echo "MODELENV=development" >> model/.env.dev; \
			echo "FLASK_HOST=0.0.0.0" >> model/.env.dev; \
			echo "FLASK_PORT=5051" >> model/.env.dev; \
			echo "EXPRESS_URL=http://backend:3000" >> model/.env.dev; \
			echo "FLASK_DEBUG=True" >> model/.env.dev; \
		fi; \
	else \
		echo "$(COLOR_YELLOW)⊙ model/.env.dev already exists$(COLOR_RESET)"; \
	fi

config-docker:
	@echo -e "$(COLOR_BOLD)$(COLOR_BLUE)Setting up Docker Compose...$(COLOR_RESET)"
	@if [ ! -f $(COMPOSE_FILE) ]; then \
		echo -e "$(COLOR_CYAN)→ Copying and fixing docker-compose.dev.yml paths...$(COLOR_RESET)"; \
		sed 's|../../backend|../backend|g; s|../../frontend|../frontend|g; s|../../model|../model|g' \
			docker/docker-compose.dev.yml > $(COMPOSE_FILE); \
	else \
		echo -e "$(COLOR_YELLOW)⊙ docker-compose.dev.yml already exists$(COLOR_RESET)"; \
	fi

# ============================================================
# Docker Compose Commands
# ============================================================
up:
	@echo -e "$(COLOR_BOLD)$(COLOR_BLUE)Starting development environment...$(COLOR_RESET)"
	@docker-compose -f $(COMPOSE_FILE) up -d
	@echo -e ""
	@echo -e "$(COLOR_BOLD)$(COLOR_GREEN)✓ Development environment started!$(COLOR_RESET)"
	@echo -e ""
	@echo -e "$(COLOR_BOLD)Services:$(COLOR_RESET)"
	@echo -e "  Frontend:      $(COLOR_YELLOW)http://localhost:5173$(COLOR_RESET)"
	@echo -e "  Backend API:   $(COLOR_YELLOW)http://localhost:3000/api/v1/health$(COLOR_RESET)"
	@echo -e "  Model API:     $(COLOR_YELLOW)http://localhost:5051/health$(COLOR_RESET)"
	@echo -e "  Mongo Express: $(COLOR_YELLOW)http://localhost:8081$(COLOR_RESET) (admin/admin123)"
# 	@echo -e "  PostHog:       $(COLOR_YELLOW)http://localhost:8000$(COLOR_RESET) (analytics)"
	@echo -e ""
	@echo -e "$(COLOR_BOLD)Commands:$(COLOR_RESET)"
	@echo -e "  View logs:     $(COLOR_CYAN)make logs$(COLOR_RESET)"
	@echo -e "  Stop:          $(COLOR_CYAN)make down$(COLOR_RESET)"
	@echo -e "  Seed DB:       $(COLOR_CYAN)make seed$(COLOR_RESET)"
	@echo -e ""

down:
	@echo -e "$(COLOR_BOLD)$(COLOR_BLUE)Stopping development environment...$(COLOR_RESET)"
	@docker-compose -f $(COMPOSE_FILE) down
	@echo -e "$(COLOR_GREEN)✓ Development environment stopped$(COLOR_RESET)"

restart:
	@echo -e "$(COLOR_BOLD)$(COLOR_BLUE)Restarting development environment...$(COLOR_RESET)"
	@docker-compose -f $(COMPOSE_FILE) restart
	@echo -e "$(COLOR_GREEN)✓ Development environment restarted$(COLOR_RESET)"

rebuild:
	@echo -e "$(COLOR_BOLD)$(COLOR_BLUE)Rebuilding containers...$(COLOR_RESET)"
	@docker-compose -f $(COMPOSE_FILE) up -d --build
	@echo -e "$(COLOR_GREEN)✓ Containers rebuilt and started$(COLOR_RESET)"

clean:
	@echo -e "$(COLOR_BOLD)$(COLOR_YELLOW)⚠️  This will delete all data (MongoDB, volumes)$(COLOR_RESET)"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		echo "$(COLOR_BOLD)$(COLOR_BLUE)Stopping and removing volumes...$(COLOR_RESET)"; \
		docker-compose -f $(COMPOSE_FILE) down -v; \
		echo "$(COLOR_GREEN)✓ Clean complete (all data removed)$(COLOR_RESET)"; \
	else \
		echo "$(COLOR_YELLOW)Cancelled$(COLOR_RESET)"; \
	fi


nuke:
	@echo -e "$(COLOR_BOLD)$(COLOR_YELLOW)☢️  NUCLEAR OPTION ☢️$(COLOR_RESET)"
	@echo -e "This will completely wipe:"
	@echo -e "  - All containers (running and stopped)"
	@echo -e "  - All images (acosus-*)"
	@echo -e "  - All volumes (acosus-*)"
	@echo -e "  - All networks (acosus-*)"
	@echo -e "  - Build cache"
	@echo -e ""
	@echo -e "$(COLOR_BOLD)$(COLOR_YELLOW)⚠️  You will need to rebuild everything from scratch!$(COLOR_RESET)"
	@echo -e ""
	@read -p "Are you ABSOLUTELY sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		echo "$(COLOR_BOLD)$(COLOR_BLUE)Nuking everything...$(COLOR_RESET)"; \
		echo ""; \
		echo "$(COLOR_CYAN)→ Stopping and removing containers...$(COLOR_RESET)"; \
		docker-compose -f $(COMPOSE_FILE) down -v --remove-orphans 2>/dev/null || true; \
		echo "$(COLOR_CYAN)→ Removing containers...$(COLOR_RESET)"; \
		docker ps -a --filter "name=acosus" --format "{{.ID}}" | xargs -r docker rm -f 2>/dev/null || true; \
		echo "$(COLOR_CYAN)→ Removing images...$(COLOR_RESET)"; \
		docker images --filter "reference=acosus/*" --format "{{.ID}}" | xargs -r docker rmi -f 2>/dev/null || true; \
		docker images --filter "reference=*/acosus*" --format "{{.ID}}" | xargs -r docker rmi -f 2>/dev/null || true; \
		echo "$(COLOR_CYAN)→ Removing volumes...$(COLOR_RESET)"; \
		docker volume ls --filter "name=acosus" --format "{{.Name}}" | xargs -r docker volume rm -f 2>/dev/null || true; \
		echo "$(COLOR_CYAN)→ Removing networks...$(COLOR_RESET)"; \
		docker network ls --filter "name=acosus" --format "{{.ID}}" | xargs -r docker network rm 2>/dev/null || true; \
		echo "$(COLOR_CYAN)→ Pruning build cache...$(COLOR_RESET)"; \
		docker builder prune -af 2>/dev/null || true; \
		echo "$(COLOR_CYAN)→ Pruning system...$(COLOR_RESET)"; \
		docker system prune -af --volumes 2>/dev/null || true; \
		echo ""; \
		echo "$(COLOR_BOLD)$(COLOR_GREEN)☢️  Nuclear cleanup complete!$(COLOR_RESET)"; \
		echo ""; \
		echo "$(COLOR_BOLD)Next steps:$(COLOR_RESET)"; \
		echo "  1. $(COLOR_CYAN)make up$(COLOR_RESET)     # Rebuild and start"; \
		echo "  2. $(COLOR_CYAN)make seed$(COLOR_RESET)   # Seed database"; \
		echo ""; \
	else \
		echo "$(COLOR_YELLOW)Cancelled - wise choice!$(COLOR_RESET)"; \
	fi

# ============================================================
# Development Init Container Commands
# ============================================================

# One-command full dev setup
dev: config-docker up dev-init-wait dev-status
	@echo -e "$(COLOR_BOLD)$(COLOR_GREEN)✓ Development environment ready!$(COLOR_RESET)"

# Wait for init container to complete
dev-init-wait:
	@echo -e "$(COLOR_BOLD)$(COLOR_BLUE)Waiting for backend initialization to complete...$(COLOR_RESET)"
	@timeout 120 sh -c 'until docker ps -a --filter "name=acosus-backend-init-dev" --filter "status=exited" --format "{{.Status}}" | grep -q "Exited (0)"; do \
		echo "$(COLOR_CYAN)→ Waiting for database initialization...$(COLOR_RESET)"; \
		sleep 5; \
	done' || { \
		echo "$(COLOR_BOLD)$(COLOR_RED)✗ ERROR: Init container failed or timed out$(COLOR_RESET)"; \
		echo ""; \
		echo "Init container logs:"; \
		docker logs acosus-backend-init-dev; \
		exit 1; \
	}
	@echo -e "$(COLOR_GREEN)✓ Backend initialization completed successfully$(COLOR_RESET)"

# Show development URLs and status
dev-status:
	@echo -e ""
	@echo -e "$(COLOR_BOLD)$(COLOR_CYAN)════════════════════════════════════════════════════════════════$(COLOR_RESET)"
	@echo -e "$(COLOR_BOLD)$(COLOR_CYAN)  ACOSUS Development Environment$(COLOR_RESET)"
	@echo -e "$(COLOR_BOLD)$(COLOR_CYAN)════════════════════════════════════════════════════════════════$(COLOR_RESET)"
	@echo -e ""
	@echo -e "$(COLOR_BOLD)Services:$(COLOR_RESET)"
	@echo -e "  Frontend:      $(COLOR_YELLOW)http://localhost:5173$(COLOR_RESET)"
	@echo -e "  Backend API:   $(COLOR_YELLOW)http://localhost:3000/api/v1/health$(COLOR_RESET)"
	@echo -e "  Model API:     $(COLOR_YELLOW)http://localhost:5051/health$(COLOR_RESET)"
	@echo -e "  Mongo Express: $(COLOR_YELLOW)http://localhost:8081$(COLOR_RESET) (admin/admin123)"
	@echo -e ""
	@echo -e "$(COLOR_BOLD)Commands:$(COLOR_RESET)"
	@echo -e "  View logs:        $(COLOR_CYAN)make logs$(COLOR_RESET)"
	@echo -e "  Init status:      $(COLOR_CYAN)make dev-init-status$(COLOR_RESET)"
	@echo -e "  Re-run init:      $(COLOR_CYAN)make dev-reinit$(COLOR_RESET)"
	@echo -e "  Fresh start:      $(COLOR_CYAN)make dev-fresh$(COLOR_RESET)"
	@echo -e "  Stop:             $(COLOR_CYAN)make down$(COLOR_RESET)"
	@echo -e ""

# Run database initialization only
dev-init-db:
	@echo -e "$(COLOR_BOLD)$(COLOR_BLUE)Running database initialization...$(COLOR_RESET)"
	@docker-compose -f $(COMPOSE_FILE) up backend-init
	@echo -e "$(COLOR_GREEN)✓ Database initialized$(COLOR_RESET)"

# Show init container and database status
dev-init-status:
	@echo -e "$(COLOR_BOLD)$(COLOR_BLUE)════════════════════════════════════════════════════════════════$(COLOR_RESET)"
	@echo -e "$(COLOR_BOLD)$(COLOR_BLUE)  Init Container Status$(COLOR_RESET)"
	@echo -e "$(COLOR_BOLD)$(COLOR_BLUE)════════════════════════════════════════════════════════════════$(COLOR_RESET)"
	@echo -e ""
	@docker ps -a --filter "name=acosus-backend-init-dev" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
	@echo -e ""
	@echo -e "$(COLOR_BOLD)Database Version:$(COLOR_RESET)"
	@docker-compose -f $(COMPOSE_FILE) exec -T mongodb mongosh --quiet acosus-dev --eval "db.getCollection('_system').findOne({_id: 'db-version'})" 2>/dev/null || echo "  Not initialized yet"
	@echo -e ""
	@echo -e "$(COLOR_BOLD)Data Counts:$(COLOR_RESET)"
	@docker-compose -f $(COMPOSE_FILE) exec -T mongodb mongosh --quiet acosus-dev --eval "print('  Users:', db.users.countDocuments()); print('  Quizzes:', db.quizzes.countDocuments());" 2>/dev/null || echo "  Database not ready"
	@echo -e ""

# Re-run initialization (useful for testing migration changes)
dev-reinit:
	@echo -e "$(COLOR_BOLD)$(COLOR_YELLOW)⚠️  This will re-run database initialization$(COLOR_RESET)"
	@echo -e "Current data will not be deleted, but migrations will run again."
	@echo -e ""
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		echo "$(COLOR_BOLD)$(COLOR_BLUE)Removing init container...$(COLOR_RESET)"; \
		docker rm -f acosus-backend-init-dev 2>/dev/null || true; \
		echo "$(COLOR_BOLD)$(COLOR_BLUE)Running init container...$(COLOR_RESET)"; \
		$(MAKE) dev-init-db; \
		$(MAKE) dev-init-status; \
	else \
		echo "$(COLOR_YELLOW)Cancelled$(COLOR_RESET)"; \
	fi

# Fresh start (clean + rebuild + init)
dev-fresh:
	@echo -e "$(COLOR_BOLD)$(COLOR_YELLOW)⚠️  This will delete ALL development data$(COLOR_RESET)"
	@echo -e ""
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		echo "$(COLOR_BOLD)$(COLOR_BLUE)Cleaning containers and volumes...$(COLOR_RESET)"; \
		docker-compose -f $(COMPOSE_FILE) down -v; \
		echo "$(COLOR_BOLD)$(COLOR_BLUE)Setting up environment...$(COLOR_RESET)"; \
		$(MAKE) config-docker; \
		echo "$(COLOR_BOLD)$(COLOR_BLUE)Building fresh containers...$(COLOR_RESET)"; \
		docker-compose -f $(COMPOSE_FILE) build --no-cache backend-init backend; \
		echo "$(COLOR_BOLD)$(COLOR_BLUE)Starting development environment...$(COLOR_RESET)"; \
		$(MAKE) dev; \
	else \
		echo "$(COLOR_YELLOW)Cancelled$(COLOR_RESET)"; \
	fi

# Show init container logs
logs-init:
	@docker logs acosus-backend-init-dev

# ============================================================
# Logging Commands
# ============================================================
logs:
	@docker-compose -f $(COMPOSE_FILE) logs -f

logs-backend:
	@docker-compose -f $(COMPOSE_FILE) logs -f backend

logs-frontend:
	@docker-compose -f $(COMPOSE_FILE) logs -f frontend

logs-model:
	@docker-compose -f $(COMPOSE_FILE) logs -f model

logs-mongodb:
	@docker-compose -f $(COMPOSE_FILE) logs -f mongodb

# logs-posthog:
# 	@docker-compose -f $(COMPOSE_FILE) logs -f posthog

# logs-postgres-posthog:
# 	@docker-compose -f $(COMPOSE_FILE) logs -f postgres-posthog

# logs-clickhouse-posthog:
# 	@docker-compose -f $(COMPOSE_FILE) logs -f clickhouse-posthog

# ============================================================
# Status Commands
# ============================================================
status:
	@echo -e "$(COLOR_BOLD)$(COLOR_BLUE)Container Status:$(COLOR_RESET)"
	@docker-compose -f $(COMPOSE_FILE) ps

# ============================================================
# Database Commands
# ============================================================
seed:
	@echo -e "$(COLOR_BOLD)$(COLOR_BLUE)Seeding database...$(COLOR_RESET)"
	@docker-compose -f $(COMPOSE_FILE) exec backend npm run seed:db
	@echo -e "$(COLOR_GREEN)✓ Database seeded$(COLOR_RESET)"

seed-admin:
	@echo -e "$(COLOR_BOLD)$(COLOR_BLUE)Seeding admin user...$(COLOR_RESET)"
	@docker-compose -f $(COMPOSE_FILE) exec backend npm run seed:admin
	@echo -e "$(COLOR_GREEN)✓ Admin user created$(COLOR_RESET)"

seed-quiz:
	@echo -e "$(COLOR_BOLD)$(COLOR_BLUE)Seeding quiz data...$(COLOR_RESET)"
	@docker-compose -f $(COMPOSE_FILE) exec backend npm run seed:quiz-init
	@echo -e "$(COLOR_GREEN)✓ Quiz data seeded$(COLOR_RESET)"

# ============================================================
# Shell Commands
# ============================================================
shell-backend:
	@docker-compose -f $(COMPOSE_FILE) exec backend sh

shell-frontend:
	@docker-compose -f $(COMPOSE_FILE) exec frontend sh

shell-model:
	@docker-compose -f $(COMPOSE_FILE) exec model sh

shell-mongodb:
	@docker-compose -f $(COMPOSE_FILE) exec mongodb mongosh

# ============================================================
# Utility Commands
# ============================================================
ps:
	@docker-compose -f $(COMPOSE_FILE) ps

stats:
	@docker stats --no-stream $(shell docker-compose -f $(COMPOSE_FILE) ps -q)

# ============================================================
# Update Commands
# ============================================================
pull:
	@echo -e "$(COLOR_BOLD)$(COLOR_BLUE)Pulling latest changes...$(COLOR_RESET)"
	@for repo in $(REPOS); do \
		if [ -d "$$repo" ]; then \
			echo "$(COLOR_CYAN)→ Pulling $$repo...$(COLOR_RESET)"; \
			cd $$repo && git pull && cd ..; \
		fi; \
	done
	@echo -e "$(COLOR_GREEN)✓ All repositories updated$(COLOR_RESET)"

update: pull install
	@echo -e "$(COLOR_GREEN)✓ Update complete$(COLOR_RESET)"

# ============================================================
# PostHog Commands
# ============================================================
# posthog-status:
# 	@echo -e "$(COLOR_BOLD)$(COLOR_BLUE)PostHog Services Status:$(COLOR_RESET)"
# 	@docker-compose -f $(COMPOSE_FILE) ps postgres-posthog clickhouse-posthog redis-posthog posthog

# posthog-restart:
# 	@echo -e "$(COLOR_BOLD)$(COLOR_BLUE)Restarting PostHog services...$(COLOR_RESET)"
# 	@docker-compose -f $(COMPOSE_FILE) restart postgres-posthog clickhouse-posthog redis-posthog posthog
# 	@echo -e "$(COLOR_GREEN)✓ PostHog services restarted$(COLOR_RESET)"

# posthog-stop:
# 	@echo -e "$(COLOR_BOLD)$(COLOR_BLUE)Stopping PostHog services...$(COLOR_RESET)"
# 	@docker-compose -f $(COMPOSE_FILE) stop postgres-posthog clickhouse-posthog redis-posthog posthog
# 	@echo -e "$(COLOR_GREEN)✓ PostHog services stopped$(COLOR_RESET)"

# posthog-start:
# 	@echo -e "$(COLOR_BOLD)$(COLOR_BLUE)Starting PostHog services...$(COLOR_RESET)"
# 	@docker-compose -f $(COMPOSE_FILE) up -d postgres-posthog clickhouse-posthog redis-posthog posthog
# 	@echo -e "$(COLOR_GREEN)✓ PostHog services started$(COLOR_RESET)"
# 	@echo -e ""
# 	@echo -e "$(COLOR_BOLD)Access PostHog:$(COLOR_RESET)"
# 	@echo -e "  Direct:  $(COLOR_YELLOW)http://localhost:8000$(COLOR_RESET)"
# 	@echo -e "  Proxy:   $(COLOR_YELLOW)http://localhost:3000/api/services/posthog$(COLOR_RESET)"
# 	@echo -e ""

# posthog-clean:
# 	@echo -e "$(COLOR_BOLD)$(COLOR_YELLOW)⚠️  This will delete all PostHog data$(COLOR_RESET)"
# 	@read -p "Are you sure? [y/N] " -n 1 -r; \
# 	echo; \
# 	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
# 		echo "$(COLOR_BOLD)$(COLOR_BLUE)Stopping and removing PostHog volumes...$(COLOR_RESET)"; \
# 		docker-compose -f $(COMPOSE_FILE) stop postgres-posthog clickhouse-posthog redis-posthog posthog; \
# 		docker-compose -f $(COMPOSE_FILE) rm -f postgres-posthog clickhouse-posthog redis-posthog posthog; \
# 		docker volume rm acosus-postgres-posthog-dev-data acosus-clickhouse-posthog-dev-data acosus-posthog-dev-data 2>/dev/null || true; \
# 		echo "$(COLOR_GREEN)✓ PostHog data removed$(COLOR_RESET)"; \
# 	else \
# 		echo "$(COLOR_YELLOW)Cancelled$(COLOR_RESET)"; \
# 	fi
