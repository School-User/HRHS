#!/bin/bash
# =============================================================
#  Agent Zero - Install Script
#  Assumes: Docker is installed, Ollama is running with Qwen3-VL:8B
# =============================================================

set -e

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}"
echo "╔══════════════════════════════════════════╗"
echo "║        Agent Zero - Linux Installer      ║"
echo "║   Using Ollama + Qwen3-VL:8B (local)    ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

# --- Config ---
CONTAINER_NAME="agent-zero"
HOST_PORT="50080"
DATA_DIR="$HOME/agent-zero-data"
OLLAMA_MODEL="qwen3vl:8b"       # name as shown in: ollama list
OLLAMA_URL="http://host.docker.internal:11434"

# --- Step 1: Check Docker is running ---
echo -e "${YELLOW}[1/5] Checking Docker...${NC}"
if ! docker info > /dev/null 2>&1; then
  echo -e "${RED}Docker is not running. Please start Docker and try again.${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Docker is running${NC}"

# --- Step 2: Check Ollama is running ---
echo -e "${YELLOW}[2/5] Checking Ollama...${NC}"
if ! curl -s http://localhost:11434 > /dev/null 2>&1; then
  echo -e "${RED}Ollama is not running on port 11434. Start it with: ollama serve${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Ollama is running${NC}"

# --- Step 3: Verify Qwen3-VL:8B is available ---
echo -e "${YELLOW}[3/5] Checking Qwen3-VL:8B model in Ollama...${NC}"
if ! ollama list | grep -qi "qwen3"; then
  echo -e "${YELLOW}⚠ Qwen3-VL:8B not detected. You may need to check the exact model name with: ollama list${NC}"
  echo -e "${YELLOW}  Continuing anyway...${NC}"
else
  echo -e "${GREEN}✓ Qwen3-VL:8B found${NC}"
fi

# --- Step 4: Pull latest Agent Zero image ---
echo -e "${YELLOW}[4/5] Pulling latest Agent Zero Docker image...${NC}"
docker pull agent0ai/agent-zero:latest

# --- Step 5: Stop & remove any existing container ---
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo -e "${YELLOW}Removing existing container: ${CONTAINER_NAME}${NC}"
  docker stop "$CONTAINER_NAME" 2>/dev/null || true
  docker rm "$CONTAINER_NAME" 2>/dev/null || true
fi

# --- Step 6: Create persistent data directory ---
echo -e "${YELLOW}[5/5] Setting up data directory at ${DATA_DIR}...${NC}"
mkdir -p "$DATA_DIR"

# --- Step 7: Write .env with Ollama config ---
ENV_FILE="$DATA_DIR/.env"
cat > "$ENV_FILE" <<EOF
# Agent Zero - Auto-generated config
# Ollama base URL (host.docker.internal lets Docker reach your host machine)
OLLAMA_BASE_URL=${OLLAMA_URL}
EOF
echo -e "${GREEN}✓ .env written to ${ENV_FILE}${NC}"

# --- Step 8: Run the container ---
echo -e "${YELLOW}Starting Agent Zero container...${NC}"
docker run -d \
  --name "$CONTAINER_NAME" \
  --add-host=host.docker.internal:host-gateway \
  -p "${HOST_PORT}:80" \
  -v "${DATA_DIR}:/a0" \
  --restart unless-stopped \
  agent0ai/agent-zero:latest

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              ✅  Agent Zero is running!              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  🌐 Open in browser: ${GREEN}http://localhost:${HOST_PORT}${NC}"
echo ""
echo -e "${YELLOW}📋 Next steps — configure in the UI (Settings tab):${NC}"
echo ""
echo "  Chat model:"
echo "    Provider : Ollama"
echo "    Model    : qwen3vl:8b   (check exact name with: ollama list)"
echo "    API URL  : http://host.docker.internal:11434"
echo ""
echo "  Utility model (same or smaller):"
echo "    Provider : Ollama"
echo "    Model    : qwen3vl:8b"
echo "    API URL  : http://host.docker.internal:11434"
echo ""
echo "  Embedding model (optional, defaults to local CPU):"
echo "    Leave as default, or pull: ollama pull nomic-embed-text"
echo "    Then set Provider: Ollama, Model: nomic-embed-text"
echo ""
echo -e "${YELLOW}🛠  Useful commands:${NC}"
echo "  View logs   : docker logs -f ${CONTAINER_NAME}"
echo "  Stop        : docker stop ${CONTAINER_NAME}"
echo "  Start again : docker start ${CONTAINER_NAME}"
echo "  Remove      : docker rm -f ${CONTAINER_NAME}"
echo ""
echo -e "${YELLOW}⚠  Tip:${NC} Qwen3-VL:8B needs ~8GB RAM. If responses are slow,"
echo "   make sure Ollama isn't competing with other apps for memory."
echo ""

# =============================================================
#  GPU TEST — RTX 3070 Ti detection + Ollama GPU usage check
# =============================================================
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              🎮  GPU Diagnostics                     ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# --- Check nvidia-smi is available ---
if ! command -v nvidia-smi &> /dev/null; then
  echo -e "${RED}✗ nvidia-smi not found. Install NVIDIA drivers:${NC}"
  echo "    sudo apt install nvidia-driver-535 nvidia-utils-535"
  echo ""
else
  # --- Basic GPU info ---
  echo -e "${YELLOW}── GPU Info ───────────────────────────────────────────${NC}"
  nvidia-smi --query-gpu=name,driver_version,memory.total,memory.used,memory.free,temperature.gpu,utilization.gpu \
    --format=csv,noheader,nounits | while IFS=',' read -r name driver mem_total mem_used mem_free temp util; do
    echo -e "  GPU Name    : ${GREEN}${name}${NC}"
    echo -e "  Driver      : ${driver}"
    echo -e "  VRAM Total  : ${mem_total} MB"
    echo -e "  VRAM Used   : ${mem_used} MB"
    echo -e "  VRAM Free   : ${mem_free} MB"
    echo -e "  Temperature : ${temp}°C"
    echo -e "  GPU Util    : ${util}%"
  done
  echo ""

  # --- Check if RTX 3070 Ti is detected ---
  echo -e "${YELLOW}── RTX 3070 Ti Detection ──────────────────────────────${NC}"
  if nvidia-smi --query-gpu=name --format=csv,noheader | grep -qi "3070"; then
    echo -e "  ${GREEN}✓ RTX 3070 Ti detected!${NC}"
  else
    DETECTED=$(nvidia-smi --query-gpu=name --format=csv,noheader)
    echo -e "  ${YELLOW}⚠ RTX 3070 Ti not found. Detected: ${DETECTED}${NC}"
  fi
  echo ""

  # --- Check CUDA availability ---
  echo -e "${YELLOW}── CUDA Check ─────────────────────────────────────────${NC}"
  if command -v nvcc &> /dev/null; then
    CUDA_VER=$(nvcc --version | grep "release" | awk '{print $6}' | tr -d ',')
    echo -e "  ${GREEN}✓ CUDA installed: ${CUDA_VER}${NC}"
  else
    echo -e "  ${YELLOW}⚠ nvcc not found (CUDA toolkit not installed — Ollama may still use GPU via its own CUDA libs)${NC}"
  fi
  echo ""

  # --- Check if Ollama is using the GPU ---
  echo -e "${YELLOW}── Ollama GPU Usage Check ─────────────────────────────${NC}"
  echo -e "  Sending a test prompt to Ollama to trigger GPU load..."
  echo -e "  Watching nvidia-smi for 10 seconds...\n"

  # Fire a background request to Ollama
  curl -s -o /dev/null -X POST http://localhost:11434/api/generate \
    -H "Content-Type: application/json" \
    -d '{"model":"qwen3vl:8b","prompt":"Say hello in one word.","stream":false}' &
  CURL_PID=$!

  # Sample GPU utilization every 2 seconds for 10 seconds
  MAX_UTIL=0
  for i in 1 2 3 4 5; do
    sleep 2
    UTIL=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | tr -d ' ')
    MEM=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | tr -d ' ')
    echo -e "  [${i}0s] GPU Util: ${UTIL}%  |  VRAM Used: ${MEM} MB"
    if [ "$UTIL" -gt "$MAX_UTIL" ] 2>/dev/null; then
      MAX_UTIL=$UTIL
    fi
  done

  wait $CURL_PID 2>/dev/null

  echo ""
  if [ "$MAX_UTIL" -gt 5 ]; then
    echo -e "  ${GREEN}✓ GPU IS being used by Ollama! (peak util: ${MAX_UTIL}%)${NC}"
  else
    echo -e "  ${YELLOW}⚠ GPU utilization stayed low (${MAX_UTIL}%). Possible causes:${NC}"
    echo "      - Model is running on CPU (check: ollama ps)"
    echo "      - NVIDIA container toolkit not installed for Docker GPU passthrough"
    echo "      - Try: nvidia-smi dmon -s u  while running a prompt manually"
    echo ""
    echo -e "  ${YELLOW}To force GPU usage, ensure these env vars are set for Ollama:${NC}"
    echo "      CUDA_VISIBLE_DEVICES=0"
    echo "      OLLAMA_CUDA=true   (if using older Ollama builds)"
  fi
  echo ""

  # --- Final full nvidia-smi table ---
  echo -e "${YELLOW}── Full nvidia-smi Output ─────────────────────────────${NC}"
  nvidia-smi
fi

echo ""
echo -e "${GREEN}✅ All done! Agent Zero + GPU check complete.${NC}"
echo ""
