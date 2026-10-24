"""The ONE job a week — the model's proposal, validated against the challenge registry."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from healthee.challenges.day_verdicts import strap_measures
from healthee.challenges.metrics import CHALLENGE_METRICS, allows_cadence
from healthee.jobs.coach_checks import has_banned_phrase

_MAX_LINE = 160


class CoachJob(BaseModel):
    """A job as the model words it. The numbers are checked again by the sizing guard."""

    model_config = ConfigDict(extra="ignore")

    action: str = Field(min_length=3, max_length=_MAX_LINE)
    metric: str
    target: float = Field(gt=0)
    unit: str = Field(default="", max_length=24)
    days_required: int = Field(ge=1, le=7)
    slot: str = Field(min_length=1, max_length=_MAX_LINE)
    floor: str = Field(min_length=1, max_length=_MAX_LINE)
    counts_when: str = Field(min_length=1, max_length=_MAX_LINE)

    @field_validator("metric")
    @classmethod
    def _metric_is_checkable(cls, metric: str) -> str:
        """A real registry metric the STRAP measures, that improves upward, daily-scorable."""
        entry = CHALLENGE_METRICS.get(metric)
        if entry is None:
            raise ValueError(f"{metric!r} is not a challenge metric")
        if not strap_measures(metric) or entry.good != "up" or not allows_cadence(metric, "daily"):
            raise ValueError(f"{metric!r} cannot be a strap-checked daily job")
        return metric

    @model_validator(mode="after")
    def _no_safety_words(self) -> CoachJob:
        if has_banned_phrase(self.action, self.slot, self.floor, self.counts_when):
            raise ValueError("the job text contains a banned safety phrase")
        return self
