# DataVault API — production container image (built by GitHub Actions, stored in ECR)

FROM python:3.11-slim  # Minimal Python base; matches CI PYTHON_VERSION

WORKDIR /app           # All app files live here inside the container

# Install dependencies first (layer cached unless requirements.txt changes)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .         # Application code only — config comes from K8s env at runtime

EXPOSE 8000            # Documented port; matches Service targetPort and probes

# Docker-level health check (K8s probes in deployment.yaml are the primary health gate)
HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

# Bind 0.0.0.0 so traffic from the cluster network reaches the process
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
