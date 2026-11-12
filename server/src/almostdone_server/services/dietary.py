import hashlib
import json


class DietaryService:
    def __init__(self, store):
        self.store = store

    def supported(self, db):
        return {'any'} | self.store.dietary_support(db)

    def context(self, db, user_id):
        supported = self.supported(db)
        decision = self.store.dietary_visibility(db, user_id)
        recipes = decision or {}
        version = hashlib.sha256(json.dumps(
            {'supported': sorted(supported), 'recipes': recipes}, sort_keys=True,
        ).encode()).hexdigest()[:24]
        return {'supported': supported, 'recipes': recipes, 'version': version,
                'database': self.store.persistent and decision is not None}
