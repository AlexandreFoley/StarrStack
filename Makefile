.PHONY: venv test test-static test-quadlet clean

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

clean:
	rm -rf .venv .pytest_cache
	podman rmi starr-quadlet-harness:latest 2>/dev/null || true
