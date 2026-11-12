"""Transaction wrapper shared by PostgreSQL and injected test stores."""


class Transaction:
    def __init__(self, runtime, connection=None):
        self.runtime = runtime
        self.connection = connection

    def execute(self, *args, **kwargs):
        return self.connection.execute(*args, **kwargs)
