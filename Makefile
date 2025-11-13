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
COLOR_RESET := \033[0m
COLOR_BOLD := \033[1m
COLOR_GREEN := \033[32m
COLOR_YELLOW := \033[33m
COLOR_BLUE := \033[34m
COLOR_CYAN := \033[36m

# ============================================================
# Default Target
# ============================================================
.DEFAULT_GOAL := help

# ============================================================
# Help
# ============================================================
help:
	@echo "$(COLOR_BOLD)$(COLOR_CYAN)ACOSUS Development Environment$(COLOR_RESET)"
	@echo ""
	@echo "$(COLOR_BOLD)Setup Commands:$(COLOR_RESET)"
	@echo "  $(COLOR_GREEN)make setup$(COLOR_RESET)      - Full setup (clone + install + config)"
	@echo "  $(COLOR_GREEN)make clone$(COLOR_RESET)      - Clone all repositories"
	@echo "  $(COLOR_GREEN)make install$(COLOR_RESET)    - Install dependencies"
	@echo "  $(COLOR_GREEN)make config$(COLOR_RESET)     - Setup environment files"
	@echo ""
	@echo "$(COLOR_BOLD)Development Commands:$(COLOR_RESET)"
	@echo "  $(COLOR_GREEN)make up$(COLOR_RESET)         - Start all services"
	@echo "  $(COLOR_GREEN)make down$(COLOR_RESET)       - Stop all services"
	@echo "  $(COLOR_GREEN)make restart$(COLOR_RESET)    - Restart all services"
	@echo "  $(COLOR_GREEN)make rebuild$(COLOR_RESET)    - Rebuild and restart containers"
	@echo "  $(COLOR_GREEN)make clean$(COLOR_RESET)      - Stop and remove volumes (fresh DB)"
	@echo "  $(COLOR_GREEN)make nuke$(COLOR_RESET)       - ☢️  Nuclear option: wipe EVERYTHING"
	@echo ""
	@echo "$(COLOR_BOLD)Utility Commands:$(COLOR_RESET)"
	@echo "  $(COLOR_GREEN)make logs$(COLOR_RESET)       - View logs (all services)"
	@echo "  $(COLOR_GREEN)make logs-backend$(COLOR_RESET) - View backend logs"
	@echo "  $(COLOR_GREEN)make logs-frontend$(COLOR_RESET) - View frontend logs"
	@echo "  $(COLOR_GREEN)make logs-model$(COLOR_RESET) - View model logs"
	@echo "  $(COLOR_GREEN)make status$(COLOR_RESET)     - Show running containers"
	@echo "  $(COLOR_GREEN)make seed$(COLOR_RESET)       - Seed database with test data"
	@echo "  $(COLOR_GREEN)make shell-backend$(COLOR_RESET) - Open shell in backend container"
	@echo "  $(COLOR_GREEN)make shell-frontend$(COLOR_RESET) - Open shell in frontend container"
	@echo "  $(COLOR_GREEN)make shell-model$(COLOR_RESET) - Open shell in model container"
	@echo ""
# 	@echo "$(COLOR_BOLD)PostHog Commands:$(COLOR_RESET)"
# 	@echo "  $(COLOR_GREEN)make posthog-status$(COLOR_RESET) - Check PostHog services"
# 	@echo "  $(COLOR_GREEN)make posthog-start$(COLOR_RESET) - Start PostHog services"
# 	@echo "  $(COLOR_GREEN)make posthog-stop$(COLOR_RESET) - Stop PostHog services"
# 	@echo "  $(COLOR_GREEN)make posthog-restart$(COLOR_RESET) - Restart PostHog services"
# 	@echo "  $(COLOR_GREEN)make posthog-clean$(COLOR_RESET) - Remove PostHog data"
# 	@echo "  $(COLOR_GREEN)make logs-posthog$(COLOR_RESET) - View PostHog logs"
# 	@echo ""
	@echo "$(COLOR_BOLD)Quick Start:$(COLOR_RESET)"
	@echo "  1. $(COLOR_CYAN)make setup$(COLOR_RESET)  # First time only"
	@echo "  2. $(COLOR_CYAN)make up$(COLOR_RESET)     # Start development"
	@echo "  3. Open: $(COLOR_YELLOW)http://localhost:5173$(COLOR_RESET)"
	@echo ""

# ============================================================
# Full Setup (Clone + Install + Config)
# ============================================================
setup: check-requirements clone install config
	@echo "$(COLOR_BOLD)$(COLOR_GREEN)✓ Setup complete!$(COLOR_RESET)"
	@echo ""
	@echo "$(COLOR_BOLD)Next steps:$(COLOR_RESET)"
	@echo "  1. Review and edit .env.dev files if needed:"
	@echo "     - backend/.env.dev"
	@echo "     - frontend/.env.dev"
	@echo "     - model/.env.dev"
	@echo ""
	@echo "  2. Start development environment:"
	@echo "     $(COLOR_CYAN)make up$(COLOR_RESET)"
	@echo ""
	@echo "  3. Access services:"
	@echo "     - Frontend:      $(COLOR_YELLOW)http://localhost:5173$(COLOR_RESET)"
	@echo "     - Backend API:   $(COLOR_YELLOW)http://localhost:3000$(COLOR_RESET)"
	@echo "     - Model API:     $(COLOR_YELLOW)http://localhost:5051$(COLOR_RESET)"
	@echo "     - Mongo Express: $(COLOR_YELLOW)http://localhost:8081$(COLOR_RESET) (admin/admin123)"
	@echo ""

# ============================================================
# Check Requirements
# ============================================================
check-requirements:
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)Checking requirements...$(COLOR_RESET)"
	@command -v gh >/dev/null 2>&1 || { echo "$(COLOR_BOLD)ERROR:$(COLOR_RESET) gh CLI is required. Install: brew install gh"; exit 1; }
	@command -v docker >/dev/null 2>&1 || { echo "$(COLOR_BOLD)ERROR:$(COLOR_RESET) Docker is required. Install from docker.com"; exit 1; }
	@command -v node >/dev/null 2>&1 || { echo "$(COLOR_BOLD)ERROR:$(COLOR_RESET) Node.js is required. Install: brew install node"; exit 1; }
	@command -v python3 >/dev/null 2>&1 || { echo "$(COLOR_BOLD)ERROR:$(COLOR_RESET) Python 3 is required. Install: brew install python"; exit 1; }
	@echo "$(COLOR_GREEN)✓ All requirements met$(COLOR_RESET)"

# ============================================================
# Clone Repositories
# ============================================================
clone:
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)Cloning repositories...$(COLOR_RESET)"
	@for repo in $(REPOS); do \
		if [ -d "$$repo" ]; then \
			echo "$(COLOR_YELLOW)⊙ $$repo already exists, skipping...$(COLOR_RESET)"; \
		else \
			echo "$(COLOR_CYAN)→ Cloning $$repo...$(COLOR_RESET)"; \
			gh repo clone $(GITHUB_ORG)/$$repo || exit 1; \
		fi; \
	done
	@echo "$(COLOR_GREEN)✓ All repositories cloned$(COLOR_RESET)"

# ============================================================
# Install Dependencies
# ============================================================
install: install-npm install-python
	@echo "$(COLOR_GREEN)✓ All dependencies installed$(COLOR_RESET)"

install-npm:
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)Installing Node.js dependencies...$(COLOR_RESET)"
	@for repo in $(NPM_REPOS); do \
		if [ -d "$$repo" ]; then \
			echo "$(COLOR_CYAN)→ Installing $$repo...$(COLOR_RESET)"; \
			cd $$repo && npm install && cd ..; \
		fi; \
	done

install-python:
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)Setting up Python environments...$(COLOR_RESET)"
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
	@echo "$(COLOR_GREEN)✓ Configuration complete$(COLOR_RESET)"

config-env:
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)Setting up environment files...$(COLOR_RESET)"
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
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)Setting up Docker Compose...$(COLOR_RESET)"
	@if [ ! -f $(COMPOSE_FILE) ]; then \
		echo "$(COLOR_CYAN)→ Copying and fixing docker-compose.dev.yml paths...$(COLOR_RESET)"; \
		sed 's|../../backend|./backend|g; s|../../frontend|./frontend|g; s|../../model|./model|g' \
			infra/docker/docker-compose.dev.yml > $(COMPOSE_FILE); \
	else \
		echo "$(COLOR_YELLOW)⊙ docker-compose.dev.yml already exists$(COLOR_RESET)"; \
	fi

# ============================================================
# Docker Compose Commands
# ============================================================
up:
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)Starting development environment...$(COLOR_RESET)"
	@docker-compose -f $(COMPOSE_FILE) up -d
	@echo ""
	@echo "$(COLOR_BOLD)$(COLOR_GREEN)✓ Development environment started!$(COLOR_RESET)"
	@echo ""
	@echo "$(COLOR_BOLD)Services:$(COLOR_RESET)"
	@echo "  Frontend:      $(COLOR_YELLOW)http://localhost:5173$(COLOR_RESET)"
	@echo "  Backend API:   $(COLOR_YELLOW)http://localhost:3000/api/v1/health$(COLOR_RESET)"
	@echo "  Model API:     $(COLOR_YELLOW)http://localhost:5051/health$(COLOR_RESET)"
	@echo "  Mongo Express: $(COLOR_YELLOW)http://localhost:8081$(COLOR_RESET) (admin/admin123)"
# 	@echo "  PostHog:       $(COLOR_YELLOW)http://localhost:8000$(COLOR_RESET) (analytics)"
	@echo ""
	@echo "$(COLOR_BOLD)Commands:$(COLOR_RESET)"
	@echo "  View logs:     $(COLOR_CYAN)make logs$(COLOR_RESET)"
	@echo "  Stop:          $(COLOR_CYAN)make down$(COLOR_RESET)"
	@echo "  Seed DB:       $(COLOR_CYAN)make seed$(COLOR_RESET)"
	@echo ""

down:
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)Stopping development environment...$(COLOR_RESET)"
	@docker-compose -f $(COMPOSE_FILE) down
	@echo "$(COLOR_GREEN)✓ Development environment stopped$(COLOR_RESET)"

restart:
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)Restarting development environment...$(COLOR_RESET)"
	@docker-compose -f $(COMPOSE_FILE) restart
	@echo "$(COLOR_GREEN)✓ Development environment restarted$(COLOR_RESET)"

rebuild:
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)Rebuilding containers...$(COLOR_RESET)"
	@docker-compose -f $(COMPOSE_FILE) up -d --build
	@echo "$(COLOR_GREEN)✓ Containers rebuilt and started$(COLOR_RESET)"

clean:
	@echo "$(COLOR_BOLD)$(COLOR_YELLOW)⚠️  This will delete all data (MongoDB, volumes)$(COLOR_RESET)"
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
	@echo "$(COLOR_BOLD)$(COLOR_YELLOW)☢️  NUCLEAR OPTION ☢️$(COLOR_RESET)"
	@echo "This will completely wipe:"
	@echo "  - All containers (running and stopped)"
	@echo "  - All images (acosus-*)"
	@echo "  - All volumes (acosus-*)"
	@echo "  - All networks (acosus-*)"
	@echo "  - Build cache"
	@echo ""
	@echo "$(COLOR_BOLD)$(COLOR_YELLOW)⚠️  You will need to rebuild everything from scratch!$(COLOR_RESET)"
	@echo ""
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
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)Container Status:$(COLOR_RESET)"
	@docker-compose -f $(COMPOSE_FILE) ps

# ============================================================
# Database Commands
# ============================================================
seed:
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)Seeding database...$(COLOR_RESET)"
	@docker-compose -f $(COMPOSE_FILE) exec backend npm run seed:db
	@echo "$(COLOR_GREEN)✓ Database seeded$(COLOR_RESET)"

seed-admin:
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)Seeding admin user...$(COLOR_RESET)"
	@docker-compose -f $(COMPOSE_FILE) exec backend npm run seed:admin
	@echo "$(COLOR_GREEN)✓ Admin user created$(COLOR_RESET)"

seed-quiz:
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)Seeding quiz data...$(COLOR_RESET)"
	@docker-compose -f $(COMPOSE_FILE) exec backend npm run seed:quiz-init
	@echo "$(COLOR_GREEN)✓ Quiz data seeded$(COLOR_RESET)"

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
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)Pulling latest changes...$(COLOR_RESET)"
	@for repo in $(REPOS); do \
		if [ -d "$$repo" ]; then \
			echo "$(COLOR_CYAN)→ Pulling $$repo...$(COLOR_RESET)"; \
			cd $$repo && git pull && cd ..; \
		fi; \
	done
	@echo "$(COLOR_GREEN)✓ All repositories updated$(COLOR_RESET)"

update: pull install
	@echo "$(COLOR_GREEN)✓ Update complete$(COLOR_RESET)"

# ============================================================
# PostHog Commands
# ============================================================
# posthog-status:
# 	@echo "$(COLOR_BOLD)$(COLOR_BLUE)PostHog Services Status:$(COLOR_RESET)"
# 	@docker-compose -f $(COMPOSE_FILE) ps postgres-posthog clickhouse-posthog redis-posthog posthog

# posthog-restart:
# 	@echo "$(COLOR_BOLD)$(COLOR_BLUE)Restarting PostHog services...$(COLOR_RESET)"
# 	@docker-compose -f $(COMPOSE_FILE) restart postgres-posthog clickhouse-posthog redis-posthog posthog
# 	@echo "$(COLOR_GREEN)✓ PostHog services restarted$(COLOR_RESET)"

# posthog-stop:
# 	@echo "$(COLOR_BOLD)$(COLOR_BLUE)Stopping PostHog services...$(COLOR_RESET)"
# 	@docker-compose -f $(COMPOSE_FILE) stop postgres-posthog clickhouse-posthog redis-posthog posthog
# 	@echo "$(COLOR_GREEN)✓ PostHog services stopped$(COLOR_RESET)"

# posthog-start:
# 	@echo "$(COLOR_BOLD)$(COLOR_BLUE)Starting PostHog services...$(COLOR_RESET)"
# 	@docker-compose -f $(COMPOSE_FILE) up -d postgres-posthog clickhouse-posthog redis-posthog posthog
# 	@echo "$(COLOR_GREEN)✓ PostHog services started$(COLOR_RESET)"
# 	@echo ""
# 	@echo "$(COLOR_BOLD)Access PostHog:$(COLOR_RESET)"
# 	@echo "  Direct:  $(COLOR_YELLOW)http://localhost:8000$(COLOR_RESET)"
# 	@echo "  Proxy:   $(COLOR_YELLOW)http://localhost:3000/api/services/posthog$(COLOR_RESET)"
# 	@echo ""

# posthog-clean:
# 	@echo "$(COLOR_BOLD)$(COLOR_YELLOW)⚠️  This will delete all PostHog data$(COLOR_RESET)"
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
