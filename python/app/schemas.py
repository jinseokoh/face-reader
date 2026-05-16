from pydantic import BaseModel, Field, HttpUrl


class AnalyzeRequest(BaseModel):
    image_url: HttpUrl = Field(
        ...,
        description="Public or signed URL of a face image (already 720px wide).",
    )


class AnalyzeResponse(BaseModel):
    age: int
    gender: str
    race: str


class ErrorResponse(BaseModel):
    error: str
    detail: str | None = None
