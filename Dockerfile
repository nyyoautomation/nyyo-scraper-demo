# Nyyo scraper kit runtime. Base image pinned by digest, Python packages pinned by version AND hash.
FROM python:3.12-slim@sha256:a6e34c598f2467ed0e9a8d349809fcd8b5c603269512df273a0bb1784edc11b1
ARG BROWSER=0
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_DISABLE_PIP_VERSION_CHECK=1 PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
COPY requirements.txt requirements-browser.txt /tmp/
RUN if [ "$BROWSER" = 1 ]; then \
      pip install --no-cache-dir --require-hashes -r /tmp/requirements-browser.txt && \
      python -m playwright install --with-deps chromium && chmod -R a+rx /ms-playwright; \
    else pip install --no-cache-dir --require-hashes -r /tmp/requirements.txt; fi
WORKDIR /kit
ENTRYPOINT ["python", "/kit/scraper/nyyo_scrape.py"]
