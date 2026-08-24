"""Single category-3 profile used by content build and audit tools."""

RANGES = ((1, 34), (47, 98), (100, 135), (150, 226), (387, 391), (409, 422))
EXPECTED_NUMBERS = {
    number
    for lower, upper in RANGES
    for number in range(lower, upper + 1)
}
BANK_COUNT = 218
MOCK_QUESTION_COUNT = 25
PASSING_SCORE = 20

assert len(EXPECTED_NUMBERS) == BANK_COUNT
