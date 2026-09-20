from pydantic import BaseModel, Field, HttpUrl


class AnalyzeRequest(BaseModel):
    image_url: HttpUrl = Field(
        ...,
        description="Public or signed URL of a face image (already 720px wide).",
    )


class AnalyzeResponse(BaseModel):
    # MiVOLO v2 정수(반올림).
    age: int
    # "male" | "female" — Flutter Gender enum name.
    gender: str
    # Flutter Ethnicity enum name 6종 중 하나:
    #   "eastAsian" | "caucasian" | "african" |
    #   "southeastAsian" | "hispanic" | "middleEastern"
    ethnicity: str
    # 나이·성별을 낸 모델 — "mivolo_v2". 카드에 남겨 어느 식의 값인지 추적한다.
    ageModel: str


class ErrorResponse(BaseModel):
    error: str
    detail: str | None = None
