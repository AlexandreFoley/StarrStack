set shell := ["bash", "-c"]

venv:
	@if [ ! -d ".venv" ]; then \
		python3 -m venv .venv; \
		.venv/bin/pip install -r requirements-test.txt; \
	else \
		echo "Venv already exists"; \
	fi

# Default: the whole suite against both images in one session.
test: venv
	.venv/bin/pytest tests/ -v -ra -s

# Single-variant runs are faster and useful in CI.
test-ubi: venv
	VARIANT=ubi .venv/bin/pytest tests/ -v -ra -s

test-alpine: venv
	VARIANT=alpine .venv/bin/pytest tests/test_basic.py tests/test_generated_api_keys.py tests/test_configure_indexers.py tests/test_configure_downloadclients.py tests/test_quadlet.py tests/test_service_sync.py -v -ra -s

test-static: venv
	.venv/bin/pytest tests/test_quadlet.py tests/test_basic.py -v -ra -s

test-quadlet: venv
	.venv/bin/pytest tests/test_quadlet.py -v -ra

clean:
	rm -rf .venv .pytest_cache
	podman rmi starr-quadlet-harness:latest 2>/dev/null || true
