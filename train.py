import json
import os
from pathlib import Path

import joblib
import mlflow
import mlflow.sklearn
from sklearn.datasets import load_iris
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split


def main() -> None:
    features, labels = load_iris(return_X_y=True)
    seed = 42
    x_train, x_test, y_train, y_test = train_test_split(
        features, labels, test_size=0.2, random_state=seed, stratify=labels
    )
    model = RandomForestClassifier(n_estimators=100, random_state=seed)

    mlflow.set_tracking_uri(os.getenv("MLFLOW_TRACKING_URI", "sqlite:///mlflow.db"))
    mlflow.set_experiment("iris")
    with mlflow.start_run(run_name="iris-random-forest") as run:
        model.fit(x_train, y_train)
        accuracy = model.score(x_test, y_test)
        mlflow.log_params({"n_estimators": model.n_estimators, "random_state": seed})
        mlflow.log_metric("accuracy", accuracy)
        mlflow.sklearn.log_model(model, name="model", input_example=x_test[:1])
        joblib.dump(model, Path(__file__).with_name("model.pkl"))

    print(json.dumps({
        "run_id": run.info.run_id,
        "experiment_id": run.info.experiment_id,
        "accuracy": accuracy,
    }))


if __name__ == "__main__":
    main()
