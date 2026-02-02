#!/usr/bin/env python3
"""NotebookLM Sidecar for Tauri App.

This sidecar receives commands from Tauri via command line arguments
and communicates via JSON on stdout.

Commands:
    login           - Open browser for Google login
    check-auth      - Check if authenticated
    process <file> <output_dir> - Full flow: upload, generate slides, download PDF
"""

import asyncio
import json
import os
import sys
from pathlib import Path


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


async def cmd_process(file_path: str, output_dir: str):
    """Full flow: create notebook, upload source, generate slides, download PDF."""
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
            title = f"Auto Slide: {file_path.name}"
            notebook = await client.notebooks.create(title)
            notebook_id = notebook.id
            emit("progress", f"Notebook created: {notebook_id}")

            # Add source
            emit("progress", f"Uploading source: {file_path.name}...")
            source = await client.sources.add_file(notebook_id, str(file_path))
            emit("progress", f"Source uploaded: {source.id}")

            # Generate slides
            emit("progress", "Generating slide deck...")
            status = await client.artifacts.generate_slide_deck(
                notebook_id,
                instructions="Create a comprehensive slide deck from this content."
            )
            emit("progress", f"Generation started, task_id: {status.task_id}")

            # Wait for completion
            emit("progress", "Waiting for slide generation to complete...")
            final_status = await client.artifacts.wait_for_completion(
                notebook_id,
                status.task_id,
                timeout=600.0  # 10 minutes max
            )

            if final_status.is_failed:
                emit_error(f"Slide generation failed: {final_status}")
                return

            emit("progress", "Slide generation complete!")

            # Download PDF
            output_file = output_dir / f"{file_path.stem}_slides.pdf"
            emit("progress", f"Downloading PDF to: {output_file}")

            downloaded_path = await client.artifacts.download_slide_deck(
                notebook_id,
                str(output_file)
            )

            emit("done", f"PDF downloaded: {downloaded_path}", output_path=str(downloaded_path))

    except FileNotFoundError as e:
        emit_error(f"Not authenticated. Run 'login' first. ({e})")
    except Exception as e:
        emit_error(f"Process failed: {e}")


def main():
    if len(sys.argv) < 2:
        emit_error("No command provided. Use: login, check-auth, or process <file> <output_dir>")
        return

    command = sys.argv[1]

    if command == "login":
        # Login is synchronous (uses sync_playwright)
        cmd_login()

    elif command == "check-auth":
        asyncio.run(cmd_check_auth())

    elif command == "process":
        if len(sys.argv) < 4:
            emit_error("Usage: process <file_path> <output_dir>")
            return
        file_path = sys.argv[2]
        output_dir = sys.argv[3]
        asyncio.run(cmd_process(file_path, output_dir))

    else:
        emit_error(f"Unknown command: {command}")


if __name__ == "__main__":
    main()
