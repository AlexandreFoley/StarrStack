.PHONY: venv test test-test-alpine test-static test-quadlet clean

venv:
	@if [ ! -d ".venv" ]; then \
		python3 -m venv .venv; \
		.venv/bin/pip install -r requirements-test.txt; \
	else \
		echo "Venv already exists"; \
	fi

test: venv
	.venv/bin/pytest tests/ -v -ra -s

# Same suite, alpine image: VARIANT selects the dockerfile + run flags
# (see tests/conftest.py). UNPACKERR_VERSION pins the alpine unpackerr release.
test-alpine: venv
	VARIANT=alpine .venv/bin/pytest tests/ -v -ra -s

test-static: venv
	.venv/bin/pytest tests/test_quadlet.py tests/test_basic.py -v -ra -s

test-quadlet: venv
	.venv/bin/pytest tests/test_quadlet.py -v -ra

clean:
	rm -rf .venv .pytest_cache
	podman rmi starr-quadlet-harness:latest 2>/dev/null || true
