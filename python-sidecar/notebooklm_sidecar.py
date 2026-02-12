#!/usr/bin/env python3
"""NotebookLM Sidecar for AutoMeetsSlide.

This sidecar receives commands via command line arguments
and communicates via JSON on stdout.

Commands:
    login           - Open browser for Google login
    check-auth      - Check if authenticated
    process <file> <output_dir> - Full flow: upload, generate slides, download PDF
    check-status <notebook_id> <task_id> - Check generation status
    download <notebook_id> <output_dir> - Download completed slide deck PDF
"""

import asyncio
import json
import os
import sys
from pathlib import Path


def unique_path(path: Path) -> Path:
    """Return a unique file path by appending a number if the file already exists.

    Example: slides.pdf -> slides 2.pdf -> slides 3.pdf
    """
    if not path.exists():
        return path
    stem = path.stem
    suffix = path.suffix
    parent = path.parent
    counter = 2
    while True:
        candidate = parent / f"{stem} {counter}{suffix}"
        if not candidate.exists():
            return candidate
        counter += 1


def emit(status: str, message: str, **kwargs):
    """Emit a JSON status message to stdout."""
    data = {"status": status, "message": message, **kwargs}
    print(json.dumps(data), flush=True)


def emit_error(message: str):
    """Emit an error message."""
    print(json.dumps({"error": message}), flush=True)


def cmd_login():
    """Open browser for Google login using Playwright."""
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        emit_error("Playwright not installed. Run: pip install playwright && playwright install chromium")
        return

    from notebooklm.paths import get_browser_profile_dir, get_storage_path

    storage_path = get_storage_path()
    browser_profile = get_browser_profile_dir()
    storage_path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    browser_profile.mkdir(parents=True, exist_ok=True, mode=0o700)

    emit("progress", "Opening browser for Google login...")

    with sync_playwright() as p:
        # Use Playwright's bundled Chromium
        context = p.chromium.launch_persistent_context(
            user_data_dir=str(browser_profile),
            headless=False,
            args=[
                "--disable-blink-features=AutomationControlled",
                "--password-store=basic",
            ],
            ignore_default_args=["--enable-automation"],
        )

        page = context.pages[0] if context.pages else context.new_page()
        page.goto("https://notebooklm.google.com/")

        emit("waiting", "Please complete Google login in the browser...")

        # Wait for successful login - detect NotebookLM homepage
        # Poll until we're on the NotebookLM page (not login/accounts page)
        max_wait = 300  # 5 minutes
        poll_interval = 2
        waited = 0

        while waited < max_wait:
            current_url = page.url
            # Check if we're on NotebookLM (not on accounts.google.com or login page)
            if "notebooklm.google.com" in current_url and "accounts.google" not in current_url:
                # Additional check: look for signs we're actually logged in
                try:
                    # Wait a bit for page to settle
                    page.wait_for_load_state("networkidle", timeout=5000)
                    # Check if we're past the login
                    if "accounts.google" not in page.url:
                        emit("progress", "Login detected, saving authentication...")
                        break
                except:
                    pass

            page.wait_for_timeout(poll_interval * 1000)
            waited += poll_interval
            if waited % 10 == 0:
                emit("progress", f"Waiting for login... ({waited}s)")

        if waited >= max_wait:
            emit_error("Login timeout. Please try again.")
            context.close()
            return

        context.storage_state(path=str(storage_path))
        storage_path.chmod(0o600)
        context.close()

    emit("done", f"Authentication saved to: {storage_path}")


async def cmd_check_auth():
    """Check if user is authenticated."""
    emit("progress", "Checking authentication...")

    from notebooklm.paths import get_storage_path
    storage_path = get_storage_path()
    emit("progress", f"Storage path: {storage_path}")

    if not storage_path.exists():
        emit("error", f"Storage file not found: {storage_path}", authenticated=False)
        return

    emit("progress", "Storage file exists, validating tokens...")

    try:
        from notebooklm.auth import AuthTokens
        auth = await AuthTokens.from_storage()
        emit("progress", f"Tokens loaded: csrf={auth.csrf_token[:10]}..., session={auth.session_id[:10]}...")
        emit("done", "Authenticated", authenticated=True)
    except Exception as e:
        emit("error", f"Authentication check failed: {type(e).__name__}: {e}", authenticated=False)


DEFAULT_SYSTEM_PROMPT = "この内容から包括的なスライドデッキを日本語で作成してください。"


async def cmd_process(
    file_path: str,
    output_dir: str,
    system_prompt: str | None = None,
    job_id: str | None = None,
    additional_files: list[str] | None = None,
    source_urls: list[str] | None = None,
):
    """Full flow: create notebook, upload source(s), generate slides, download PDF.

    Args:
        file_path: Path to primary input file
        output_dir: Output directory for PDF
        system_prompt: Custom instructions for slide generation (optional)
        job_id: Unique job identifier for recovery (optional)
        additional_files: Additional source file paths (optional)
        source_urls: Web/Google Doc URLs to add as sources (optional)
    """
    from notebooklm.client import NotebookLMClient

    file_path = Path(file_path)
    output_dir = Path(output_dir)

    if not file_path.exists():
        emit_error(f"File not found: {file_path}")
        return

    output_dir.mkdir(parents=True, exist_ok=True)

    emit("progress", "Connecting to NotebookLM...")

    try:
        async with await NotebookLMClient.from_storage() as client:
            # Create notebook
            emit("progress", "Creating notebook...")
            title = f"Auto Slide: {file_path.name} [{job_id}]" if job_id else f"Auto Slide: {file_path.name}"
            notebook = await client.notebooks.create(title)
            notebook_id = notebook.id
            emit("progress", f"Notebook created: {notebook_id}", notebook_id=notebook_id)

            # Add primary source
            emit("progress", f"Uploading source: {file_path.name}...")
            source = await client.sources.add_file(notebook_id, str(file_path))
            emit("progress", f"Source uploaded: {source.id}")
            source_ids = [(source.id, file_path.name)]

            # Add additional file sources
            for af_path in (additional_files or []):
                af = Path(af_path)
                if not af.exists():
                    emit("progress", f"Skipping missing file: {af}")
                    continue
                emit("progress", f"Uploading additional source: {af.name}...")
                af_source = await client.sources.add_file(notebook_id, str(af))
                emit("progress", f"Additional source uploaded: {af_source.id}")
                source_ids.append((af_source.id, af.name))

            # Add URL sources
            for url in (source_urls or []):
                emit("progress", f"Adding URL source: {url}...")
                url_source = await client.sources.add_url(notebook_id, url)
                emit("progress", f"URL source added: {url_source.id}")
                source_ids.append((url_source.id, url))

            # Wait for all sources to be processed
            for sid, sname in source_ids:
                emit("progress", f"Waiting for source to be processed: {sname}...")
                ready_source = await client.sources.wait_until_ready(
                    notebook_id, sid, timeout=300.0  # 5 minutes for audio
                )
                emit("progress", f"Source ready: {ready_source.title}")

            # Generate slides
            emit("progress", "Generating slide deck...")
            instructions = system_prompt or DEFAULT_SYSTEM_PROMPT
            status = await client.artifacts.generate_slide_deck(
                notebook_id,
                instructions=instructions
            )
            if not status.task_id:
                emit_error(f"Slide generation failed to start (no task_id returned). The API may have rejected the request.")
                return
            emit("progress", f"Generation started, task_id: {status.task_id}", task_id=status.task_id, notebook_id=notebook_id)

            # Wait for completion
            emit("progress", "Waiting for slide generation to complete...")
            final_status = await client.artifacts.wait_for_completion(
                notebook_id,
                status.task_id,
                timeout=1800.0  # 30 minutes max
            )

            if final_status.is_failed:
                emit("progress", f"Generation status reports failed (status={final_status.status}), attempting download anyway...")
            else:
                emit("progress", "Slide generation complete!")

            # Download PDF
            output_file = unique_path(output_dir / f"{file_path.stem}_slides.pdf")
            emit("progress", f"Downloading PDF to: {output_file}")

            downloaded_path = await client.artifacts.download_slide_deck(
                notebook_id,
                str(output_file)
            )

            emit("done", f"PDF downloaded: {downloaded_path}", output_path=str(downloaded_path), notebook_id=notebook_id)

    except FileNotFoundError as e:
        emit_error(f"Not authenticated. Run 'login' first. ({e})")
    except Exception as e:
        import traceback
        emit_error(f"Process failed: {type(e).__name__}: {e}\n{traceback.format_exc()}")


async def cmd_find_notebook(job_id: str):
    """Find an existing notebook by job ID and return its status."""
    from notebooklm.client import NotebookLMClient

    emit("progress", f"Searching for notebook with job ID: {job_id}")

    try:
        async with await NotebookLMClient.from_storage() as client:
            notebooks = await client.notebooks.list()
            for nb in notebooks:
                if job_id in nb.title:
                    emit("progress", f"Found notebook: {nb.id}")
                    # Check for slide deck artifacts
                    artifacts = await client.artifacts.list(nb.id)
                    for artifact in artifacts:
                        if hasattr(artifact, 'kind') and 'slide' in str(artifact.kind).lower():
                            emit("done", f"Found notebook with slide artifact",
                                 notebook_id=nb.id,
                                 task_id=artifact.id,
                                 generation_status="completed" if artifact.is_completed else "processing" if artifact.is_processing else "failed",
                                 is_complete=artifact.is_completed,
                                 is_failed=artifact.is_failed)
                            return
                    # Notebook exists but no slide artifact yet
                    emit("done", f"Found notebook but no slide artifact",
                         notebook_id=nb.id,
                         generation_status="no_artifact")
                    return

            emit("done", "No matching notebook found", notebook_id=None)
    except FileNotFoundError as e:
        emit_error(f"Not authenticated. Run 'login' first. ({e})")
    except Exception as e:
        emit_error(f"Find notebook failed: {type(e).__name__}: {e}")


async def cmd_check_status(notebook_id: str, task_id: str):
    """Check the generation status of a task."""
    from notebooklm.client import NotebookLMClient

    emit("progress", "Checking generation status...")

    try:
        async with await NotebookLMClient.from_storage() as client:
            status = await client.artifacts.poll_status(notebook_id, task_id)
            emit("done", f"Status: {status.status}",
                 generation_status=status.status,
                 is_complete=status.is_complete,
                 is_failed=status.is_failed,
                 task_id=task_id)
    except FileNotFoundError as e:
        emit_error(f"Not authenticated. Run 'login' first. ({e})")
    except Exception as e:
        emit_error(f"Check status failed: {type(e).__name__}: {e}")


async def cmd_download(notebook_id: str, output_dir: str, name: str | None = None, artifact_id: str | None = None):
    """Download a completed slide deck PDF."""
    from notebooklm.client import NotebookLMClient

    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    emit("progress", "Downloading slide deck...")

    try:
        async with await NotebookLMClient.from_storage() as client:
            file_name = f"{name}_slides.pdf" if name else "slides.pdf"
            output_file = unique_path(output_dir / file_name)
            downloaded_path = await client.artifacts.download_slide_deck(
                notebook_id,
                str(output_file),
                artifact_id=artifact_id
            )
            emit("done", f"PDF downloaded: {downloaded_path}", output_path=str(downloaded_path))
    except FileNotFoundError as e:
        emit_error(f"Not authenticated. Run 'login' first. ({e})")
    except Exception as e:
        import traceback
        emit_error(f"Download failed: {type(e).__name__}: {e}\n{traceback.format_exc()}")


def main():
    if len(sys.argv) < 2:
        emit_error("No command provided. Use: login, check-auth, process, check-status, or download")
        return

    command = sys.argv[1]

    if command == "login":
        # Login is synchronous (uses sync_playwright)
        cmd_login()

    elif command == "check-auth":
        asyncio.run(cmd_check_auth())

    elif command == "process":
        if len(sys.argv) < 4:
            emit_error("Usage: process <file_path> <output_dir> [--system-prompt <prompt>] [--source-file <path>]... [--source-url <url>]...")
            return
        file_path = sys.argv[2]
        output_dir = sys.argv[3]

        # Parse --system-prompt flag
        system_prompt = None
        if "--system-prompt" in sys.argv:
            idx = sys.argv.index("--system-prompt")
            if idx + 1 < len(sys.argv):
                system_prompt = sys.argv[idx + 1]

        # Parse --job-id flag
        job_id = None
        if "--job-id" in sys.argv:
            idx = sys.argv.index("--job-id")
            if idx + 1 < len(sys.argv):
                job_id = sys.argv[idx + 1]

        # Parse --source-file flags (can appear multiple times)
        additional_files = []
        for i, arg in enumerate(sys.argv):
            if arg == "--source-file" and i + 1 < len(sys.argv):
                additional_files.append(sys.argv[i + 1])

        # Parse --source-url flags (can appear multiple times)
        source_urls = []
        for i, arg in enumerate(sys.argv):
            if arg == "--source-url" and i + 1 < len(sys.argv):
                source_urls.append(sys.argv[i + 1])

        asyncio.run(cmd_process(file_path, output_dir, system_prompt, job_id, additional_files or None, source_urls or None))

    elif command == "find-notebook":
        if len(sys.argv) < 3:
            emit_error("Usage: find-notebook <job_id>")
            return
        asyncio.run(cmd_find_notebook(sys.argv[2]))

    elif command == "check-status":
        if len(sys.argv) < 4:
            emit_error("Usage: check-status <notebook_id> <task_id>")
            return
        asyncio.run(cmd_check_status(sys.argv[2], sys.argv[3]))

    elif command == "download":
        if len(sys.argv) < 4:
            emit_error("Usage: download <notebook_id> <output_dir> [--name <stem>] [--artifact-id <id>]")
            return
        notebook_id = sys.argv[2]
        output_dir = sys.argv[3]

        name = None
        if "--name" in sys.argv:
            idx = sys.argv.index("--name")
            if idx + 1 < len(sys.argv):
                name = sys.argv[idx + 1]

        artifact_id = None
        if "--artifact-id" in sys.argv:
            idx = sys.argv.index("--artifact-id")
            if idx + 1 < len(sys.argv):
                artifact_id = sys.argv[idx + 1]

        asyncio.run(cmd_download(notebook_id, output_dir, name, artifact_id))

    else:
        emit_error(f"Unknown command: {command}")


if __name__ == "__main__":
    main()
