FROM python:3.12-slim-bookworm
RUN apt-get update && apt-get install -y --no-install-recommends \
    clamav clamav-freshclam poppler-utils tesseract-ocr libseccomp2 \
    tesseract-ocr-eng tesseract-ocr-ara tesseract-ocr-rus \
    tesseract-ocr-kaz tesseract-ocr-kir tesseract-ocr-uzb \
    tesseract-ocr-uzb-cyrl tesseract-ocr-tur tesseract-ocr-ind \
    tesseract-ocr-urd tesseract-ocr-fra tesseract-ocr-spa \
    tesseract-ocr-por tesseract-ocr-swa tesseract-ocr-hin \
    tesseract-ocr-ben && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
RUN sed -i '/^NotifyClamd /d' /etc/clamav/freshclam.conf && freshclam --stdout
COPY processor.py .
COPY sandbox_exec.py extract_worker.py ./
COPY start.sh .
RUN useradd --uid 10002 --create-home extractor && chmod -R a-w /app
CMD ["sh", "start.sh"]
