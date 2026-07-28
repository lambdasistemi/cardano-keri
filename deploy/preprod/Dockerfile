FROM ghcr.io/astral-sh/uv:0.8.3@sha256:88baae1f9fa298996f8313e44559163c535937406d217f1c8ac9d4b86a2020fd AS uv

FROM python:3.12.11-slim-bookworm@sha256:c00fc7b44d844b6da22861ec24af43968a5200eac4ec607b4725d585165d6b49

ENV HOME=/var/lib/keri \
    PATH=/opt/keripy/.venv/bin:$PATH \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_COMPILE_BYTECODE=1

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
      libsodium23=1.0.18-1+deb12u1 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=uv /uv /uvx /bin/

WORKDIR /opt/keripy
COPY offchain/test/keri-fixtures/pyproject.toml .
COPY offchain/test/keri-fixtures/uv.lock .
RUN uv sync --frozen --no-dev --no-install-project \
    && test "$(.venv/bin/kli version | sed -n 's/^Library version: //p')" = "1.3.5"

RUN groupadd --gid 10001 keri \
    && useradd --uid 10001 --gid 10001 --home-dir /var/lib/keri --create-home keri \
    && mkdir -p /var/lib/keri/.keri \
    && chown -R keri:keri /var/lib/keri

COPY --chmod=0755 deploy/preprod/witness-entrypoint /usr/local/bin/witness-entrypoint

USER 10001:10001

VOLUME ["/var/lib/keri/.keri"]
EXPOSE 5632 5642

ENTRYPOINT ["/usr/local/bin/witness-entrypoint"]
