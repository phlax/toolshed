

class preload:

    def __init__(self, *args, **kwargs):
        self.args = args
        self.kwargs = kwargs

    def __call__(self, fn, *args, **kwargs):
        self.fn = fn
        return self

    def __set_name__(self, owner, name):
        self.name = name
        owner.checks_data = getattr(owner, "checks_data", {})
        task_name = self.kwargs.pop("name", self.fn.__name__)
        self.kwargs["blocks"] = (
            self.kwargs["when"]
            + self.kwargs.get("blocks", []))
        owner.checks_data[task_name] = dict(run=self.fn, **self.kwargs)
