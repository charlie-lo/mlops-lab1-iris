"""Save the real MLflow run page for the run produced by train.py."""

import json
import os
import sys
from pathlib import Path

from mlflow import MlflowClient
from playwright.sync_api import TimeoutError as PlaywrightTimeout
from playwright.sync_api import sync_playwright


def main() -> None:
    metadata = json.loads(Path(sys.argv[1]).read_text())
    run = MlflowClient().get_run(metadata["run_id"])
    assert run.info.status == "FINISHED", run.info.status
    assert run.data.params["n_estimators"] == "100"
    assert run.data.metrics["accuracy"] == metadata["accuracy"]

    tracking_uri = os.environ["MLFLOW_TRACKING_URI"].rstrip("/")
    url = f"{tracking_uri}/#/experiments/{run.info.experiment_id}/runs/{run.info.run_id}"
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(channel="chrome", args=["--no-sandbox"])
        page = browser.new_page(viewport={"width": 1680, "height": 1400})
        page.goto(url)
        page.get_by_text(run.info.run_name, exact=True).first.wait_for(timeout=90_000)
        # MLflow can place parameters below the fold or behind a collapsed panel.
        # The API checks above establish the run contents regardless of UI layout.
        for label in ("accuracy", "n_estimators"):
            try:
                page.get_by_text(label, exact=True).first.wait_for(timeout=5_000)
            except PlaywrightTimeout:
                print(f"{label} is not visible in the initial run overview")
        print(page.locator("body").inner_text()[:3000])
        page.screenshot(path="screenshots/mlflow-run.png", full_page=True)
        browser.close()
    print(f"Captured run {run.info.run_id} (accuracy {metadata['accuracy']:.4f})")


if __name__ == "__main__":
    main()
