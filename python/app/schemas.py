from pydantic import BaseModel, Field, HttpUrl


class AnalyzeRequest(BaseModel):
    image_url: HttpUrl = Field(
        ...,
        description="Public or signed URL of a face image (already 720px wide).",
    )


class AnalyzeResponse(BaseModel):
    age: int
    # "male" | "female" — Flutter Gender enum name.
    gender: str
    # Flutter Ethnicity enum name 6종 중 하나:
    #   "eastAsian" | "caucasian" | "african" |
    #   "southeastAsian" | "hispanic" | "middleEastern"
    ethnicity: str


class ErrorResponse(BaseModel):
    error: str
    detail: str | None = None
