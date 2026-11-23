from pathlib import Path

import joblib
from fastapi import FastAPI
from pydantic import BaseModel, Field, FiniteFloat


app = FastAPI(title="Iris prediction service")
model = joblib.load(Path(__file__).with_name("model.pkl"))


class PredictionRequest(BaseModel):
    # Features follow the Iris dataset order: sepal length, sepal width,
    # petal length, and petal width (all in cm).
    instances: list[tuple[FiniteFloat, FiniteFloat, FiniteFloat, FiniteFloat]] = Field(
        min_length=1
    )


@app.get("/healthz")
def health() -> dict[str, bool]:
    return {"ok": True}


@app.post("/predict")
def predict(request: PredictionRequest) -> dict[str, list[int]]:
    return {"predictions": model.predict(request.instances).tolist()}
