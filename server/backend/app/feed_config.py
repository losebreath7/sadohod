"""Versioned, server-only feed configuration. All signals normalized to [0, 1]."""
WEIGHTS = {
    'interest': .40,
    'popularity': .20,
    'freshness': .15,
    'quality': .10,
    'seller_rating': .10,
    'exploration': .05,
}
ALGORITHM = 'hybrid-v1'
PAGE_SIZE = 20
WINDOW_DAYS = 30
FRESH_DAYS = 14
SNAPSHOT_TTL = 1800
SNAPSHOT_LIMIT = 128
SELLER_CAP = 4
CATEGORY_CAP = 8
