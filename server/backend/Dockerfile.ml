FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PIP_NO_CACHE_DIR=1 HF_HOME=/root/.cache/huggingface
WORKDIR /app
COPY backend/requirements.txt ./requirements.txt
RUN pip install -r requirements.txt
# CPU PyTorch avoids CUDA downloads and does not require a graphics card.
RUN pip install --index-url https://download.pytorch.org/whl/cpu torch torchvision
COPY backend/requirements-ml.txt ./requirements-ml.txt
RUN pip install -r requirements-ml.txt
COPY backend ./backend
COPY preview ./preview
COPY demo_data ./demo_data
EXPOSE 8000
CMD ["uvicorn", "backend.app.main:app", "--host", "0.0.0.0", "--port", "8000"]
