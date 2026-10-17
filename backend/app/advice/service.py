"""Advice = Gemini when it works, rules when it doesn't, hard rules always."""

import logging
from collections.abc import Awaitable, Callable

from . import rules
from .gemini import GeminiUnavailable, gemini_advice
from .models import Advice, AdviceResponse, BinSnapshot, Verdict

log = logging.getLogger(__name__)

GeminiFn = Callable[[str, BinSnapshot], Awaitable[Advice]]


async def check_scrap(scrap: str, snapshot: BinSnapshot, gemini: GeminiFn = gemini_advice) -> AdviceResponse:
    scrap = scrap.strip()
    category = rules.hard_avoid(scrap)

    try:
        advice, source = await gemini(scrap, snapshot), "gemini"
    except GeminiUnavailable as e:
        log.warning("Gemini unavailable, using rules: %s", e)
        advice, source = rules.rule_advice(scrap, snapshot), "rules"

    # Hard rules beat Gemini: meat, fish, bones, dairy, oil are always avoid.
    if category and advice.verdict != Verdict.avoid:
        advice = advice.model_copy(update={"verdict": Verdict.avoid, "reason": rules.avoid_reason(category)})

    advice = advice.model_copy(update={
        "suggest_add": advice.suggest_add[:3],
        "suggest_avoid": advice.suggest_avoid[:3],
    })
    return AdviceResponse(**advice.model_dump(), scrap=scrap, source=source, snapshot=snapshot)
