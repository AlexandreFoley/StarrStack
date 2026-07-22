.PHONY: venv test test-static test-quadlet test-integration test-integration-vpn clean

venv:
	@if [ ! -d ".venv" ]; then \
		python3 -m venv .venv; \
		.venv/bin/pip install -r requirements-test.txt; \
	else \
		echo "Venv already exists"; \
	fi

test: venv
	.venv/bin/pytest tests/ -v -ra -s

test-static: venv
	.venv/bin/pytest tests/test_quadlet.py tests/test_basic.py -v -ra -s

test-quadlet: venv
	.venv/bin/pytest tests/test_quadlet.py -v -ra

test-integration: venv
	.venv/bin/pytest tests/test_quadlet_integration.py -v -ra -s

test-integration-vpn: venv
	@if [ -f .env ]; then set -a; . ./.env; set +a; fi; \
	.venv/bin/pytest tests/test_quadlet_integration.py -v -ra -s

clean:
	rm -rf .venv .pytest_cache .test-secrets .test-mounts
	podman rm -f $$(podman ps -aq --filter "name=quadlet-harness-") 2>/dev/null || true
	podman rmi starr-quadlet-harness:latest 2>/dev/null || true
